import AppKit
import CodexBarCore
import Combine
import Foundation
import OSLog

enum IconStyle {
    case codex
    case claude
    case gemini
    case combined
}

enum ProviderStatusIndicator: String {
    case none
    case minor
    case major
    case critical
    case maintenance
    case unknown

    var hasIssue: Bool {
        switch self {
        case .none: false
        default: true
        }
    }

    var label: String {
        switch self {
        case .none: "Operational"
        case .minor: "Partial outage"
        case .major: "Major outage"
        case .critical: "Critical issue"
        case .maintenance: "Maintenance"
        case .unknown: "Status unknown"
        }
    }
}

struct ProviderStatus {
    let indicator: ProviderStatusIndicator
    let description: String?
    let updatedAt: Date?
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
    @Published var tokenSnapshots: [UsageProvider: CCUsageTokenSnapshot] = [:]
    @Published var tokenErrors: [UsageProvider: String] = [:]
    @Published var credits: CreditsSnapshot?
    @Published var lastCreditsError: String?
    @Published var openAIDashboard: OpenAIDashboardSnapshot?
    @Published var lastOpenAIDashboardError: String?
    @Published private(set) var openAIDashboardRequiresLogin: Bool = false
    @Published var openAIDashboardCookieImportStatus: String?
    @Published var openAIDashboardCookieImportDebugLog: String?
    @Published var codexVersion: String?
    @Published var claudeVersion: String?
    @Published var geminiVersion: String?
    @Published var claudeAccountEmail: String?
    @Published var claudeAccountOrganization: String?
    @Published var isRefreshing = false
    @Published var debugForceAnimation = false
    @Published var pathDebugInfo: PathDebugSnapshot = .empty
    @Published private var statuses: [UsageProvider: ProviderStatus] = [:]
    @Published private(set) var probeLogs: [UsageProvider: String] = [:]
    private var lastCreditsSnapshot: CreditsSnapshot?
    private var creditsFailureStreak: Int = 0
    private var lastOpenAIDashboardSnapshot: OpenAIDashboardSnapshot?
    private var lastOpenAIDashboardTargetEmail: String?
    private var lastOpenAIDashboardCookieImportAttemptAt: Date?
    private var lastOpenAIDashboardCookieImportEmail: String?
    private var openAIWebAccountDidChange: Bool = false

    private let codexFetcher: UsageFetcher
    private let claudeFetcher: any ClaudeUsageFetching
    let ccusageFetcher: CCUsageFetcher
    private let registry: ProviderRegistry
    let settings: SettingsStore
    private let sessionQuotaNotifier: SessionQuotaNotifier
    private let sessionQuotaLogger = Logger(subsystem: "com.steipete.codexbar", category: "sessionQuota")
    private let openAIWebLogger = Logger(subsystem: "com.steipete.codexbar", category: "openai-web")
    private var openAIWebDebugLines: [String] = []
    private var failureGates: [UsageProvider: ConsecutiveFailureGate] = [:]
    var tokenFailureGates: [UsageProvider: ConsecutiveFailureGate] = [:]
    private var providerSpecs: [UsageProvider: ProviderSpec] = [:]
    private let providerMetadata: [UsageProvider: ProviderMetadata]
    private var timerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownSessionRemaining: [UsageProvider: Double] = [:]
    var lastTokenFetchAt: [UsageProvider: Date] = [:]
    let tokenFetchTTL: TimeInterval = 5 * 60

    init(
        fetcher: UsageFetcher,
        claudeFetcher: any ClaudeUsageFetching = ClaudeUsageFetcher(),
        ccusageFetcher: CCUsageFetcher = CCUsageFetcher(),
        settings: SettingsStore,
        registry: ProviderRegistry = .shared,
        sessionQuotaNotifier: SessionQuotaNotifier = SessionQuotaNotifier())
    {
        self.codexFetcher = fetcher
        self.claudeFetcher = claudeFetcher
        self.ccusageFetcher = ccusageFetcher
        self.settings = settings
        self.registry = registry
        self.sessionQuotaNotifier = sessionQuotaNotifier
        self.providerMetadata = registry.metadata
        self
            .failureGates = Dictionary(uniqueKeysWithValues: UsageProvider.allCases
                .map { ($0, ConsecutiveFailureGate()) })
        self.tokenFailureGates = Dictionary(uniqueKeysWithValues: UsageProvider.allCases
            .map { ($0, ConsecutiveFailureGate()) })
        self.providerSpecs = registry.specs(
            settings: settings,
            metadata: self.providerMetadata,
            codexFetcher: fetcher,
            claudeFetcher: claudeFetcher)
        self.bindSettings()
        self.detectVersions()
        self.refreshPathDebugInfo()
        LoginShellPathCache.shared.captureOnce { [weak self] _ in
            Task { @MainActor in self?.refreshPathDebugInfo() }
        }
        Task { await self.refresh() }
        self.startTimer()
    }

