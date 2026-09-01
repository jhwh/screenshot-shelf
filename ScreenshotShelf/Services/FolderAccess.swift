import AppKit

final class FolderAccess {
    static let shared = FolderAccess()

    private let bookmarkKey = "primaryFolderBookmark"
    private var accessedURLs: [URL] = []

    var primaryFolder: URL {
        resolveBookmark() ?? defaultDesktop
    }

    var picturesScreenshotsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
    }

    var defaultDesktop: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    func beginAccess() {
        endAccess()
        accessIfPossible(primaryFolder)
        accessIfPossible(picturesScreenshotsFolder)
    }

    func endAccess() {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
    }

    func savePrimaryFolder(_ url: URL) {
        let data =
            (try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ))
            ?? (try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ))
        if let data {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        beginAccess()
    }

    @MainActor
    func pickPrimaryFolder() -> URL? {
        PanelDismissal.suppress = true
        defer { PanelDismissal.suppress = false }

        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = primaryFolder
        panel.message = "Choose the folder where screenshots are saved."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        savePrimaryFolder(url)
        return url
    }

    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            if stale {
                savePrimaryFolder(url)
            }
            return url
        }
        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    private func accessIfPossible(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            accessedURLs.append(url)
        }
    }
}
