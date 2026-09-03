import SwiftUI

struct ScreenshotCell: View {
    let item: ScreenshotItem

    @EnvironmentObject private var library: ScreenshotLibrary
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var catalog: DestinationCatalog
    @StateObject private var thumbnail = ThumbnailLoader()
    @State private var hovering = false
    @State private var copied = false
    @State private var sentLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnailWell

            HStack(spacing: 6) {
                Text(ScreenshotTimeFormatter.caption(for: item.displayDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !settings.enabledDestinationsInOrder.isEmpty {
                    SendDestinationChips(item: item) { destination in
                        showSent(to: destination)
                    }
                    .layoutPriority(1)
                }

                Button {
                    library.moveToTrash(item)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(hovering ? .red.opacity(0.85) : .secondary)
                .opacity(hovering ? 1 : 0.45)
                .help("Move to Trash")
                .accessibilityLabel("Move screenshot to Trash")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .onAppear {
            thumbnail.load(url: item.url, modifiedAt: item.modifiedAt)
        }
        .onChange(of: item.modifiedAt) {
            thumbnail.load(url: item.url, modifiedAt: item.modifiedAt)
        }
        .contextMenu {
            Button("Copy") { copyImage() }
            Button("Reveal in Finder") { library.reveal(item) }
            sendContextMenu
            Divider()
            Button("Move to Trash", role: .destructive) { library.moveToTrash(item) }
        }
        .help("Click to copy · Drag into any app · App icons paste into the active session")
        .accessibilityLabel("Screenshot from \(ScreenshotTimeFormatter.caption(for: item.displayDate))")
    }

    @ViewBuilder
    private var sendContextMenu: some View {
        if !settings.enabledDestinationsInOrder.isEmpty {
            Menu("Send to") {
                ForEach(settings.enabledDestinationsInOrder) { destination in
                    sendContextItems(for: destination)
                }
            }
        }
    }

    @ViewBuilder
    private func sendContextItems(for destination: SendDestination) -> some View {
        let running = catalog.running.contains(destination)
        let windows = running ? DestinationWindowLister.windows(for: destination) : []
        if !running {
            Button(destination.title) {}
                .disabled(true)
        } else if windows.count > 1 {
            Menu(destination.title) {
                ForEach(windows) { window in
                    Button(window.title) {
                        Task { await send(destination, window: window) }
                    }
                }
            }
        } else {
            Button(destination.title) {
                Task { await send(destination, window: windows.first) }
            }
        }
    }

    private var thumbnailWell: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        return Color.primary.opacity(0.06)
            .aspectRatio(16 / 10, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack {
                    if let image = thumbnail.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }

                    FileDragView(
                        fileURL: item.url,
                        preview: thumbnail.image,
                        onClick: copyImage,
                        onCopy: copyImage,
                        onReveal: { library.reveal(item) },
                        onDelete: { library.moveToTrash(item) },
                        makeSendMenu: makeFileDragSendMenu
                    )

                    if let sentLabel {
                        shape.fill(Color.black.opacity(0.45))
                        Text(sentLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                    } else if copied {
                        shape.fill(Color.black.opacity(0.45))
                        Text("Copied")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .clipped()
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(Color.primary.opacity(hovering ? 0.22 : 0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.16 : 0), radius: hovering ? 6 : 0, y: hovering ? 2 : 0)
            .contentShape(shape)
    }

    private func makeFileDragSendMenu() -> NSMenu {
        SendDestinationMenu.makeNSMenu(
            destinations: settings.enabledDestinationsInOrder,
            running: catalog.running
        ) { destination, window in
            Task { await send(destination, window: window) }
        }
    }

    private func copyImage() {
        library.copyImage(of: item)
        copied = true
        sentLabel = nil
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            copied = false
        }
    }

    private func send(_ destination: SendDestination, window: DestinationWindow?) async {
        let result = await ScreenshotSender.send(
            item: item,
            destination: destination,
            window: window,
            library: library
        )
        if result == .sent {
            showSent(to: destination)
        }
    }

    private func showSent(to destination: SendDestination) {
        sentLabel = "Sent to \(destination.title)"
        copied = false
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            sentLabel = nil
        }
    }
}