    var codexSnapshot: UsageSnapshot? { self.snapshots[.codex] }
    var claudeSnapshot: UsageSnapshot? { self.snapshots[.claude] }
    var lastCodexError: String? { self.errors[.codex] }
    var lastClaudeError: String? { self.errors[.claude] }
    func error(for provider: UsageProvider) -> String? { self.errors[provider] }
    func metadata(for provider: UsageProvider) -> ProviderMetadata { self.providerMetadata[provider]! }
    func status(for provider: UsageProvider) -> ProviderStatus? {
        guard self.settings.statusChecksEnabled else { return nil }
        return self.statuses[provider]
    }

    func statusIndicator(for provider: UsageProvider) -> ProviderStatusIndicator {
        self.status(for: provider)?.indicator ?? .none
    }

    /// Returns the login method (plan type) for the specified provider, if available.
    private func loginMethod(for provider: UsageProvider) -> String? {
        self.snapshots[provider]?.loginMethod
    }

    /// Returns true if the Claude account appears to be a subscription (Max, Pro, Ultra, Team).
    /// Returns false for API users or when plan cannot be determined.
    func isClaudeSubscription() -> Bool {
        Self.isSubscriptionPlan(self.loginMethod(for: .claude))
    }

    /// Determines if a login method string indicates a Claude subscription plan.
    /// Known subscription indicators: Max, Pro, Ultra, Team (case-insensitive).
    nonisolated static func isSubscriptionPlan(_ loginMethod: String?) -> Bool {
        guard let method = loginMethod?.lowercased(), !method.isEmpty else {
            return false
        }
        let subscriptionIndicators = ["max", "pro", "ultra", "team"]
        return subscriptionIndicators.contains { method.contains($0) }
    }

    func version(for provider: UsageProvider) -> String? {
        switch provider {
        case .codex: self.codexVersion
        case .claude: self.claudeVersion
        case .gemini: self.geminiVersion
        }
    }

    var preferredSnapshot: UsageSnapshot? {
        if self.isEnabled(.codex), let codexSnapshot {
            return codexSnapshot
        }
        if self.isEnabled(.claude), let claudeSnapshot {
            return claudeSnapshot
        }
        if self.isEnabled(.gemini), let snap = self.snapshots[.gemini] {
            return snap
        }
        return nil
    }

    var iconStyle: IconStyle {
        let enabled = self.enabledProviders()
        if enabled.count > 1 { return .combined }
        if self.isEnabled(.gemini) { return .gemini }
        if self.isEnabled(.claude) { return .claude }
        return .codex
    }

