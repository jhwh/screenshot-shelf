import SwiftUI

struct ShelfPanelView: View {
    @EnvironmentObject private var library: ScreenshotLibrary
    @EnvironmentObject private var settings: AppSettings
    @State private var showingSettings = false
    @State private var confirmClearAll = false
    @State private var clearAllCount = 0

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 10),
        GridItem(.flexible(minimum: 0), spacing: 10),
    ]

    var body: some View {
        ZStack {
            VisualEffectBackground()

            VStack(spacing: 0) {
                header
                Divider().opacity(0.35)
                if showingSettings {
                    SettingsPane()
                } else {
                    shelfContent
                }
                Divider().opacity(0.35)
                footer
            }
        }
        .frame(width: 400, height: 520)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: showingSettings ? "gearshape" : "camera.viewfinder")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(showingSettings ? "Settings" : "Screenshot Shelf")
                .font(.headline)
            Spacer()
            if !showingSettings {
                Text("\(library.items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var shelfContent: some View {
        if let accessError = library.accessError, library.items.isEmpty {
            emptyState(
                title: "Folder access needed",
                subtitle: "macOS blocked the watched folder.\n\(accessError)",
                buttonTitle: "Grant Folder Access…"
            ) {
                library.chooseWatchedFolder()
            }
        } else if library.items.isEmpty {
            emptyState(
                title: "No screenshots yet",
                subtitle: "Press ⌘⇧3, ⌘⇧4, or ⌘⇧5.\nMatching Screenshot and Zrzut ekranu files appear here.",
                buttonTitle: "Grant Folder Access…"
            ) {
                library.chooseWatchedFolder()
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(library.items) { item in
                        ScreenshotCell(item: item)
                    }
                }
                .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                showingSettings.toggle()
            } label: {
                Label(
                    showingSettings ? "Shelf" : "Settings",
                    systemImage: showingSettings ? "square.grid.2x2" : "gearshape"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            if !showingSettings, settings.enabledDestinations.isEmpty, !library.items.isEmpty {
                Button("Add destinations") {
                    showingSettings = true
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .help("Choose Cursor, Claude, or Codex in Settings. Only those apps appear on each screenshot.")
                .padding(.trailing, 10)
            }

            if !showingSettings, !library.items.isEmpty {
                Button("Clear All") {
                    clearAllCount = library.allWatchedScreenshotURLs().count
                    confirmClearAll = true
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .help("Move every watched screenshot to Trash")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .confirmationDialog(
            "Move \(clearAllCount) screenshot\(clearAllCount == 1 ? "" : "s") to Trash?",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                library.moveAllToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files stay in Trash until you empty it.")
        }
        .onChange(of: confirmClearAll) { _, isPresented in
            PanelDismissal.suppress = isPresented
        }
        .onDisappear {
            PanelDismissal.suppress = false
        }
    }

    private func emptyState(
        title: String,
        subtitle: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
