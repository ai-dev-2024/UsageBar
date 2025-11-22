import AppKit
import Combine
import Foundation

enum IconStyle {
    case codex
    case claude
    case combined
}

enum UsageProvider: String, CaseIterable {
    case codex
    case claude
}

struct ProviderMetadata {
    let id: UsageProvider
    let displayName: String
    let sessionLabel: String
    let weeklyLabel: String
    let opusLabel: String?
    let supportsOpus: Bool
    let supportsCredits: Bool
    let creditsHint: String
    let toggleTitle: String
    let cliName: String
    let defaultEnabled: Bool
    let dashboardURL: String?
}

/// Tracks consecutive failures so we can ignore a single flake when we previously had fresh data.
struct ConsecutiveFailureGate {
    private(set) var streak: Int = 0

    mutating func recordSuccess() {
        self.streak = 0
    }

    mutating func reset() {
        self.streak = 0
    }

    /// Returns true when the caller should surface the error to the UI.
    mutating func shouldSurfaceError(onFailureWithPriorData hadPriorData: Bool) -> Bool {
        self.streak += 1
        if hadPriorData, self.streak == 1 { return false }
        return true
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private var snapshots: [UsageProvider: UsageSnapshot] = [:]
    @Published private var errors: [UsageProvider: String] = [:]
    @Published var credits: CreditsSnapshot?
    @Published var lastCreditsError: String?
    @Published var codexVersion: String?
    @Published var claudeVersion: String?
    @Published var claudeAccountEmail: String?
    @Published var claudeAccountOrganization: String?
    @Published var isRefreshing = false
    @Published var debugForceAnimation = false
    @Published private(set) var probeLogs: [UsageProvider: String] = [:]
    private var lastCreditsSnapshot: CreditsSnapshot?
    private var creditsFailureStreak: Int = 0

    private let codexFetcher: UsageFetcher
    private let claudeFetcher: any ClaudeUsageFetching
    private let registry: ProviderRegistry
    private let settings: SettingsStore
    private var failureGates: [UsageProvider: ConsecutiveFailureGate] = [:]
    private var providerSpecs: [UsageProvider: ProviderSpec] = [:]
    private let providerMetadata: [UsageProvider: ProviderMetadata]
    private var timerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        fetcher: UsageFetcher,
        claudeFetcher: any ClaudeUsageFetching = ClaudeUsageFetcher(),
        settings: SettingsStore,
        registry: ProviderRegistry = .shared)
    {
        self.codexFetcher = fetcher
        self.claudeFetcher = claudeFetcher
        self.settings = settings
        self.registry = registry
        self.providerMetadata = registry.metadata
        self
            .failureGates = Dictionary(uniqueKeysWithValues: UsageProvider.allCases
                .map { ($0, ConsecutiveFailureGate()) })
        self.providerSpecs = registry.specs(
            settings: settings,
            metadata: self.providerMetadata,
            codexFetcher: fetcher,
            claudeFetcher: claudeFetcher)
        self.bindSettings()
        self.detectVersions()
        Task { await self.refresh() }
        self.startTimer()
    }

    var codexSnapshot: UsageSnapshot? { self.snapshots[.codex] }
    var claudeSnapshot: UsageSnapshot? { self.snapshots[.claude] }
    var lastCodexError: String? { self.errors[.codex] }
    var lastClaudeError: String? { self.errors[.claude] }
    func error(for provider: UsageProvider) -> String? { self.errors[provider] }
    func metadata(for provider: UsageProvider) -> ProviderMetadata { self.providerMetadata[provider]! }
    func version(for provider: UsageProvider) -> String? {
        switch provider {
        case .codex: self.codexVersion
        case .claude: self.claudeVersion
        }
    }

    var preferredSnapshot: UsageSnapshot? {
        if self.isEnabled(.codex), let codexSnapshot {
            return codexSnapshot
        }
        if self.isEnabled(.claude), let claudeSnapshot {
            return claudeSnapshot
        }
        return nil
    }

