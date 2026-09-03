import Foundation
import SwiftUI

final class AppSettings: ObservableObject {
    private enum Keys {
        static let watchPictures = "watchPicturesScreenshots"
        static let redirectSystemScreenshots = "redirectSystemScreenshots"
        static let skipFloatingPreview = "skipFloatingPreview"
        static let openShelfOnCapture = "openShelfOnCapture"
        static let openHotKey = "openShelfHotKey"
        static let enabledDestinations = "enabledSendDestinations.v2"
        static let previousLocation = "previousSystemScreenshotLocation"
        static let previousLocationUnset = "previousSystemScreenshotLocationUnset"
        static let previousShowThumbnail = "previousShowThumbnail"
        static let previousShowThumbnailUnset = "previousShowThumbnailUnset"
    }

    @Published var watchPicturesScreenshots: Bool {
        didSet {
            UserDefaults.standard.set(watchPicturesScreenshots, forKey: Keys.watchPictures)
        }
    }

    @Published var redirectSystemScreenshots: Bool {
        didSet {
            UserDefaults.standard.set(redirectSystemScreenshots, forKey: Keys.redirectSystemScreenshots)
        }
    }

    @Published var skipFloatingPreview: Bool {
        didSet {
            UserDefaults.standard.set(skipFloatingPreview, forKey: Keys.skipFloatingPreview)
        }
    }

    @Published var openShelfOnCapture: Bool {
        didSet {
            UserDefaults.standard.set(openShelfOnCapture, forKey: Keys.openShelfOnCapture)
        }
    }

    @Published var openHotKey: ShelfHotKey? {
        didSet {
            persistOpenHotKey()
        }
    }

    @Published var openHotKeyConflict = false

    @Published var enabledDestinations: Set<SendDestination> {
        didSet {
            UserDefaults.standard.set(
                enabledDestinations.map(\.rawValue),
                forKey: Keys.enabledDestinations
            )
        }
    }

    var enabledDestinationsInOrder: [SendDestination] {
        SendDestination.allCases.filter { enabledDestinations.contains($0) }
    }

    func isDestinationEnabled(_ destination: SendDestination) -> Bool {
        enabledDestinations.contains(destination)
    }

    func setDestination(_ destination: SendDestination, enabled: Bool) {
        var next = enabledDestinations
        if enabled {
            next.insert(destination)
        } else {
            next.remove(destination)
        }
        enabledDestinations = next
    }

    func binding(for destination: SendDestination) -> Binding<Bool> {
        Binding(
            get: { self.enabledDestinations.contains(destination) },
            set: { self.setDestination(destination, enabled: $0) }
        )
    }

    init() {
        if UserDefaults.standard.object(forKey: Keys.watchPictures) == nil {
            watchPicturesScreenshots = true
        } else {
            watchPicturesScreenshots = UserDefaults.standard.bool(forKey: Keys.watchPictures)
        }
        redirectSystemScreenshots = UserDefaults.standard.bool(forKey: Keys.redirectSystemScreenshots)
        if UserDefaults.standard.object(forKey: Keys.skipFloatingPreview) == nil {
            skipFloatingPreview = true
        } else {
            skipFloatingPreview = UserDefaults.standard.bool(forKey: Keys.skipFloatingPreview)
        }
        if UserDefaults.standard.object(forKey: Keys.openShelfOnCapture) == nil {
            openShelfOnCapture = true
        } else {
            openShelfOnCapture = UserDefaults.standard.bool(forKey: Keys.openShelfOnCapture)
        }
        if let data = UserDefaults.standard.data(forKey: Keys.openHotKey) {
            if data.isEmpty {
                openHotKey = nil
            } else {
                openHotKey = (try? JSONDecoder().decode(ShelfHotKey.self, from: data)) ?? .defaultOpen
            }
        } else {
            openHotKey = .defaultOpen
        }
        if UserDefaults.standard.object(forKey: Keys.enabledDestinations) == nil {
            enabledDestinations = []
        } else {
            let stored = UserDefaults.standard.stringArray(forKey: Keys.enabledDestinations) ?? []
            enabledDestinations = Set(stored.compactMap(SendDestination.init(rawValue:)))
        }
    }

    func rememberSystemLocationIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.previousLocation) == nil,
              defaults.object(forKey: Keys.previousLocationUnset) == nil
        else { return }
        if let path = SystemScreenshotSettings.location?.path {
            defaults.set(path, forKey: Keys.previousLocation)
        } else {
            defaults.set(true, forKey: Keys.previousLocationUnset)
        }
    }

    func rememberThumbnailSettingIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.previousShowThumbnail) == nil,
              defaults.object(forKey: Keys.previousShowThumbnailUnset) == nil
        else { return }
        if SystemScreenshotSettings.hasExplicitThumbnailSetting {
            defaults.set(SystemScreenshotSettings.showsFloatingThumbnail, forKey: Keys.previousShowThumbnail)
        } else {
            defaults.set(true, forKey: Keys.previousShowThumbnailUnset)
        }
    }

    func restoreSystemLocation() throws {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Keys.previousLocationUnset) {
            try SystemScreenshotSettings.setLocation(nil)
        } else if let path = defaults.string(forKey: Keys.previousLocation) {
            try SystemScreenshotSettings.setLocation(URL(fileURLWithPath: path, isDirectory: true))
        } else {
            try SystemScreenshotSettings.setLocation(nil)
        }
        defaults.removeObject(forKey: Keys.previousLocation)
        defaults.removeObject(forKey: Keys.previousLocationUnset)
    }

    func restoreFloatingThumbnail() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Keys.previousShowThumbnailUnset) {
            SystemScreenshotSettings.setShowsFloatingThumbnail(true)
        } else if defaults.object(forKey: Keys.previousShowThumbnail) != nil {
            SystemScreenshotSettings.setShowsFloatingThumbnail(defaults.bool(forKey: Keys.previousShowThumbnail))
        } else {
            SystemScreenshotSettings.setShowsFloatingThumbnail(true)
        }
        defaults.removeObject(forKey: Keys.previousShowThumbnail)
        defaults.removeObject(forKey: Keys.previousShowThumbnailUnset)
    }

    private func persistOpenHotKey() {
        if let openHotKey, let data = try? JSONEncoder().encode(openHotKey) {
            UserDefaults.standard.set(data, forKey: Keys.openHotKey)
        } else {
            UserDefaults.standard.set(Data(), forKey: Keys.openHotKey)
        }
    }
}
