import Foundation

struct ScreenshotItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let createdAt: Date
    let modifiedAt: Date
    let isHiddenStaging: Bool

    var displayDate: Date { createdAt }
}

enum ScreenshotMatcher {
    static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp"]

    static func isScreenshot(filename: String) -> Bool {
        let visible = visibleName(filename)
        let ext = (visible as NSString).pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else { return false }
        let stem = (visible as NSString).deletingPathExtension
        return stem.hasPrefix("Screenshot ") || stem.hasPrefix("Zrzut ekranu ")
    }

    static func canonicalName(_ filename: String) -> String {
        visibleName(filename)
    }

    private static func visibleName(_ filename: String) -> String {
        filename.hasPrefix(".") ? String(filename.dropFirst()) : filename
    }
}

enum ScreenshotTimeFormatter {
    private static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayAndTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func caption(for date: Date) -> String {
        let calendar = Calendar.current
        let time = timeOnly.string(from: date)
        if calendar.isDateInToday(date) {
            return time
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(time)"
        }
        return dayAndTime.string(from: date)
    }
}