    var iconStyle: IconStyle {
        self.isEnabled(.claude) ? .claude : .codex
    }

    var isStale: Bool {
        (self.isEnabled(.codex) && self.lastCodexError != nil) ||
            (self.isEnabled(.claude) && self.lastClaudeError != nil)
    }

    func enabledProviders() -> [UsageProvider] {
        UsageProvider.allCases.filter { self.isEnabled($0) }
    }

    func snapshot(for provider: UsageProvider) -> UsageSnapshot? {
        self.snapshots[provider]
    }

    func style(for provider: UsageProvider) -> IconStyle {
        self.providerSpecs[provider]?.style ?? .codex
    }

    func isStale(provider: UsageProvider) -> Bool {
        self.errors[provider] != nil
    }

    func isEnabled(_ provider: UsageProvider) -> Bool {
        self.settings.isProviderEnabled(provider: provider, metadata: self.metadata(for: provider))
    }

    func refresh() async {
        guard !self.isRefreshing else { return }
        self.isRefreshing = true
        defer { self.isRefreshing = false }

        await withTaskGroup(of: Void.self) { group in
            for provider in UsageProvider.allCases {
                group.addTask { await self.refreshProvider(provider) }
            }
            group.addTask { await self.refreshCreditsIfNeeded() }
        }
    }

