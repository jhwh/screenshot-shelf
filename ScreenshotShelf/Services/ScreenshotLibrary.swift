import AppKit
import Combine

@MainActor
final class ScreenshotLibrary: ObservableObject {
    static let itemLimit = 30

    @Published private(set) var items: [ScreenshotItem] = []
    @Published private(set) var accessError: String?
    @Published private(set) var watchedFolderName = "Desktop"
    @Published private(set) var watchedFolderPath = ""
    @Published private(set) var systemCapturePath = ""
    @Published var systemCaptureError: String?

    private let folderAccess = FolderAccess.shared
    private let watcher = FolderWatcher()
    var onNewScreenshot: (() -> Void)?

    private var settings: AppSettings?
    private var debounceTask: Task<Void, Never>?
    private var settingsObserver: AnyCancellable?
    private var knownURLs = Set<URL>()
    private var hasCompletedInitialScan = false

    func configure(settings: AppSettings) {
        self.settings = settings
        settingsObserver = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadWatching()
            }
    }

    func start() {
        folderAccess.beginAccess()
        rescan()
        restartWatcher()
        applySystemCapturePreferences()
    }

    func stop() {
        debounceTask?.cancel()
        watcher.stop()
        folderAccess.endAccess()
    }

    func reloadWatching() {
        folderAccess.beginAccess()
        rescan()
        restartWatcher()
    }

    func rescan() {
        let primary = folderAccess.primaryFolder
        watchedFolderName = primary.lastPathComponent
        watchedFolderPath = primary.path

        var collected: [ScreenshotItem] = []
        do {
            collected.append(contentsOf: try scan(folder: primary))
            accessError = nil
        } catch {
            accessError = error.localizedDescription
        }

        if settings?.watchPicturesScreenshots == true {
            let extra = folderAccess.picturesScreenshotsFolder
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: extra.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                collected.append(contentsOf: (try? scan(folder: extra)) ?? [])
            }
        }

        let nextItems = Self.merge(collected)
            .sorted { $0.displayDate > $1.displayDate }
            .prefix(Self.itemLimit)
            .map { $0 }
        let nextURLs = Set(nextItems.map(\.url))

        if hasCompletedInitialScan {
            let now = Date()
            let sawFreshCapture = nextItems.contains { item in
                !knownURLs.contains(item.url) && now.timeIntervalSince(item.displayDate) < 45
            }
            if sawFreshCapture {
                Task { @MainActor [weak self] in
                    self?.onNewScreenshot?()
                }
            }
        }

        knownURLs = nextURLs
        hasCompletedInitialScan = true
        items = nextItems
    }

    @discardableResult
    func copyImage(of item: ScreenshotItem) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let fileURL = item.url as NSURL
        let image = NSImage(contentsOf: item.url)
        var objects: [NSPasteboardWriting] = [fileURL]
        if let image {
            objects.append(image)
        }
        guard pasteboard.writeObjects(objects) else { return false }

        if let image,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:])
        {
            pasteboard.setData(png, forType: .png)
        }
        return true
    }

    func reveal(_ item: ScreenshotItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func moveToTrash(_ item: ScreenshotItem) {
        items.removeAll { $0.url == item.url }
        NSWorkspace.shared.recycle([item.url]) { [weak self] _, _ in
            Task { @MainActor in
                self?.rescan()
            }
        }
    }

    func allWatchedScreenshotURLs() -> [URL] {
        var urls = (try? scan(folder: folderAccess.primaryFolder).map(\.url)) ?? []
        if settings?.watchPicturesScreenshots == true {
            urls.append(contentsOf: (try? scan(folder: folderAccess.picturesScreenshotsFolder).map(\.url)) ?? [])
        }
        return Array(Set(urls))
    }

    func moveAllToTrash() {
        let urls = allWatchedScreenshotURLs()
        guard !urls.isEmpty else { return }
        items = []
        NSWorkspace.shared.recycle(urls) { [weak self] _, _ in
            Task { @MainActor in
                self?.rescan()
            }
        }
    }

    func chooseWatchedFolder() {
        if folderAccess.pickPrimaryFolder() != nil {
            reloadWatching()
            applySystemCapturePreferences()
        }
    }

    func applySystemCapturePreferences() {
        guard let settings else {
            refreshSystemCapturePath()
            return
        }

        var needsReload = false
        do {
            if settings.redirectSystemScreenshots {
                settings.rememberSystemLocationIfNeeded()
                let folder = folderAccess.primaryFolder
                if !SystemScreenshotSettings.pathsMatch(SystemScreenshotSettings.location, folder) {
                    try SystemScreenshotSettings.setLocation(folder, reload: false)
                    needsReload = true
                }
            }
            if settings.skipFloatingPreview, SystemScreenshotSettings.showsFloatingThumbnail {
                settings.rememberThumbnailSettingIfNeeded()
                SystemScreenshotSettings.setShowsFloatingThumbnail(false, reload: false)
                needsReload = true
            }
            if needsReload {
                SystemScreenshotSettings.reloadCaptureUI()
            }
            systemCaptureError = nil
        } catch {
            systemCaptureError = error.localizedDescription
        }
        refreshSystemCapturePath()
    }

    func setRedirectsSystemScreenshots(_ enabled: Bool) {
        guard let settings else { return }
        settings.redirectSystemScreenshots = enabled
        do {
            if enabled {
                settings.rememberSystemLocationIfNeeded()
                try SystemScreenshotSettings.setLocation(folderAccess.primaryFolder)
            } else {
                try settings.restoreSystemLocation()
            }
            systemCaptureError = nil
        } catch {
            systemCaptureError = error.localizedDescription
        }
        refreshSystemCapturePath()
    }

    func setSkipsFloatingPreview(_ enabled: Bool) {
        guard let settings else { return }
        settings.skipFloatingPreview = enabled
        if enabled {
            settings.rememberThumbnailSettingIfNeeded()
            SystemScreenshotSettings.setShowsFloatingThumbnail(false)
        } else {
            settings.restoreFloatingThumbnail()
        }
        refreshSystemCapturePath()
    }

    private func refreshSystemCapturePath() {
        systemCapturePath = SystemScreenshotSettings.location?.path
            ?? folderAccess.defaultDesktop.path
    }

    private func restartWatcher() {
        var paths = [folderAccess.primaryFolder.path]
        if settings?.watchPicturesScreenshots == true {
            let extra = folderAccess.picturesScreenshotsFolder
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: extra.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                paths.append(extra.path)
            }
        }
        watcher.start(paths: paths) { [weak self] in
            Task { @MainActor in
                self?.scheduleRescan()
            }
        }
    }

    private func scheduleRescan() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self.rescan()
        }
    }

    private func scan(folder: URL) throws -> [ScreenshotItem] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .creationDateKey,
            .contentModificationDateKey,
        ]
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: []
        )

        return entries.compactMap { url in
            let name = url.lastPathComponent
            guard ScreenshotMatcher.isScreenshot(filename: name) else { return nil }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { return nil }
            let created = values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
            let modified = values?.contentModificationDate ?? created
            return ScreenshotItem(
                url: url,
                createdAt: created,
                modifiedAt: modified,
                isHiddenStaging: name.hasPrefix(".")
            )
        }
    }

    private static func merge(_ items: [ScreenshotItem]) -> [ScreenshotItem] {
        var byName: [String: ScreenshotItem] = [:]
        for item in items {
            let key = ScreenshotMatcher.canonicalName(item.url.lastPathComponent)
            if let existing = byName[key] {
                if existing.isHiddenStaging && !item.isHiddenStaging {
                    byName[key] = item
                } else if existing.isHiddenStaging == item.isHiddenStaging,
                          item.displayDate > existing.displayDate
                {
                    byName[key] = item
                }
            } else {
                byName[key] = item
            }
        }
        return Array(byName.values)
    }
}
