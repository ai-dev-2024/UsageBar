import CodexBarCore
import SwiftUI
import WidgetKit

enum ProviderChoice: String, AppEnum {
    case codex
    case claude
    case gemini

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")

    static var caseDisplayRepresentations: [ProviderChoice: DisplayRepresentation] = [
        .codex: DisplayRepresentation(title: "Codex"),
        .claude: DisplayRepresentation(title: "Claude"),
        .gemini: DisplayRepresentation(title: "Gemini"),
    ]

    var provider: UsageProvider {
        switch self {
        case .codex: .codex
        case .claude: .claude
        case .gemini: .gemini
        }
    }
}

enum CompactMetric: String, AppEnum {
    case credits
    case todayCost
    case last30DaysCost

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static var caseDisplayRepresentations: [CompactMetric: DisplayRepresentation] = [
        .credits: DisplayRepresentation(title: "Credits left"),
        .todayCost: DisplayRepresentation(title: "Today cost"),
        .last30DaysCost: DisplayRepresentation(title: "30d cost"),
    ]
}

struct ProviderSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Provider"
    static var description = IntentDescription("Select the provider to display in the widget.")

    @Parameter(title: "Provider")
    var provider: ProviderChoice

    init() {
        self.provider = .codex
    }
}

struct CompactMetricSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Provider + Metric"
    static var description = IntentDescription("Select the provider and metric to display.")

    @Parameter(title: "Provider")
    var provider: ProviderChoice

    @Parameter(title: "Metric")
    var metric: CompactMetric

    init() {
        self.provider = .codex
        self.metric = .credits
    }
}

struct CodexBarWidgetEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let snapshot: WidgetSnapshot
}

struct CodexBarCompactEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let metric: CompactMetric
    let snapshot: WidgetSnapshot
}

struct CodexBarTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CodexBarWidgetEntry {
        CodexBarWidgetEntry(
            date: Date(),
            provider: .codex,
            snapshot: WidgetPreviewData.snapshot())
    }

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> CodexBarWidgetEntry {
        let provider = configuration.provider.provider
        return CodexBarWidgetEntry(
            date: Date(),
            provider: provider,
            snapshot: WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot())
    }

    func timeline(
        for configuration: ProviderSelectionIntent,
        in context: Context) async -> Timeline<CodexBarWidgetEntry>
    {
        let provider = configuration.provider.provider
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot()
        let entry = CodexBarWidgetEntry(date: Date(), provider: provider, snapshot: snapshot)
        let refresh = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

struct CodexBarCompactTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CodexBarCompactEntry {
        CodexBarCompactEntry(
            date: Date(),
            provider: .codex,
            metric: .credits,
            snapshot: WidgetPreviewData.snapshot())
    }

    func snapshot(for configuration: CompactMetricSelectionIntent, in context: Context) async -> CodexBarCompactEntry {
        let provider = configuration.provider.provider
        return CodexBarCompactEntry(
            date: Date(),
            provider: provider,
            metric: configuration.metric,
            snapshot: WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot())
    }

    func timeline(
        for configuration: CompactMetricSelectionIntent,
        in context: Context) async -> Timeline<CodexBarCompactEntry>
    {
        let provider = configuration.provider.provider
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot()
        let entry = CodexBarCompactEntry(
            date: Date(),
            provider: provider,
            metric: configuration.metric,
            snapshot: snapshot)
        let refresh = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

enum WidgetPreviewData {
    static func snapshot() -> WidgetSnapshot {
        let primary = RateWindow(usedPercent: 35, windowMinutes: nil, resetsAt: nil, resetDescription: "Resets in 4h")
        let secondary = RateWindow(usedPercent: 60, windowMinutes: nil, resetsAt: nil, resetDescription: "Resets in 3d")
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: Date(),
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            creditsRemaining: 1243.4,
            codeReviewRemainingPercent: 78,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 12.4,
                sessionTokens: 420_000,
                last30DaysCostUSD: 923.8,
                last30DaysTokens: 12_400_000),
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-01", totalTokens: 120_000, costUSD: 15.2),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-02", totalTokens: 80000, costUSD: 10.1),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-03", totalTokens: 140_000, costUSD: 17.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-04", totalTokens: 90000, costUSD: 11.4),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-05", totalTokens: 160_000, costUSD: 19.8),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-06", totalTokens: 70000, costUSD: 8.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-07", totalTokens: 110_000, costUSD: 13.7),
            ])
        return WidgetSnapshot(entries: [entry], generatedAt: Date())
    }
}
