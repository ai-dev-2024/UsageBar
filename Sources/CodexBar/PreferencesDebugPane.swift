import AppKit
import SwiftUI

@MainActor
struct DebugPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var store: UsageStore
    @State private var currentLogProvider: UsageProvider = .codex
    @State private var isLoadingLog = false
    @State private var logText: String = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection {
                    PreferenceToggleRow(
                        title: "Force animation on next refresh",
                        subtitle: "Temporarily shows the loading animation after the next refresh.",
                        binding: self.$store.debugForceAnimation)
                }

                SettingsSection(
                    title: "Loading animations",
                    caption: "Pick a pattern and replay it in the menu bar. \"Random\" keeps the existing behavior.")
                {
                    Picker("Animation pattern", selection: self.animationPatternBinding) {
                        Text("Random (default)").tag(nil as LoadingPattern?)
                        ForEach(LoadingPattern.allCases) { pattern in
                            Text(pattern.displayName).tag(Optional(pattern))
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Button("Replay selected animation") {
                        self.replaySelectedAnimation()
                    }
                    .keyboardShortcut(.defaultAction)
                }

                SettingsSection(
                    title: "Probe logs",
                    caption: "Fetch the latest PTY scrape for Codex or Claude; Copy keeps the full text.")
                {
                    Picker("Provider", selection: self.$currentLogProvider) {
                        Text("Codex").tag(UsageProvider.codex)
                        Text("Claude").tag(UsageProvider.claude)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)

                    HStack(spacing: 12) {
                        Button { self.loadLog(self.currentLogProvider) } label: {
                            Label("Fetch log", systemImage: "arrow.clockwise")
                        }
                        .disabled(self.isLoadingLog)

                        Button { self.copyToPasteboard(self.logText) } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .disabled(self.logText.isEmpty)

                        Button { self.saveLog(self.currentLogProvider) } label: {
                            Label("Save to file", systemImage: "externaldrive.badge.plus")
                        }
                        .disabled(self.isLoadingLog && self.logText.isEmpty)

                        if self.currentLogProvider == .claude {
                            Button { self.loadClaudeDump() } label: {
                                Label("Load parse dump", systemImage: "doc.text.magnifyingglass")
                            }
                            .disabled(self.isLoadingLog)
                        }
                    }

                    Button {
                        self.settings.rerunProviderDetection()
                        self.loadLog(self.currentLogProvider)
                    } label: {
                        Label("Re-run provider autodetect", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .controlSize(.small)

                    ZStack(alignment: .topLeading) {
                        ScrollView {
                            Text(self.displayedLog)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(minHeight: 160, maxHeight: 220)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)

                        if self.isLoadingLog {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                .padding()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var animationPatternBinding: Binding<LoadingPattern?> {
        Binding(
            get: { self.settings.debugLoadingPattern },
            set: { self.settings.debugLoadingPattern = $0 })
    }

    private func replaySelectedAnimation() {
        var userInfo: [AnyHashable: Any] = [:]
        if let pattern = self.settings.debugLoadingPattern {
            userInfo["pattern"] = pattern.rawValue
        }
        NotificationCenter.default.post(
            name: .codexbarDebugReplayAllAnimations,
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo)
        self.store.replayLoadingAnimation(duration: 4)
    }

    private var displayedLog: String {
        if self.logText.isEmpty {
            return self.isLoadingLog ? "Loading…" : "No log yet. Fetch to load."
        }
        return self.logText
    }

    private func loadLog(_ provider: UsageProvider) {
        self.isLoadingLog = true
        Task {
            let text = await self.store.debugLog(for: provider)
            await MainActor.run {
                self.logText = text
                self.isLoadingLog = false
            }
        }
    }

    private func saveLog(_ provider: UsageProvider) {
        Task {
            if self.logText.isEmpty {
                self.isLoadingLog = true
                let text = await self.store.debugLog(for: provider)
                await MainActor.run { self.logText = text }
                self.isLoadingLog = false
            }
            _ = await self.store.dumpLog(toFileFor: provider)
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func loadClaudeDump() {
        self.isLoadingLog = true
        Task {
            let text = await self.store.debugClaudeDump()
            await MainActor.run {
                self.logText = text
                self.isLoadingLog = false
            }
        }
    }
}
