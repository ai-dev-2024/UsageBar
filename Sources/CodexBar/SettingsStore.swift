import AppKit
import CodexBarCore
import Combine
import ServiceManagement
import SwiftUI

enum RefreshFrequency: String, CaseIterable, Identifiable {
    case manual
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes

    var id: String { self.rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .manual: nil
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .oneMinute: "1 min"
        case .twoMinutes: "2 min"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var refreshFrequency: RefreshFrequency {
        didSet { self.userDefaults.set(self.refreshFrequency.rawValue, forKey: "refreshFrequency") }
    }

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet { LaunchAtLoginManager.setEnabled(self.launchAtLogin) }
    }

    /// Hidden toggle to reveal debug-only menu items (enable via defaults write com.steipete.CodexBar debugMenuEnabled
    /// -bool YES).
    @AppStorage("debugMenuEnabled") var debugMenuEnabled: Bool = false

    @AppStorage("debugLoadingPattern") private var debugLoadingPatternRaw: String?

    @AppStorage("statusChecksEnabled") var statusChecksEnabled: Bool = true {
        didSet { self.objectWillChange.send() }
    }

    @AppStorage("sessionQuotaNotificationsEnabled") var sessionQuotaNotificationsEnabled: Bool = true {
        didSet { self.objectWillChange.send() }
    }

    /// When enabled, progress bars show "percent used" instead of "percent left".
    @AppStorage("usageBarsShowUsed") var usageBarsShowUsed: Bool = false {
        didSet { self.objectWillChange.send() }
    }

    /// Optional: show Codex token + cost usage from @ccusage/codex (offline CLI).
    @AppStorage("tokenCostUsageEnabled") var tokenCostUsageEnabled: Bool = false {
        didSet { self.objectWillChange.send() }
    }

    @AppStorage("randomBlinkEnabled") var randomBlinkEnabled: Bool = false {
        didSet { self.objectWillChange.send() }
    }

    /// Optional: enable scraping the OpenAI dashboard (WebKit) for extra Codex data (code review + breakdown).
    @AppStorage("openAIDashboardEnabled") var openAIDashboardEnabled: Bool = false {
        didSet { self.objectWillChange.send() }
    }

    /// Optional: collapse provider icons into a single menu bar item with an in-menu switcher.
    @AppStorage("mergeIcons") var mergeIcons: Bool = true {
        didSet { self.objectWillChange.send() }
    }

    @AppStorage("selectedMenuProvider") private var selectedMenuProviderRaw: String?

    /// Optional override for the loading animation pattern, exposed via the Debug tab.
    var debugLoadingPattern: LoadingPattern? {
        get { self.debugLoadingPatternRaw.flatMap(LoadingPattern.init(rawValue:)) }
        set {
            self.objectWillChange.send()
            self.debugLoadingPatternRaw = newValue?.rawValue
        }
    }

    var selectedMenuProvider: UsageProvider? {
        get { self.selectedMenuProviderRaw.flatMap(UsageProvider.init(rawValue:)) }
        set {
            self.objectWillChange.send()
            self.selectedMenuProviderRaw = newValue?.rawValue
        }
    }

    @AppStorage("providerDetectionCompleted") private var providerDetectionCompleted: Bool = false

    private let userDefaults: UserDefaults
    private let toggleStore: ProviderToggleStore

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: "sessionQuotaNotificationsEnabled") == nil {
            userDefaults.set(true, forKey: "sessionQuotaNotificationsEnabled")
        }
        if userDefaults.object(forKey: "tokenCostUsageEnabled") == nil {
            userDefaults.set(TTYCommandRunner.which("ccusage-codex") != nil, forKey: "tokenCostUsageEnabled")
        }
        let raw = userDefaults.string(forKey: "refreshFrequency") ?? RefreshFrequency.fiveMinutes.rawValue
        self.refreshFrequency = RefreshFrequency(rawValue: raw) ?? .fiveMinutes
        self.toggleStore = ProviderToggleStore(userDefaults: userDefaults)
        self.toggleStore.purgeLegacyKeys()
        LaunchAtLoginManager.setEnabled(self.launchAtLogin)
        self.runInitialProviderDetectionIfNeeded()
    }

    func isProviderEnabled(provider: UsageProvider, metadata: ProviderMetadata) -> Bool {
        self.toggleStore.isEnabled(metadata: metadata)
    }

    func setProviderEnabled(provider: UsageProvider, metadata: ProviderMetadata, enabled: Bool) {
        self.objectWillChange.send()
        self.toggleStore.setEnabled(enabled, metadata: metadata)
    }

    func rerunProviderDetection() {
        self.runInitialProviderDetectionIfNeeded(force: true)
    }

    // MARK: - Private

    private func runInitialProviderDetectionIfNeeded(force: Bool = false) {
        guard force || !self.providerDetectionCompleted else { return }
        guard let codexMeta = ProviderRegistry.shared.metadata[.codex],
              let claudeMeta = ProviderRegistry.shared.metadata[.claude],
              let geminiMeta = ProviderRegistry.shared.metadata[.gemini] else { return }

        LoginShellPathCache.shared.captureOnce { [weak self] _ in
            Task { @MainActor in
                self?.applyProviderDetection(codexMeta: codexMeta, claudeMeta: claudeMeta, geminiMeta: geminiMeta)
            }
        }
    }

    private func applyProviderDetection(
        codexMeta: ProviderMetadata,
        claudeMeta: ProviderMetadata,
        geminiMeta: ProviderMetadata)
    {
        guard !self.providerDetectionCompleted else { return }
        let codexInstalled = BinaryLocator.resolveCodexBinary() != nil
        let claudeInstalled = BinaryLocator.resolveClaudeBinary() != nil
        let geminiInstalled = BinaryLocator.resolveGeminiBinary() != nil

        // If none installed, keep Codex enabled to match previous behavior.
        let noneInstalled = !codexInstalled && !claudeInstalled && !geminiInstalled
        let enableCodex = codexInstalled || noneInstalled
        let enableClaude = claudeInstalled
        let enableGemini = geminiInstalled

        self.objectWillChange.send()
        self.toggleStore.setEnabled(enableCodex, metadata: codexMeta)
        self.toggleStore.setEnabled(enableClaude, metadata: claudeMeta)
        self.toggleStore.setEnabled(enableGemini, metadata: geminiMeta)
        self.providerDetectionCompleted = true
    }
}

enum LaunchAtLoginManager {
    @MainActor
    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13, *) else { return }
        let service = SMAppService.mainApp
        if enabled {
            try? service.register()
        } else {
            try? service.unregister()
        }
    }
}
