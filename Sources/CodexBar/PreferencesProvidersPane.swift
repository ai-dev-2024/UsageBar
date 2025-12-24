import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct ProvidersPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @State private var expandedErrors: Set<UsageProvider> = []
    @State private var openAIDashboardStatus: String?
    @State private var showOpenAIWebFullDiskAccessAlert = false
    @State private var lastOpenAIWebFullDiskAccessRetryAt: Date?
    @State private var claudeWebStatus: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 12) {
                    Text("Providers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    VStack(alignment: .leading, spacing: 8) {
                        PreferenceToggleRow(
                            title: self.store.metadata(for: .codex).toggleTitle,
                            subtitle: self.providerSubtitle(.codex),
                            binding: self.codexBinding)

                        self.codexSigningStatus()
                        if self.codexBinding.wrappedValue {
                            self.openAIDashboardLogin()
                                .padding(.leading, 22)
                        }
                    }
                    .padding(.bottom, 10)

                    if let display = self.providerErrorDisplay(.codex) {
                        ProviderErrorView(
                            title: "Last Codex fetch failed:",
                            display: display,
                            isExpanded: self.expandedBinding(for: .codex),
                            onCopy: { self.copyToPasteboard(display.full) })
                            .padding(.bottom, 8)
                    }

                    PreferenceToggleRow(
                        title: self.store.metadata(for: .claude).toggleTitle,
                        subtitle: self.providerSubtitle(.claude),
                        binding: self.claudeBinding)

                    if self.claudeBinding.wrappedValue {
                        self.claudeWebExtras()
                            .padding(.leading, 22)
                    }

                    if let display = self.providerErrorDisplay(.claude) {
                        ProviderErrorView(
                            title: "Last Claude fetch failed:",
                            display: display,
                            isExpanded: self.expandedBinding(for: .claude),
                            onCopy: { self.copyToPasteboard(display.full) })
                    }

                    PreferenceToggleRow(
                        title: self.store.metadata(for: .gemini).toggleTitle,
                        subtitle: self.providerSubtitle(.gemini),
                        binding: self.geminiBinding)

                    if let display = self.providerErrorDisplay(.gemini) {
                        ProviderErrorView(
                            title: "Last Gemini fetch failed:",
                            display: display,
                            isExpanded: self.expandedBinding(for: .gemini),
                            onCopy: { self.copyToPasteboard(display.full) })
                    }

                    PreferenceToggleRow(
                        title: self.store.metadata(for: .antigravity).toggleTitle,
                        subtitle: self.providerSubtitle(.antigravity),
                        binding: self.antigravityBinding)

                    if let display = self.providerErrorDisplay(.antigravity) {
                        ProviderErrorView(
                            title: "Last Antigravity fetch failed:",
                            display: display,
                            isExpanded: self.expandedBinding(for: .antigravity),
                            onCopy: { self.copyToPasteboard(display.full) })
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            if self.settings.claudeWebExtrasEnabled {
                self.refreshClaudeWebStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.retryOpenAIWebAfterPermissionChangeIfNeeded()
        }
        .onChange(of: self.settings.claudeWebExtrasEnabled) { _, enabled in
            if enabled {
                self.refreshClaudeWebStatus()
            } else {
                self.claudeWebStatus = nil
            }
        }
    }

    private var codexBinding: Binding<Bool> { self.binding(for: .codex) }
    private var claudeBinding: Binding<Bool> { self.binding(for: .claude) }
    private var geminiBinding: Binding<Bool> { self.binding(for: .gemini) }
    private var antigravityBinding: Binding<Bool> { self.binding(for: .antigravity) }

    private func binding(for provider: UsageProvider) -> Binding<Bool> {
        let meta = self.store.metadata(for: provider)
        return Binding(
            get: { self.settings.isProviderEnabled(provider: provider, metadata: meta) },
            set: { self.settings.setProviderEnabled(provider: provider, metadata: meta, enabled: $0) })
    }

    private func providerSubtitle(_ provider: UsageProvider) -> String {
        let meta = self.store.metadata(for: provider)
        let cliName = meta.cliName
        let version = self.store.version(for: provider)
        var versionText = version ?? "not detected"
        if provider == .claude, let parenRange = versionText.range(of: "(") {
            versionText = versionText[..<parenRange.lowerBound].trimmingCharacters(in: .whitespaces)
        }

        let usageText: String
        if let snapshot = self.store.snapshot(for: provider) {
            let timestamp = snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened)
            usageText = "usage fetched \(timestamp)"
        } else if self.store.isStale(provider: provider) {
            usageText = "last fetch failed"
        } else {
            usageText = "usage not fetched yet"
        }

        if cliName == "codex" {
            return "\(versionText) • \(usageText)"
        }

        var detail = "\(cliName) \(versionText) • \(usageText)"
        if provider == .antigravity {
            detail += " • experimental"
        }
        return detail
    }

    private func providerErrorDisplay(_ provider: UsageProvider) -> ProviderErrorDisplay? {
        guard self.store.isStale(provider: provider), let raw = self.store.error(for: provider) else { return nil }
        let meta = self.store.metadata(for: provider)
        let prefix = "Last \(meta.displayName) fetch failed: "
        return ProviderErrorDisplay(
            preview: self.truncated(raw, prefix: prefix),
            full: raw)
    }

    @ViewBuilder
    private func openAIDashboardLogin() -> some View {
        SettingsSection(contentSpacing: 10) {
            PreferenceToggleRow(
                title: "Augment Codex via web",
                subtitle: [
                    "Uses your Safari/Chrome session cookies to add extra dashboard fields.",
                    "Adds Code review + Usage breakdown.",
                    "Safari → Chrome.",
                ].joined(separator: " "),
                binding: self.$settings.openAIDashboardEnabled)

            if self.settings.openAIDashboardEnabled {
                let status = self.openAIDashboardStatus ??
                    self.store.openAIDashboardCookieImportStatus ??
                    self.store.lastOpenAIDashboardError

                if let status, !status.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)

                        if self.needsOpenAIWebFullDiskAccess(status: status) {
                            Button("Fix: enable Full Disk Access…") {
                                self.showOpenAIWebFullDiskAccessAlert = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .alert("Enable Full Disk Access", isPresented: self.$showOpenAIWebFullDiskAccessAlert) {
                                Button("Open System Settings") {
                                    Self.openFullDiskAccessSettings()
                                    self.openAIDashboardStatus = "Waiting for Full Disk Access…"
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(
                                    [
                                        "CodexBar needs Full Disk Access to read Safari cookies " +
                                            "(required for OpenAI web scraping).",
                                        "System Settings → Privacy & Security → Full Disk Access " +
                                            "→ add/enable CodexBar.",
                                        "Then re-toggle “Access OpenAI via web” to import cookies again.",
                                    ].joined(separator: "\n"))
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: self.settings.openAIDashboardEnabled) { _, enabled in
            if enabled {
                self.openAIDashboardStatus = "Importing cookies…"
                Task { @MainActor in
                    await self.store.importOpenAIDashboardBrowserCookiesNow()
                    self.openAIDashboardStatus = nil
                }
            } else {
                self.openAIDashboardStatus = nil
            }
        }
    }

    @ViewBuilder
    private func claudeWebExtras() -> some View {
        SettingsSection(contentSpacing: 10) {
            PreferenceToggleRow(
                title: "Augment Claude via web",
                subtitle: [
                    "Uses your Safari/Chrome session cookies to add extra dashboard fields.",
                    "Adds reset timestamps + Extra usage spend/limit.",
                    "Safari → Chrome.",
                ].joined(separator: " "),
                binding: self.$settings.claudeWebExtrasEnabled)

            if self.settings.claudeWebExtrasEnabled {
                if let status = self.claudeWebStatus, !status.isEmpty {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        }
    }

    @ViewBuilder
    private func codexSigningStatus() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let credits = self.store.credits {
                Text("Codex credits")
                    .font(.footnote.weight(.semibold))
                Text(self.creditsSummary(credits))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let hint = self.store.lastCreditsError ?? "Credits unavailable; keep Codex running to refresh."
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let lastError = self.store.lastCreditsError {
                Text(self.truncated(lastError, prefix: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refreshClaudeWebStatus() {
        let expectedEmail = self.store.snapshot(for: .claude)?.accountEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.claudeWebStatus = "Checking Claude cookies…"
        Task { @MainActor in
            let status = await self.loadClaudeWebStatus(expectedEmail: expectedEmail)
            self.claudeWebStatus = status
        }
    }

    private func loadClaudeWebStatus(expectedEmail: String?) async -> String {
        await Task.detached(priority: .utility) {
            do {
                let info = try ClaudeWebAPIFetcher.sessionKeyInfo()
                var parts = ["Using \(info.sourceLabel) cookies (\(info.cookieCount))."]

                do {
                    let usage = try await ClaudeWebAPIFetcher.fetchUsage(using: info)
                    if let rawEmail = usage.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !rawEmail.isEmpty
                    {
                        if let expectedEmail, !expectedEmail.isEmpty {
                            let matches = rawEmail.lowercased() == expectedEmail.lowercased()
                            let matchText = matches ? "matches Claude" : "does not match Claude"
                            parts.append("Signed in as \(rawEmail) (\(matchText)).")
                        } else {
                            parts.append("Signed in as \(rawEmail).")
                        }
                    }
                } catch {
                    parts.append("Signed-in status unavailable: \(error.localizedDescription)")
                }

                return parts.joined(separator: " ")
            } catch {
                return "Browser cookie import failed: \(error.localizedDescription)"
            }
        }.value
    }

    private func truncated(_ text: String, prefix: String, maxLength: Int = 160) -> String {
        var message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.count > maxLength {
            let idx = message.index(message.startIndex, offsetBy: maxLength)
            message = "\(message[..<idx])…"
        }
        return prefix + message
    }

    private func creditsSummary(_ snapshot: CreditsSnapshot) -> String {
        let amount = snapshot.remaining.formatted(.number.precision(.fractionLength(0...2)))
        let timestamp = snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return "Remaining \(amount) credits as of \(timestamp)."
    }

    private func expandedBinding(for provider: UsageProvider) -> Binding<Bool> {
        Binding(
            get: { self.expandedErrors.contains(provider) },
            set: { expanded in
                if expanded {
                    self.expandedErrors.insert(provider)
                } else {
                    self.expandedErrors.remove(provider)
                }
            })
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - OpenAI dashboard auth

    private func needsOpenAIWebFullDiskAccess(status: String) -> Bool {
        let s = status.lowercased()
        return s.contains("full disk access") && s.contains("safari")
    }

    private func retryOpenAIWebAfterPermissionChangeIfNeeded() {
        guard self.settings.openAIDashboardEnabled else { return }
        let status = self.openAIDashboardStatus ??
            self.store.openAIDashboardCookieImportStatus ??
            self.store.lastOpenAIDashboardError

        guard let status, self.needsOpenAIWebFullDiskAccess(status: status) else { return }

        let now = Date()
        if let last = self.lastOpenAIWebFullDiskAccessRetryAt, now.timeIntervalSince(last) < 5 {
            return
        }
        self.lastOpenAIWebFullDiskAccessRetryAt = now

        self.openAIDashboardStatus = "Re-checking Full Disk Access…"
        Task { @MainActor in
            await self.store.importOpenAIDashboardBrowserCookiesNow()
            self.openAIDashboardStatus = nil
        }
    }

    private static func openFullDiskAccessSettings() {
        // Best-effort deep link. On macOS 13 beta it used to open the wrong pane, but this has been stable on
        // modern macOS releases again. Fall back to the Privacy pane if needed.
        let urls: [URL] = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security"),
        ].compactMap(\.self)

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }
}

private struct ProviderErrorDisplay: Sendable {
    let preview: String
    let full: String
}

@MainActor
private struct ProviderErrorView: View {
    let title: String
    let display: ProviderErrorDisplay
    @Binding var isExpanded: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(self.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                self.onCopy()
            } label: {
                Text(self.display.preview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button("Copy full error") { self.onCopy() }
                    .buttonStyle(.link)
                Button(self.isExpanded ? "Hide details" : "Show details") { self.isExpanded.toggle() }
                    .buttonStyle(.link)
            }
            .font(.footnote)

            if self.isExpanded {
                Text(self.display.full)
                    .font(.footnote)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 2)
    }
}