    /// For demo/testing: drop the snapshot so the loading animation plays, then restore the last snapshot.
    func replayLoadingAnimation(duration: TimeInterval = 3) {
        let current = self.preferredSnapshot
        self.snapshots.removeAll()
        self.debugForceAnimation = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if let current {
                if self.isEnabled(.codex) {
                    self.snapshots[.codex] = current
                } else if self.isEnabled(.claude) {
                    self.snapshots[.claude] = current
                }
            }
            self.debugForceAnimation = false
        }
    }

    // MARK: - Private

    private func bindSettings() {
        self.settings.$refreshFrequency
            .sink { [weak self] _ in
                self?.startTimer()
            }
            .store(in: &self.cancellables)

        self.settings.objectWillChange
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
            .store(in: &self.cancellables)
    }

    private func startTimer() {
        self.timerTask?.cancel()
        guard let wait = self.settings.refreshFrequency.seconds else { return }

        // Background poller so the menu stays responsive; canceled when settings change or store deallocates.
        self.timerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(wait))
                await self?.refresh()
            }
        }
    }

    deinit {
        self.timerTask?.cancel()
    }

    private func refreshProvider(_ provider: UsageProvider) async {
        guard let spec = self.providerSpecs[provider] else { return }

        if !spec.isEnabled() {
            await MainActor.run {
                self.snapshots.removeValue(forKey: provider)
                self.errors[provider] = nil
                self.failureGates[provider]?.reset()
            }
            return
        }

        do {
            let snapshot: UsageSnapshot
            if provider == .codex {
                let task = Task(priority: .utility) { () -> UsageSnapshot in
                    try await self.codexFetcher.loadLatestUsage()
                }
                snapshot = try await task.value
            } else {
                let task = Task(priority: .utility) { () -> UsageSnapshot in
                    let usage = try await self.claudeFetcher.loadLatestUsage(model: "sonnet")
                    return UsageSnapshot(
                        primary: usage.primary,
                        secondary: usage.secondary,
                        tertiary: usage.opus,
                        updatedAt: usage.updatedAt,
                        accountEmail: usage.accountEmail,
                        accountOrganization: usage.accountOrganization,
                        loginMethod: usage.loginMethod)
                }
                snapshot = try await task.value
            }
            await MainActor.run {
                self.snapshots[provider] = snapshot
                self.errors[provider] = nil
                self.failureGates[provider]?.recordSuccess()
                if provider == .claude {
                    self.claudeAccountEmail = snapshot.accountEmail
                    self.claudeAccountOrganization = snapshot.accountOrganization
                }
            }
        } catch {
            await MainActor.run {
                let hadPriorData = self.snapshots[provider] != nil
                let shouldSurface = self.failureGates[provider]?
                    .shouldSurfaceError(onFailureWithPriorData: hadPriorData) ?? true
                if shouldSurface {
                    self.errors[provider] = error.localizedDescription
                    self.snapshots.removeValue(forKey: provider)
                } else {
                    self.errors[provider] = nil
                }
            }
        }
    }

    private func refreshCreditsIfNeeded() async {
        guard self.isEnabled(.codex) else { return }
        do {
            let credits = try await self.codexFetcher.loadLatestCredits()
            await MainActor.run {
                self.credits = credits
                self.lastCreditsError = nil
                self.lastCreditsSnapshot = credits
                self.creditsFailureStreak = 0
            }
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("data not available yet") {
                await MainActor.run {
                    if let cached = self.lastCreditsSnapshot {
                        self.credits = cached
                        self.lastCreditsError = nil
                    } else {
                        self.credits = nil
                        self.lastCreditsError = "Codex credits are still loading; will retry shortly."
                    }
                }
                return
            }

            await MainActor.run {
                self.creditsFailureStreak += 1
                if let cached = self.lastCreditsSnapshot {
                    self.credits = cached
                    let stamp = cached.updatedAt.formatted(date: .abbreviated, time: .shortened)
                    self.lastCreditsError =
                        "Last Codex credits refresh failed: \(message). Cached values from \(stamp)."
                } else {
                    self.lastCreditsError = message
                    self.credits = nil
                }
            }
        }
    }

    func debugDumpClaude() async {
        let output = await self.claudeFetcher.debugRawProbe(model: "sonnet")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codexbar-claude-probe.txt")
        try? output.write(to: url, atomically: true, encoding: String.Encoding.utf8)
        await MainActor.run {
            let snippet = String(output.prefix(180)).replacingOccurrences(of: "\n", with: " ")
            self.errors[.claude] = "[Claude] \(snippet) (saved: \(url.path))"
            NSWorkspace.shared.open(url)
        }
    }

    func dumpLog(toFileFor provider: UsageProvider) async -> URL? {
        let text = await self.debugLog(for: provider)
        let filename = "codexbar-\(provider.rawValue)-probe.txt"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
            return url
        } catch {
            await MainActor.run { self.errors[provider] = "Failed to save log: \(error.localizedDescription)" }
            return nil
        }
    }

    func debugClaudeDump() async -> String {
        let url = URL(fileURLWithPath: "/tmp/codexbar-claude-dump.txt")
        if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "No Claude parse dump found at \(url.path). Set DEBUG_CLAUDE_DUMP=1 and reproduce the parse failure."
    }

    private func detectVersions() {
        Task.detached { [claudeFetcher] in
            let codexVer = Self.readCLI("codex", args: ["-s", "read-only", "-a", "untrusted", "--version"])
            let claudeVer = claudeFetcher.detectVersion()
            await MainActor.run {
                self.codexVersion = codexVer
                self.claudeVersion = claudeVer
            }
        }
    }

    func debugLog(for provider: UsageProvider) async -> String {
        if let cached = self.probeLogs[provider], !cached.isEmpty {
            return cached
        }

        return await Task.detached(priority: .utility) { () -> String in
            switch provider {
            case .codex:
                let raw = await self.codexFetcher.debugRawRateLimits()
                await MainActor.run { self.probeLogs[.codex] = raw }
                return raw
            case .claude:
                let text = await self.runWithTimeout(seconds: 15) {
                    await self.claudeFetcher.debugRawProbe(model: "sonnet")
                }
                await MainActor.run { self.probeLogs[.claude] = text }
                return text
            }
        }.value
    }

    private func runWithTimeout(seconds: Double, operation: @escaping @Sendable () async -> String) async -> String {
        await withTaskGroup(of: String?.self) { group -> String in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next()?.flatMap(\.self)
            group.cancelAll()
            return result ?? "Probe timed out after \(Int(seconds))s"
        }
    }

    private nonisolated static func readCLI(_ cmd: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [cmd] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else { return nil }
        return text
    }
}
