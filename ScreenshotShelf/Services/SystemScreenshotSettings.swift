import Foundation

enum SystemScreenshotSettings {
    private static let suite = "com.apple.screencapture"
    private static let locationKey = "location"
    private static let locationLastKey = "location-last"
    private static let thumbnailKey = "show-thumbnail"

    static var location: URL? {
        guard let path = string(for: locationKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var showsFloatingThumbnail: Bool {
        bool(for: thumbnailKey) ?? true
    }

    static var hasExplicitThumbnailSetting: Bool {
        store.object(forKey: thumbnailKey) != nil
    }

    static func setLocation(_ folder: URL?, reload: Bool = true) throws {
        if let folder {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            set(folder.path, for: locationKey)
            set(folder.path, for: locationLastKey)
        } else {
            remove(locationKey)
            remove(locationLastKey)
        }
        if reload {
            reloadCaptureUI()
        }
    }

    static func setShowsFloatingThumbnail(_ show: Bool, reload: Bool = true) {
        set(show, for: thumbnailKey)
        if reload {
            reloadCaptureUI()
        }
    }

    static func pathsMatch(_ lhs: URL?, _ rhs: URL?) -> Bool {
        lhs?.standardizedFileURL.path == rhs?.standardizedFileURL.path
    }

    static func reloadCaptureUI() {
        for name in ["screencaptureui", "SystemUIServer"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    private static var store: UserDefaults {
        UserDefaults(suiteName: suite) ?? .standard
    }

    private static func string(for key: String) -> String? {
        store.string(forKey: key)
    }

    private static func bool(for key: String) -> Bool? {
        guard store.object(forKey: key) != nil else { return nil }
        return store.bool(forKey: key)
    }

    private static func set(_ value: Any, for key: String) {
        store.set(value, forKey: key)
        store.synchronize()
        CFPreferencesAppSynchronize(suite as CFString)
    }

    private static func remove(_ key: String) {
        store.removeObject(forKey: key)
        store.synchronize()
        CFPreferencesAppSynchronize(suite as CFString)
    }
}
