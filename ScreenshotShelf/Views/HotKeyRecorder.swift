import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorder: View {
    @Binding var hotKey: ShelfHotKey?

    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(label)
                    .font(.caption.weight(.semibold).monospaced())
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundStyle(isRecording ? Color.accentColor : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(isRecording ? 0.10 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                Color.accentColor.opacity(isRecording ? 0.55 : 0.14),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Press a key combo, or Esc to cancel" : "Click to record a new shortcut")

            if hotKey != nil {
                Button {
                    hotKey = nil
                    stopRecording()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .background(
            HotKeyCaptureRepresentable(isRecording: isRecording, onKeyDown: handleKey)
        )
        .onChange(of: isRecording) { _, recording in
            publishRecording(recording)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var label: String {
        if isRecording {
            return "Type shortcut"
        }
        return hotKey?.displayString ?? "None"
    }

    private func toggleRecording() {
        isRecording.toggle()
        if !isRecording {
            publishRecording(false)
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
    }

    private func publishRecording(_ recording: Bool) {
        HotKeyRecording.isActive = recording
        NotificationCenter.default.post(name: .hotKeyRecordingDidChange, object: nil)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.isARepeat { return true }

        switch Int(event.keyCode) {
        case kVK_Escape:
            isRecording = false
            return true
        case kVK_Delete, kVK_ForwardDelete:
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers.isEmpty {
                hotKey = nil
                isRecording = false
                return true
            }
        default:
            break
        }

        if let captured = ShelfHotKey(event: event) {
            hotKey = captured
            isRecording = false
        }
        return true
    }
}

private struct HotKeyCaptureRepresentable: NSViewRepresentable {
    var isRecording: Bool
    var onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> CaptureView {
        CaptureView()
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onKeyDown = onKeyDown
        view.setRecording(isRecording)
    }

    final class CaptureView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        private var monitor: Any?

        func setRecording(_ recording: Bool) {
            if recording {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let onKeyDown else { return event }
                    return onKeyDown(event) ? nil : event
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
