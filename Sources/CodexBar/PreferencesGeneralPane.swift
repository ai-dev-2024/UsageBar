import AppKit
import SwiftUI

@MainActor
struct GeneralPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 12) {
                    Text("Notifications")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    PreferenceToggleRow(
                        title: "Session quota notifications",
                        subtitle: "Notifies when the 5-hour session quota hits 0% and when it becomes available again.",
                        binding: self.$settings.sessionQuotaNotificationsEnabled)
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    Text("System")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    PreferenceToggleRow(
                        title: "Start at Login",
                        subtitle: "Automatically opens CodexBar when you start your Mac.",
                        binding: self.$settings.launchAtLogin)
                    HStack {
                        Spacer()
                        Button("Quit CodexBar") { NSApp.terminate(nil) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                    .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}
