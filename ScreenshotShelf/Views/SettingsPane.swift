import AppKit
import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject private var library: ScreenshotLibrary
    @EnvironmentObject private var settings: AppSettings

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var accessibilityTrusted = ScreenshotSender.isTrusted()

    var body: some View {
        Form {
            Section("Destinations") {
                Text("Turn on only the apps you use. Those are the only Send buttons that appear on each screenshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(SendDestination.allCases) { destination in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(destination.title, isOn: settings.binding(for: destination))
                        Text(destination.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if accessibilityTrusted {
                    Text("Accessibility is on. Send can paste into the active session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This signed copy is not trusted yet. Remove the old Screenshot Shelf row in Accessibility, then allow the new prompt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Bundle.main.bundlePath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                    Button("Open Accessibility Settings") {
                        ScreenshotSender.openAccessibilitySettings()
                    }
                }
            }

            Section("Watched folders") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Primary folder")
                    Text(library.watchedFolderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Button("Choose Folder…") {
                        library.chooseWatchedFolder()
                    }
                }

                Toggle("Also watch Pictures/Screenshots", isOn: $settings.watchPicturesScreenshots)
                Text("Optional extra folder at ~/Pictures/Screenshots. Screenshots stay where they are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System screenshots") {
                Toggle("Save new screenshots to this folder", isOn: redirectBinding)
                Text("Same as ⌘⇧5 → Options → Save to. Shelf then sees each capture immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Skip floating preview", isOn: skipPreviewBinding)
                Text("Turns off the corner thumbnail so the file is written right away.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("macOS currently saves to \(library.systemCapturePath)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)

                if let systemCaptureError = library.systemCaptureError {
                    Text(systemCaptureError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Shelf") {
                Toggle("Open on new screenshot", isOn: $settings.openShelfOnCapture)
                Text("Show the shelf as soon as a capture lands in a watched folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Keyboard shortcut")
                    Spacer()
                    HotKeyRecorder(hotKey: $settings.openHotKey)
                }
                Text("Toggle the shelf from any app. Default is ⌥⌘S.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.openHotKeyConflict {
                    Text("That shortcut is already used by macOS or another app. Pick a different combo.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                Text("Works most reliably after you copy Screenshot Shelf to /Applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Quit Screenshot Shelf", role: .destructive) {
                    NSApp.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            accessibilityTrusted = ScreenshotSender.isTrusted()
            library.applySystemCapturePreferences()
        }
    }

    private var redirectBinding: Binding<Bool> {
        Binding(
            get: { settings.redirectSystemScreenshots },
            set: { library.setRedirectsSystemScreenshots($0) }
        )
    }

    private var skipPreviewBinding: Binding<Bool> {
        Binding(
            get: { settings.skipFloatingPreview },
            set: { library.setSkipsFloatingPreview($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = LaunchAtLogin.isEnabled
                    launchError = nil
                } catch {
                    launchAtLogin = LaunchAtLogin.isEnabled
                    launchError = error.localizedDescription
                }
            }
        )
    }
}