    var isStale: Bool {
        (self.isEnabled(.codex) && self.lastCodexError != nil) ||
            (self.isEnabled(.claude) && self.lastClaudeError != nil) ||
            (self.isEnabled(.gemini) && self.errors[.gemini] != nil)
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
                group.addTask { await self.refreshTokenUsage(provider) }
                group.addTask { await self.refreshStatus(provider) }
            }
            group.addTask { await self.refreshCreditsIfNeeded() }
        }

        // OpenAI web scrape depends on the current Codex account email (which can change after login/account switch).
        // Run this after Codex usage refresh so we don't accidentally scrape with stale credentials.
        await self.refreshOpenAIDashboardIfNeeded()
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
                self.tokenSnapshots.removeValue(forKey: provider)
                self.tokenErrors[provider] = nil
                self.failureGates[provider]?.reset()
                self.tokenFailureGates[provider]?.reset()
                self.statuses.removeValue(forKey: provider)
                self.lastKnownSessionRemaining.removeValue(forKey: provider)
                self.lastTokenFetchAt.removeValue(forKey: provider)
            }
            return
        }

        do {
            let fetchClosure = spec.fetch
            let task = Task(priority: .utility) { () -> UsageSnapshot in
                try await fetchClosure()
            }
            let snapshot = try await task.value
            await MainActor.run {
                self.handleSessionQuotaTransition(provider: provider, snapshot: snapshot)
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

    private func handleSessionQuotaTransition(provider: UsageProvider, snapshot: UsageSnapshot) {
        let currentRemaining = snapshot.primary.remainingPercent
        let previousRemaining = self.lastKnownSessionRemaining[provider]

        defer { self.lastKnownSessionRemaining[provider] = currentRemaining }

        guard self.settings.sessionQuotaNotificationsEnabled else {
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) ||
                SessionQuotaNotificationLogic.isDepleted(previousRemaining)
            {
                let providerText = provider.rawValue
                let message =
                    "notifications disabled: provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)"
                self.sessionQuotaLogger.debug("\(message, privacy: .public)")
            }
            return
        }

        guard previousRemaining != nil else {
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) {
                let providerText = provider.rawValue
                let message = "startup depleted: provider=\(providerText) curr=\(currentRemaining)"
                self.sessionQuotaLogger.info("\(message, privacy: .public)")
                self.sessionQuotaNotifier.post(transition: .depleted, provider: provider)
            }
            return
        }

        let transition = SessionQuotaNotificationLogic.transition(
            previousRemaining: previousRemaining,
            currentRemaining: currentRemaining)
        guard transition != .none else {
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) ||
                SessionQuotaNotificationLogic.isDepleted(previousRemaining)
            {
                let providerText = provider.rawValue
                let message =
                    "no transition: provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)"
                self.sessionQuotaLogger.debug("\(message, privacy: .public)")
            }
            return
        }

        let providerText = provider.rawValue
        let transitionText = String(describing: transition)
        let message =
            "transition \(transitionText): provider=\(providerText) " +
            "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)"
        self.sessionQuotaLogger.info("\(message, privacy: .public)")

        self.sessionQuotaNotifier.post(transition: transition, provider: provider)
    }

    private func refreshStatus(_ provider: UsageProvider) async {
        guard self.settings.statusChecksEnabled else { return }
        guard let urlString = self.providerMetadata[provider]?.statusPageURL,
              let baseURL = URL(string: urlString) else { return }

        do {
            let status = try await Self.fetchStatus(from: baseURL)
            await MainActor.run { self.statuses[provider] = status }
        } catch {
            // Keep the previous status to avoid flapping when the API hiccups.
            await MainActor.run {
                if self.statuses[provider] == nil {
                    self.statuses[provider] = ProviderStatus(
                        indicator: .unknown,
                        description: error.localizedDescription,
                        updatedAt: nil)
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

    private func applyOpenAIDashboard(_ dash: OpenAIDashboardSnapshot, targetEmail: String?) async {
        await MainActor.run {
            self.openAIDashboard = dash
            self.lastOpenAIDashboardError = nil
            self.lastOpenAIDashboardSnapshot = dash
            self.openAIDashboardRequiresLogin = false
        }

        if let email = targetEmail, !email.isEmpty {
            OpenAIDashboardCacheStore.save(OpenAIDashboardCache(accountEmail: email, snapshot: dash))
        }
    }

    private func applyOpenAIDashboardFailure(message: String) async {
        await MainActor.run {
            if let cached = self.lastOpenAIDashboardSnapshot {
                self.openAIDashboard = cached
                let stamp = cached.updatedAt.formatted(date: .abbreviated, time: .shortened)
                self.lastOpenAIDashboardError =
                    "Last OpenAI dashboard refresh failed: \(message). Cached values from \(stamp)."
            } else {
                self.lastOpenAIDashboardError = message
                self.openAIDashboard = nil
            }
        }
    }

    private func refreshOpenAIDashboardIfNeeded() async {
        guard self.isEnabled(.codex) else { return }
        guard self.settings.openAIDashboardEnabled else {
            await MainActor.run {
                self.openAIDashboard = nil
                self.lastOpenAIDashboardError = nil
                self.lastOpenAIDashboardSnapshot = nil
                self.lastOpenAIDashboardTargetEmail = nil
                self.openAIDashboardRequiresLogin = false
                self.openAIDashboardCookieImportStatus = nil
                self.openAIDashboardCookieImportDebugLog = nil
                self.lastOpenAIDashboardCookieImportAttemptAt = nil
                self.lastOpenAIDashboardCookieImportEmail = nil
            }
            return
        }

        let targetEmail = self.codexAccountEmailForOpenAIDashboard()
        self.handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: targetEmail)

        if self.openAIWebDebugLines.isEmpty {
            self.resetOpenAIWebDebugLog(context: "refresh")
        } else {
            let stamp = Date().formatted(date: .abbreviated, time: .shortened)
            self.logOpenAIWeb("[\(stamp)] OpenAI web refresh start")
        }
        let log: (String) -> Void = { [weak self] line in
            guard let self else { return }
            self.logOpenAIWeb(line)
        }

        do {
            let normalized = targetEmail?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            // Use a per-email persistent `WKWebsiteDataStore` so multiple dashboard sessions can coexist.
            // Strategy:
            // - Try the existing per-email WebKit cookie store first (fast; avoids Keychain prompts).
            // - On login-required or account mismatch, import cookies from Chrome/Safari and retry once.
            if self.openAIWebAccountDidChange, let targetEmail, !targetEmail.isEmpty {
                // On account switches, proactively re-import cookies so we don't show stale data from the previous
                // user.
                await self.importOpenAIDashboardCookiesIfNeeded(targetEmail: targetEmail, force: true)
                self.openAIWebAccountDidChange = false
            }

            var dash = try await OpenAIDashboardFetcher().loadLatestDashboard(
                accountEmail: targetEmail,
                logger: log,
                debugDumpHTML: false)

            if self.dashboardEmailMismatch(expected: normalized, actual: dash.signedInEmail) {
                await self.importOpenAIDashboardCookiesIfNeeded(targetEmail: targetEmail, force: true)
                dash = try await OpenAIDashboardFetcher().loadLatestDashboard(
                    accountEmail: targetEmail,
                    logger: log,
                    debugDumpHTML: false)
            }

            if self.dashboardEmailMismatch(expected: normalized, actual: dash.signedInEmail) {
                let signedIn = dash.signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
                await MainActor.run {
                    self.openAIDashboard = nil
                    self.lastOpenAIDashboardError = [
                        "OpenAI dashboard signed in as \(signedIn), but Codex uses \(normalized ?? "unknown").",
                        "Switch accounts in your browser and re-enable “Access OpenAI via web”.",
                    ].joined(separator: " ")
                    self.openAIDashboardRequiresLogin = true
                }
                return
            }

            await self.applyOpenAIDashboard(dash, targetEmail: targetEmail)
        } catch OpenAIDashboardFetcher.FetchError.noDashboardData {
            // Often indicates a missing/stale session without an obvious login prompt. Retry once after
            // importing cookies from the user's browser.
            let targetEmail = self.codexAccountEmailForOpenAIDashboard()
            await self.importOpenAIDashboardCookiesIfNeeded(targetEmail: targetEmail, force: true)
            do {
                let dash = try await OpenAIDashboardFetcher().loadLatestDashboard(
                    accountEmail: targetEmail,
                    logger: log,
                    debugDumpHTML: true)
                await self.applyOpenAIDashboard(dash, targetEmail: targetEmail)
            } catch {
                await self.applyOpenAIDashboardFailure(message: error.localizedDescription)
            }
        } catch OpenAIDashboardFetcher.FetchError.loginRequired {
            let targetEmail = self.codexAccountEmailForOpenAIDashboard()
            await self.importOpenAIDashboardCookiesIfNeeded(targetEmail: targetEmail, force: true)
            do {
                let dash = try await OpenAIDashboardFetcher().loadLatestDashboard(
                    accountEmail: targetEmail,
                    logger: log,
                    debugDumpHTML: true)
                await self.applyOpenAIDashboard(dash, targetEmail: targetEmail)
            } catch OpenAIDashboardFetcher.FetchError.loginRequired {
                await MainActor.run {
                    self.lastOpenAIDashboardError = [
                        "OpenAI web access requires a signed-in chatgpt.com session.",
                        "Sign in in Chrome or Safari, then re-enable “Access OpenAI via web”.",
                    ].joined(separator: " ")
                    self.openAIDashboard = self.lastOpenAIDashboardSnapshot
                    self.openAIDashboardRequiresLogin = true
                }
            } catch {
                await self.applyOpenAIDashboardFailure(message: error.localizedDescription)
            }
        } catch {
            await self.applyOpenAIDashboardFailure(message: error.localizedDescription)
        }
    }

    // MARK: - OpenAI web account switching

    /// Detect Codex account email changes and clear stale OpenAI web state so the UI can't show the wrong user.
    /// This does not delete other per-email WebKit cookie stores (we keep multiple accounts around).
    func handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: String?) {
        let normalized = targetEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let normalized, !normalized.isEmpty else { return }

        let previous = self.lastOpenAIDashboardTargetEmail
        self.lastOpenAIDashboardTargetEmail = normalized

        if let previous,
           !previous.isEmpty,
           previous != normalized
        {
            let stamp = Date().formatted(date: .abbreviated, time: .shortened)
            self.logOpenAIWeb(
                "[\(stamp)] Codex account changed: \(previous) → \(normalized); " +
                    "clearing OpenAI web snapshot")
            self.openAIWebAccountDidChange = true
            self.openAIDashboard = nil
            self.lastOpenAIDashboardSnapshot = nil
            self.lastOpenAIDashboardError = nil
            self.openAIDashboardRequiresLogin = true
            self.openAIDashboardCookieImportStatus = "Codex account changed; importing browser cookies…"
            self.lastOpenAIDashboardCookieImportAttemptAt = nil
            self.lastOpenAIDashboardCookieImportEmail = nil
        }
    }

    func importOpenAIDashboardBrowserCookiesNow() async {
        guard self.settings.openAIDashboardEnabled else { return }
        self.resetOpenAIWebDebugLog(context: "manual import")
        let targetEmail = self.codexAccountEmailForOpenAIDashboard()
        await self.importOpenAIDashboardCookiesIfNeeded(targetEmail: targetEmail, force: true)
        await self.refreshOpenAIDashboardIfNeeded()
    }

    private func importOpenAIDashboardCookiesIfNeeded(targetEmail: String?, force: Bool) async {
        guard let targetEmail, !targetEmail.isEmpty else { return }

        let now = Date()
        let lastEmail = self.lastOpenAIDashboardCookieImportEmail
        let lastAttempt = self.lastOpenAIDashboardCookieImportAttemptAt ?? .distantPast

        let shouldAttempt: Bool = if force {
            true
        } else {
            self.openAIDashboardRequiresLogin &&
                (lastEmail?.lowercased() != targetEmail.lowercased() || now.timeIntervalSince(lastAttempt) > 300)
        }

        guard shouldAttempt else { return }
        self.lastOpenAIDashboardCookieImportEmail = targetEmail
        self.lastOpenAIDashboardCookieImportAttemptAt = now

        let stamp = now.formatted(date: .abbreviated, time: .shortened)
        self.logOpenAIWeb("[\(stamp)] import start (target=\(targetEmail))")

        do {
            let log: (String) -> Void = { [weak self] message in
                guard let self else { return }
                self.logOpenAIWeb(message)
            }

            let result = try await OpenAIDashboardBrowserCookieImporter()
                .importBestCookies(intoAccountEmail: targetEmail, logger: log)
            await MainActor.run {
                let matchText = result.matchesCodexEmail ? "matches Codex" : "does not match Codex"
                if let signed = result.signedInEmail, !signed.isEmpty {
                    self.openAIDashboardCookieImportStatus =
                        [
                            "Using \(result.sourceLabel) cookies (\(result.cookieCount)).",
                            "Signed in as \(signed) (\(matchText)).",
                        ].joined(separator: " ")
                } else {
                    self.openAIDashboardCookieImportStatus =
                        "Using \(result.sourceLabel) cookies (\(result.cookieCount))."
                }
            }
        } catch let err as OpenAIDashboardBrowserCookieImporter.ImportError {
            switch err {
            case let .noMatchingAccount(found):
                let foundText: String = if found.isEmpty {
                    "no signed-in session detected in Chrome/Safari"
                } else {
                    found
                        .sorted { lhs, rhs in
                            if lhs.sourceLabel == rhs.sourceLabel { return lhs.email < rhs.email }
                            return lhs.sourceLabel < rhs.sourceLabel
                        }
                        .map { "\($0.sourceLabel): \($0.email)" }
                        .joined(separator: " • ")
                }
                self.logOpenAIWeb("[\(stamp)] import mismatch: \(foundText)")
                await MainActor.run {
                    self.openAIDashboardCookieImportStatus =
                        [
                            "Browser cookies do not match Codex account (\(targetEmail)).",
                            "Found \(foundText).",
                        ].joined(separator: " ")
                    // Treat mismatch like "not logged in" for the current Codex account.
                    self.openAIDashboardRequiresLogin = true
                    self.openAIDashboard = nil
                }
            default:
                self.logOpenAIWeb("[\(stamp)] import failed: \(err.localizedDescription)")
                await MainActor.run {
                    self.openAIDashboardCookieImportStatus =
                        "Browser cookie import failed: \(err.localizedDescription)"
                }
            }
        } catch {
            self.logOpenAIWeb("[\(stamp)] import failed: \(error.localizedDescription)")
            await MainActor.run {
                self.openAIDashboardCookieImportStatus =
                    "Browser cookie import failed: \(error.localizedDescription)"
            }
        }
    }

    private func resetOpenAIWebDebugLog(context: String) {
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        self.openAIWebDebugLines.removeAll(keepingCapacity: true)
        self.openAIDashboardCookieImportDebugLog = nil
        self.logOpenAIWeb("[\(stamp)] OpenAI web \(context) start")
    }

    private func logOpenAIWeb(_ message: String) {
        self.openAIWebLogger.debug("\(message, privacy: .public)")
        self.openAIWebDebugLines.append(message)
        if self.openAIWebDebugLines.count > 240 {
            self.openAIWebDebugLines.removeFirst(self.openAIWebDebugLines.count - 240)
        }
        self.openAIDashboardCookieImportDebugLog = self.openAIWebDebugLines.joined(separator: "\n")
    }

    private func dashboardEmailMismatch(expected: String?, actual: String?) -> Bool {
        guard let expected, !expected.isEmpty else { return false }
        guard let raw = actual?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return false }
        return raw.lowercased() != expected.lowercased()
    }

    func codexAccountEmailForOpenAIDashboard() -> String? {
        let direct = self.snapshots[.codex]?.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct, !direct.isEmpty { return direct }
        let fallback = self.codexFetcher.loadAccountInfo().email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallback, !fallback.isEmpty { return fallback }
        return nil
    }

    private static func fetchStatus(from baseURL: URL) async throws -> ProviderStatus {
        let apiURL = baseURL.appendingPathComponent("api/v2/status.json")
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request, delegate: nil)

        struct Response: Decodable {
            struct Status: Decodable {
                let indicator: String
                let description: String?
            }

            struct Page: Decodable {
                let updatedAt: Date?

                private enum CodingKeys: String, CodingKey {
                    case updatedAt = "updated_at"
                }
            }

            let page: Page?
            let status: Status
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
        }

        let response = try decoder.decode(Response.self, from: data)
        let indicator = ProviderStatusIndicator(rawValue: response.status.indicator) ?? .unknown
        return ProviderStatus(
            indicator: indicator,
            description: response.status.description,
            updatedAt: response.page?.updatedAt)
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
        await ClaudeStatusProbe.latestDumps()
    }

    private func detectVersions() {
        Task.detached { [claudeFetcher] in
            let codexVer = Self.readCLI("codex", args: ["-s", "read-only", "-a", "untrusted", "--version"])
            let claudeVer = claudeFetcher.detectVersion()
            let geminiVer = Self.readCLI("gemini", args: ["--version"])
            await MainActor.run {
                self.codexVersion = codexVer
                self.claudeVersion = claudeVer
                self.geminiVersion = geminiVer
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
            case .gemini:
                let text = "Gemini debug log not yet implemented"
                await MainActor.run { self.probeLogs[.gemini] = text }
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
        let env = ProcessInfo.processInfo.environment
        var pathEnv = env
        pathEnv["PATH"] = PathBuilder.effectivePATH(purposes: [.rpc, .tty, .nodeTooling], env: env)
        let loginPATH = LoginShellPathCache.shared.current

        let resolved: String = switch cmd {
        case "codex":
            BinaryLocator.resolveCodexBinary(env: env, loginPATH: loginPATH) ?? cmd
        case "gemini":
            BinaryLocator.resolveGeminiBinary(env: env, loginPATH: loginPATH) ?? cmd
        default:
            cmd
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [resolved] + args
        process.environment = pathEnv
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

    private func refreshPathDebugInfo() {
        self.pathDebugInfo = PathBuilder.debugSnapshot(purposes: [.rpc, .tty, .nodeTooling])
    }
}
