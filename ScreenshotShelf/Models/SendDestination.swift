import Foundation

enum SendDestination: String, CaseIterable, Identifiable, Hashable {
    case cursor
    case claudeDesktop
    case claudeCode
    case codex
    case codexCLI
    case slack
    case grokBot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "Cursor"
        case .claudeDesktop: return "Claude Desktop"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .codexCLI: return "Codex CLI"
        case .slack: return "Slack"
        case .grokBot: return "Grok Bot"
        }
    }

    var shortTitle: String {
        switch self {
        case .cursor: return "Cursor"
        case .claudeDesktop: return "Claude"
        case .claudeCode: return "Code"
        case .codex: return "Codex"
        case .codexCLI: return "CLI"
        case .slack: return "Slack"
        case .grokBot: return "Grok"
        }
    }

    var sendTitle: String {
        "Send to \(title)"
    }

    var compactSendTitle: String {
        "Send to \(shortTitle)"
    }

    var symbolName: String {
        switch self {
        case .cursor: return "chevron.left.forwardslash.chevron.right"
        case .claudeDesktop: return "bubble.left.and.bubble.right"
        case .claudeCode: return "terminal"
        case .codex: return "sparkles"
        case .codexCLI: return "apple.terminal"
        case .slack: return "number"
        case .grokBot: return "bolt"
        }
    }

    var subtitle: String {
        switch self {
        case .cursor:
            return "Pastes with ⌘V into the front Cursor window. Focus the chat composer first if you can."
        case .claudeDesktop:
            return "Pastes with ⌘V into the active Claude Desktop chat."
        case .claudeCode:
            return "Pastes with Ctrl+V into Claude Code or a terminal window you pick."
        case .codex:
            return "Pastes with ⌘V into Codex / ChatGPT.app."
        case .codexCLI:
            return "Pastes with Ctrl+V into a terminal window you pick."
        case .slack:
            return "Pastes with ⌘V into the Slack window you pick. Focus the message field first if you can."
        case .grokBot:
            return "Pastes with ⌘V into the active Grok Bot chat."
        }
    }

    var usesControlPaste: Bool {
        switch self {
        case .cursor, .claudeDesktop, .codex, .slack, .grokBot:
            return false
        case .claudeCode, .codexCLI:
            return true
        }
    }

    var dedicatedBundleIDs: [String] {
        switch self {
        case .cursor:
            return [
                "com.todesktop.230313mzl4w4u92",
                "co.anysphere.cursor.nightly",
            ]
        case .claudeDesktop:
            return ["com.anthropic.claudefordesktop"]
        case .claudeCode:
            return ["com.anthropic.claude-code"]
        case .codex:
            return [
                "com.openai.codex",
                "com.openai.chat",
            ]
        case .codexCLI:
            return []
        case .slack:
            return ["com.tinyspeck.slackmacgap"]
        case .grokBot:
            return ["com.anysphere.sand"]
        }
    }

    var lookupBundleIDs: [String] {
        if includesTerminalHosts {
            return dedicatedBundleIDs + Self.terminalHostBundleIDs
        }
        return dedicatedBundleIDs
    }

    var includesTerminalHosts: Bool {
        switch self {
        case .claudeCode, .codexCLI:
            return true
        case .cursor, .claudeDesktop, .codex, .slack, .grokBot:
            return false
        }
    }

    var triesComposerFocus: Bool {
        switch self {
        case .cursor, .slack, .grokBot:
            return true
        case .claudeDesktop, .claudeCode, .codex, .codexCLI:
            return false
        }
    }

    static let terminalHostBundleIDs = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty",
    ]
}
