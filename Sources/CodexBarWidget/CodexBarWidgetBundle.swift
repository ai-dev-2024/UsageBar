import SwiftUI
import WidgetKit

@main
struct CodexBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexBarUsageWidget()
        CodexBarHistoryWidget()
        CodexBarCompactWidget()
    }
}

struct CodexBarUsageWidget: Widget {
    private let kind = "CodexBarUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: CodexBarTimelineProvider())
        { entry in
            CodexBarUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Usage")
        .description("Session and weekly usage with credits and costs.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CodexBarHistoryWidget: Widget {
    private let kind = "CodexBarHistoryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: CodexBarTimelineProvider())
        { entry in
            CodexBarHistoryWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar History")
        .description("Usage history chart with recent totals.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CodexBarCompactWidget: Widget {
    private let kind = "CodexBarCompactWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: CompactMetricSelectionIntent.self,
            provider: CodexBarCompactTimelineProvider())
        { entry in
            CodexBarCompactWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Metric")
        .description("Compact widget for credits or cost.")
        .supportedFamilies([.systemSmall])
    }
}
