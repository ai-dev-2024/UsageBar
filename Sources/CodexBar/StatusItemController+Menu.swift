import AppKit
import CodexBarCore
import Observation
import SwiftUI

// MARK: - NSMenu construction

extension StatusItemController {
    private static let menuCardBaseWidth: CGFloat = 310
    private static let menuOpenRefreshDelay: Duration = .seconds(1.2)
    private struct OpenAIWebMenuItems {
        let hasUsageBreakdown: Bool
        let hasCreditsHistory: Bool
        let hasCostHistory: Bool
    }

    private func menuCardWidth(for providers: [UsageProvider], menu: NSMenu? = nil) -> CGFloat {
        _ = menu
        if providers.count >= 7 {
            return (Self.menuCardBaseWidth * 1.15).rounded()
        }
        return Self.menuCardBaseWidth
    }

    func makeMenu() -> NSMenu {
        guard self.shouldMergeIcons else {
            return self.makeMenu(for: nil)
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if self.isHostedSubviewMenu(menu) {
            self.refreshHostedSubviewHeights(in: menu)
            self.openMenus[ObjectIdentifier(menu)] = menu
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.openMenus[ObjectIdentifier(menu)] != nil else { return }
                self.refreshHostedSubviewHeights(in: menu)
            }
            return
        }

        var provider: UsageProvider?
        if self.shouldMergeIcons {
            self.selectedMenuProvider = self.resolvedMenuProvider()
            self.lastMenuProvider = self.selectedMenuProvider ?? .codex
            provider = self.selectedMenuProvider
        } else {
            if let menuProvider = self.menuProviders[ObjectIdentifier(menu)] {
                self.lastMenuProvider = menuProvider
                provider = menuProvider
            } else if menu === self.fallbackMenu {
                self.lastMenuProvider = self.store.enabledProviders().first ?? .codex
                provider = nil
            } else {
                let resolved = self.store.enabledProviders().first ?? .codex
                self.lastMenuProvider = resolved
                provider = resolved
            }
        }

        if self.menuNeedsRefresh(menu) {
            self.populateMenu(menu, provider: provider)
            self.markMenuFresh(menu)
        }
        self.refreshMenuCardHeights(in: menu)
        self.openMenus[ObjectIdentifier(menu)] = menu
        self.scheduleOpenMenuRefresh(for: menu)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.openMenus[ObjectIdentifier(menu)] != nil else { return }
            self.refreshMenuCardHeights(in: menu)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        self.openMenus.removeValue(forKey: ObjectIdentifier(menu))
        self.menuRefreshTasks.removeValue(forKey: ObjectIdentifier(menu))?.cancel()
        for menuItem in menu.items {
            (menuItem.view as? MenuCardHighlighting)?.setHighlighted(false)
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            let highlighted = menuItem == item && menuItem.isEnabled
            (menuItem.view as? MenuCardHighlighting)?.setHighlighted(highlighted)
        }
    }

    private func populateMenu(_ menu: NSMenu, provider: UsageProvider?) {
        menu.removeAllItems()

        let selectedProvider = provider
        let enabledProviders = self.store.enabledProviders()
        let menuWidth = self.menuCardWidth(for: enabledProviders, menu: menu)
        let descriptor = MenuDescriptor.build(
            provider: selectedProvider,
            store: self.store,
            settings: self.settings,
            account: self.account,
            updateReady: self.updater.updateStatus.isUpdateReady)
        let dashboard = self.store.openAIDashboard
        let currentProvider = selectedProvider ?? enabledProviders.first ?? .codex
        let openAIWebEligible = currentProvider == .codex &&
            self.store.openAIDashboardRequiresLogin == false &&
            dashboard != nil
        let hasCreditsHistory = openAIWebEligible && !(dashboard?.dailyBreakdown ?? []).isEmpty
        let hasUsageBreakdown = openAIWebEligible && !(dashboard?.usageBreakdown ?? []).isEmpty
        let hasCostHistory = self.settings.isCCUsageCostUsageEffectivelyEnabled(for: currentProvider) &&
            (self.store.tokenSnapshot(for: currentProvider)?.daily.isEmpty == false)
        let hasOpenAIWebMenuItems = hasCreditsHistory || hasUsageBreakdown || hasCostHistory
        var addedOpenAIWebItems = false

        if self.shouldMergeIcons, enabledProviders.count > 1 {
            let switcherItem = self.makeProviderSwitcherItem(
                providers: enabledProviders,
                selected: selectedProvider,
                menu: menu)
            menu.addItem(switcherItem)
            menu.addItem(.separator())
        }

        if let model = self.menuCardModel(for: selectedProvider) {
            if hasOpenAIWebMenuItems {
                let webItems = OpenAIWebMenuItems(
                    hasUsageBreakdown: hasUsageBreakdown,
                    hasCreditsHistory: hasCreditsHistory,
                    hasCostHistory: hasCostHistory)
                self.addMenuCardSections(
                    to: menu,
                    model: model,
                    provider: currentProvider,
                    width: menuWidth,
                    webItems: webItems)
                addedOpenAIWebItems = true
            } else {
                menu.addItem(self.makeMenuCardItem(
                    UsageMenuCardView(model: model, width: menuWidth),
                    id: "menuCard",
                    width: menuWidth))
                if currentProvider == .codex, model.creditsText != nil {
                    menu.addItem(self.makeBuyCreditsItem())
                }
                menu.addItem(.separator())
            }
        }

        if hasOpenAIWebMenuItems {
            if !addedOpenAIWebItems {
                // Only show these when we actually have additional data.
                if hasUsageBreakdown {
                    _ = self.addUsageBreakdownSubmenu(to: menu)
                }
                if hasCreditsHistory {
                    _ = self.addCreditsHistorySubmenu(to: menu)
                }
                if hasCostHistory {
                    _ = self.addCostHistorySubmenu(to: menu, provider: currentProvider)
                }
            }
            menu.addItem(.separator())
        }

        let actionableSections = descriptor.sections.filter { section in
            section.entries.contains { entry in
                if case .action = entry { return true }
                return false
            }
        }
        for (index, section) in actionableSections.enumerated() {
            for entry in section.entries {
                switch entry {
                case let .text(text, style):
                    let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    if style == .headline {
                        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
                        item.attributedTitle = NSAttributedString(string: text, attributes: [.font: font])
                    } else if style == .secondary {
                        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                        item.attributedTitle = NSAttributedString(
                            string: text,
                            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
                    }
                    menu.addItem(item)
                case let .action(title, action):
                    let (selector, represented) = self.selector(for: action)
                    let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                    item.target = self
                    item.representedObject = represented
                    if let iconName = action.systemImageName,
                       let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
                    {
                        image.isTemplate = true
                        image.size = NSSize(width: 16, height: 16)
                        item.image = image
                    }
                    if case let .switchAccount(targetProvider) = action,
                       let subtitle = self.switchAccountSubtitle(for: targetProvider)
                    {
                        item.subtitle = subtitle
                        item.isEnabled = false
                    }
                    menu.addItem(item)
                case .divider:
                    menu.addItem(.separator())
                }
            }
            if index < actionableSections.count - 1 {
                menu.addItem(.separator())
            }
        }
    }

    func makeMenu(for provider: UsageProvider?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        if let provider {
            self.menuProviders[ObjectIdentifier(menu)] = provider
        }
        return menu
    }

    private func makeProviderSwitcherItem(
        providers: [UsageProvider],
        selected: UsageProvider?,
        menu: NSMenu) -> NSMenuItem
    {
        let view = ProviderSwitcherView(
            providers: providers,
            selected: selected,
            width: self.menuCardWidth(for: providers, menu: menu),
            showsIcons: self.settings.switcherShowsIcons,
            iconProvider: { [weak self] provider in
                self?.switcherIcon(for: provider) ?? NSImage()
            },
            weeklyRemainingProvider: { [weak self] provider in
                self?.switcherWeeklyRemaining(for: provider)
            },
            onSelect: { [weak self, weak menu] provider in
                guard let self, let menu else { return }
                self.selectedMenuProvider = provider
                self.lastMenuProvider = provider
                self.populateMenu(menu, provider: provider)
                self.markMenuFresh(menu)
                self.refreshMenuCardHeights(in: menu)
                self.applyIcon(phase: nil)
            })
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = false
        return item
    }

    private func resolvedMenuProvider() -> UsageProvider? {
        let enabled = self.store.enabledProviders()
        if enabled.isEmpty { return .codex }
        if let selected = self.selectedMenuProvider, enabled.contains(selected) {
            return selected
        }
        return enabled.first
    }

    private func menuNeedsRefresh(_ menu: NSMenu) -> Bool {
        let key = ObjectIdentifier(menu)
        return self.menuVersions[key] != self.menuContentVersion
    }

    private func markMenuFresh(_ menu: NSMenu) {
        let key = ObjectIdentifier(menu)
        self.menuVersions[key] = self.menuContentVersion
    }

    func refreshOpenMenusIfNeeded() {
        guard !self.openMenus.isEmpty else { return }
        for (key, menu) in self.openMenus {
            guard key == ObjectIdentifier(menu) else {
                self.openMenus.removeValue(forKey: key)
                continue
            }

            if self.isHostedSubviewMenu(menu) {
                self.refreshHostedSubviewHeights(in: menu)
                continue
            }

            if self.menuNeedsRefresh(menu) {
                let provider = self.menuProvider(for: menu)
                self.populateMenu(menu, provider: provider)
                self.markMenuFresh(menu)
                self.refreshMenuCardHeights(in: menu)
            }
        }
    }

    private func menuProvider(for menu: NSMenu) -> UsageProvider? {
        if self.shouldMergeIcons {
            return self.selectedMenuProvider ?? self.resolvedMenuProvider()
        }
        if let provider = self.menuProviders[ObjectIdentifier(menu)] {
            return provider
        }
        if menu === self.fallbackMenu {
            return nil
        }
        return self.store.enabledProviders().first ?? .codex
    }

    private func scheduleOpenMenuRefresh(for menu: NSMenu) {
        self.refreshNow()
        let key = ObjectIdentifier(menu)
        self.menuRefreshTasks[key]?.cancel()
        self.menuRefreshTasks[key] = Task { @MainActor [weak self, weak menu] in
            guard let self, let menu else { return }
            try? await Task.sleep(for: Self.menuOpenRefreshDelay)
            guard !Task.isCancelled else { return }
            guard self.openMenus[ObjectIdentifier(menu)] != nil else { return }
            guard !self.store.isRefreshing else { return }
            let provider = self.menuProvider(for: menu) ?? self.resolvedMenuProvider()
            let isStale = provider.map { self.store.isStale(provider: $0) } ?? self.store.isStale
            let hasSnapshot = provider.map { self.store.snapshot(for: $0) != nil } ?? true
            guard isStale || !hasSnapshot else { return }
            self.refreshNow()
        }
    }

    private func refreshMenuCardHeights(in menu: NSMenu) {
        // Re-measure the menu card height right before display to avoid stale/incorrect sizing when content
        // changes (e.g. dashboard error lines causing wrapping).
        let cardItems = menu.items.filter { item in
            (item.representedObject as? String)?.hasPrefix("menuCard") == true
        }
        for item in cardItems {
            guard let view = item.view else { continue }
            let width = self.menuCardWidth(for: self.store.enabledProviders(), menu: menu)
            let height = self.menuCardHeight(for: view, width: width)
            view.frame = NSRect(
                origin: .zero,
                size: NSSize(width: width, height: height))
        }
    }

    private func makeMenuCardItem(
        _ view: some View,
        id: String,
        width: CGFloat,
        submenu: NSMenu? = nil,
        highlightExclusionHeight: CGFloat = 0) -> NSMenuItem
    {
        let highlightState = MenuCardHighlightState()
        let wrapped = MenuCardSectionContainerView(
            highlightState: highlightState,
            showsSubmenuIndicator: submenu != nil,
            highlightExclusionHeight: highlightExclusionHeight)
        {
            view
        }
        let hosting = MenuCardItemHostingView(rootView: wrapped, highlightState: highlightState)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 1))
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        // Important: constrain width before asking SwiftUI for the fitting height, otherwise text wrapping
        // changes the required height and the menu item becomes visually "squeezed".
        let height = self.menuCardHeight(for: hosting, width: width)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        let item = NSMenuItem()
        item.view = hosting
        item.isEnabled = submenu != nil
        item.representedObject = id
        item.submenu = submenu
        if submenu != nil {
            item.target = self
            item.action = #selector(self.menuCardNoOp(_:))
        }
        return item
    }

    private func menuCardHeight(for view: NSView, width: CGFloat) -> CGFloat {
        let basePadding: CGFloat = 6
        let descenderSafety: CGFloat = 1

        if let measured = view as? MenuCardMeasuring {
            return max(1, ceil(measured.measuredHeight(width: width) + basePadding + descenderSafety))
        }

        view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 1))
        view.needsLayout = true
        view.invalidateIntrinsicContentSize()
        view.layoutSubtreeIfNeeded()

        let widthConstraint = view.widthAnchor.constraint(equalToConstant: width)
        widthConstraint.priority = .required
        widthConstraint.isActive = true
        defer { widthConstraint.isActive = false }

        let fitted = view.fittingSize

        return max(1, ceil(fitted.height + basePadding + descenderSafety))
    }

    private func addMenuCardSections(
        to menu: NSMenu,
        model: UsageMenuCardView.Model,
        provider: UsageProvider,
        width: CGFloat,
        webItems: OpenAIWebMenuItems)
    {
        let hasUsageBlock = !model.metrics.isEmpty || model.placeholder != nil
        let hasCredits = model.creditsText != nil
        let hasExtraUsage = model.providerCost != nil
        let hasCost = model.tokenUsage != nil
        let bottomPadding = CGFloat(hasCredits ? 4 : 10)
        let sectionSpacing = CGFloat(8)
        let usageBottomPadding = bottomPadding
        let creditsBottomPadding = bottomPadding

        let headerView = UsageMenuCardHeaderSectionView(
            model: model,
            showDivider: hasUsageBlock,
            width: width)
        menu.addItem(self.makeMenuCardItem(headerView, id: "menuCardHeader", width: width))

        if hasUsageBlock {
            let usageView = UsageMenuCardUsageSectionView(
                model: model,
                showBottomDivider: false,
                bottomPadding: usageBottomPadding,
                width: width)
            let usageSubmenu = self.makeUsageSubmenu(
                provider: provider,
                snapshot: self.store.snapshot(for: provider),
                webItems: webItems)
            menu.addItem(self.makeMenuCardItem(
                usageView,
                id: "menuCardUsage",
                width: width,
                submenu: usageSubmenu))
        }

        if hasCredits || hasExtraUsage || hasCost {
            menu.addItem(.separator())
        }

        if hasCredits {
            if hasExtraUsage || hasCost {
                menu.addItem(.separator())
            }
            let creditsView = UsageMenuCardCreditsSectionView(
                model: model,
                showBottomDivider: false,
                topPadding: sectionSpacing,
                bottomPadding: creditsBottomPadding,
                width: width)
            let creditsSubmenu = webItems.hasCreditsHistory ? self.makeCreditsHistorySubmenu() : nil
            menu.addItem(self.makeMenuCardItem(
                creditsView,
                id: "menuCardCredits",
                width: width,
                submenu: creditsSubmenu))
            if provider == .codex {
                menu.addItem(self.makeBuyCreditsItem())
            }
        }
        if hasExtraUsage {
            if hasCredits {
                menu.addItem(.separator())
            }
            let extraUsageView = UsageMenuCardExtraUsageSectionView(
                model: model,
                topPadding: sectionSpacing,
                bottomPadding: bottomPadding,
                width: width)
            menu.addItem(self.makeMenuCardItem(
                extraUsageView,
                id: "menuCardExtraUsage",
                width: width))
        }
        if hasCost {
            if hasCredits || hasExtraUsage {
                menu.addItem(.separator())
            }
            let costView = UsageMenuCardCostSectionView(
                model: model,
                topPadding: sectionSpacing,
                bottomPadding: bottomPadding,
                width: width)
            let costSubmenu = webItems.hasCostHistory ? self.makeCostHistorySubmenu(provider: provider) : nil
            menu.addItem(self.makeMenuCardItem(
                costView,
                id: "menuCardCost",
                width: width,
                submenu: costSubmenu))
        }
    }

    private func switcherIcon(for provider: UsageProvider) -> NSImage {
        if let brand = ProviderBrandIcon.image(for: provider) {
            return brand
        }

        // Fallback to the dynamic icon renderer if resources are missing (e.g. dev bundle mismatch).
        let snapshot = self.store.snapshot(for: provider)
        let showUsed = self.settings.usageBarsShowUsed
        let primary = showUsed ? snapshot?.primary.usedPercent : snapshot?.primary.remainingPercent
        let weekly = showUsed ? snapshot?.secondary?.usedPercent : snapshot?.secondary?.remainingPercent
        let credits = provider == .codex ? self.store.credits?.remaining : nil
        let stale = self.store.isStale(provider: provider)
        let style = self.store.style(for: provider)
        let indicator = self.store.statusIndicator(for: provider)
        let image = IconRenderer.makeIcon(
            primaryRemaining: primary,
            weeklyRemaining: weekly,
            creditsRemaining: credits,
            stale: stale,
            style: style,
            blink: 0,
            wiggle: 0,
            tilt: 0,
            statusIndicator: indicator)
        image.isTemplate = true
        return image
    }

    private func switcherWeeklyRemaining(for provider: UsageProvider) -> Double? {
        let snapshot = self.store.snapshot(for: provider)
        let window: RateWindow? = switch provider {
        case .factory:
            snapshot?.secondary ?? snapshot?.primary
        case .codex, .claude, .zai, .gemini, .antigravity, .cursor, .copilot:
            snapshot?.primary ?? snapshot?.secondary
        }
        guard let window else { return nil }
        if self.settings.usageBarsShowUsed {
            return window.usedPercent
        }
        return window.remainingPercent
    }

    private func selector(for action: MenuDescriptor.MenuAction) -> (Selector, Any?) {
        switch action {
        case .installUpdate: (#selector(self.installUpdate), nil)
        case .refresh: (#selector(self.refreshNow), nil)
        case .dashboard: (#selector(self.openDashboard), nil)
        case .statusPage: (#selector(self.openStatusPage), nil)
        case let .switchAccount(provider): (#selector(self.runSwitchAccount(_:)), provider.rawValue)
        case .settings: (#selector(self.showSettingsGeneral), nil)
        case .about: (#selector(self.showSettingsAbout), nil)
        case .quit: (#selector(self.quit), nil)
        case let .copyError(message): (#selector(self.copyError(_:)), message)
        }
    }

    @MainActor
    private protocol MenuCardHighlighting: AnyObject {
        func setHighlighted(_ highlighted: Bool)
    }

    @MainActor
    private protocol MenuCardMeasuring: AnyObject {
        func measuredHeight(width: CGFloat) -> CGFloat
    }

    @MainActor
    @Observable
    fileprivate final class MenuCardHighlightState {
        var isHighlighted = false
    }

    private final class MenuHostingView<Content: View>: NSHostingView<Content> {
        override var allowsVibrancy: Bool { true }
    }

    @MainActor
    private final class MenuCardItemHostingView<Content: View>: NSHostingView<Content>, MenuCardHighlighting,
    MenuCardMeasuring {
        private let highlightState: MenuCardHighlightState
        override var allowsVibrancy: Bool { true }

        override var intrinsicContentSize: NSSize {
            let size = super.intrinsicContentSize
            guard self.frame.width > 0 else { return size }
            return NSSize(width: self.frame.width, height: size.height)
        }

        init(rootView: Content, highlightState: MenuCardHighlightState) {
            self.highlightState = highlightState
            super.init(rootView: rootView)
        }

        required init(rootView: Content) {
            self.highlightState = MenuCardHighlightState()
            super.init(rootView: rootView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func measuredHeight(width: CGFloat) -> CGFloat {
            let controller = NSHostingController(rootView: self.rootView)
            let measured = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            return measured.height
        }

        func setHighlighted(_ highlighted: Bool) {
            guard self.highlightState.isHighlighted != highlighted else { return }
            self.highlightState.isHighlighted = highlighted
        }
    }

    private struct MenuCardSectionContainerView<Content: View>: View {
        @Bindable var highlightState: MenuCardHighlightState
        let showsSubmenuIndicator: Bool
        let highlightExclusionHeight: CGFloat
        let content: Content

        init(
            highlightState: MenuCardHighlightState,
            showsSubmenuIndicator: Bool,
            highlightExclusionHeight: CGFloat = 0,
            @ViewBuilder content: () -> Content)
        {
            self.highlightState = highlightState
            self.showsSubmenuIndicator = showsSubmenuIndicator
            self.highlightExclusionHeight = highlightExclusionHeight
            self.content = content()
        }

        var body: some View {
            self.content
                .environment(\.menuItemHighlighted, self.highlightState.isHighlighted)
                .foregroundStyle(MenuHighlightStyle.primary(self.highlightState.isHighlighted))
                .background(alignment: .topLeading) {
                    if self.highlightState.isHighlighted {
                        self.highlightBackground
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if self.showsSubmenuIndicator {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.highlightState.isHighlighted))
                            .padding(.top, 8)
                            .padding(.trailing, 10)
                    }
                }
        }

        @ViewBuilder
        private var highlightBackground: some View {
            GeometryReader { proxy in
                let topInset: CGFloat = 1
                let bottomInset: CGFloat = 1
                let height = max(0, proxy.size.height - self.highlightExclusionHeight - topInset - bottomInset)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MenuHighlightStyle.selectionBackground(self.highlightState.isHighlighted))
                    .frame(height: height, alignment: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 6)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
            }
            .allowsHitTesting(false)
        }
    }

    private func makeBuyCreditsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Buy Credits...", action: #selector(self.openCreditsPurchase), keyEquivalent: "")
        item.target = self
        if let image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            item.image = image
        }
        return item
    }

    @discardableResult
    private func addCreditsHistorySubmenu(to menu: NSMenu) -> Bool {
        guard let submenu = self.makeCreditsHistorySubmenu() else { return false }
        let item = NSMenuItem(title: "Credits history", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    @discardableResult
    private func addUsageBreakdownSubmenu(to menu: NSMenu) -> Bool {
        guard let submenu = self.makeUsageBreakdownSubmenu() else { return false }
        let item = NSMenuItem(title: "Usage breakdown", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    @discardableResult
    private func addCostHistorySubmenu(to menu: NSMenu, provider: UsageProvider) -> Bool {
        guard let submenu = self.makeCostHistorySubmenu(provider: provider) else { return false }
        let item = NSMenuItem(title: "Usage history (30 days)", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    private func makeUsageSubmenu(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        webItems: OpenAIWebMenuItems) -> NSMenu?
    {
        if provider == .codex, webItems.hasUsageBreakdown {
            return self.makeUsageBreakdownSubmenu()
        }
        if provider == .zai {
            return self.makeZaiUsageDetailsSubmenu(snapshot: snapshot)
        }
        return nil
    }

    private func makeZaiUsageDetailsSubmenu(snapshot: UsageSnapshot?) -> NSMenu? {
        guard let timeLimit = snapshot?.zaiUsage?.timeLimit else { return nil }
        guard !timeLimit.usageDetails.isEmpty else { return nil }

        let submenu = NSMenu()
        let titleItem = NSMenuItem(title: "MCP details", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        submenu.addItem(titleItem)

        if let window = timeLimit.windowLabel {
            let item = NSMenuItem(title: "Window: \(window)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }
        if let resetTime = timeLimit.nextResetTime {
            let reset = UsageFormatter.resetDescription(from: resetTime)
            let item = NSMenuItem(title: "Resets: \(reset)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }
        submenu.addItem(.separator())

        let sortedDetails = timeLimit.usageDetails.sorted {
            $0.modelCode.localizedCaseInsensitiveCompare($1.modelCode) == .orderedAscending
        }
        for detail in sortedDetails {
            let usage = UsageFormatter.tokenCountString(detail.usage)
            let item = NSMenuItem(title: "\(detail.modelCode): \(usage)", action: nil, keyEquivalent: "")
            submenu.addItem(item)
        }
        return submenu
    }

    private func makeUsageBreakdownSubmenu() -> NSMenu? {
        let breakdown = self.store.openAIDashboard?.usageBreakdown ?? []
        let width = Self.menuCardBaseWidth
        guard !breakdown.isEmpty else { return nil }

        let submenu = NSMenu()
        submenu.delegate = self
        let chartView = UsageBreakdownChartMenuView(breakdown: breakdown, width: width)
        let hosting = MenuHostingView(rootView: chartView)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 1))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: size.height))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = false
        chartItem.representedObject = "usageBreakdownChart"
        submenu.addItem(chartItem)
        return submenu
    }

    private func makeCreditsHistorySubmenu() -> NSMenu? {
        let breakdown = self.store.openAIDashboard?.dailyBreakdown ?? []
        let width = Self.menuCardBaseWidth
        guard !breakdown.isEmpty else { return nil }

        let submenu = NSMenu()
        submenu.delegate = self
        let chartView = CreditsHistoryChartMenuView(breakdown: breakdown, width: width)
        let hosting = MenuHostingView(rootView: chartView)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 1))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: size.height))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = false
        chartItem.representedObject = "creditsHistoryChart"
        submenu.addItem(chartItem)
        return submenu
    }

    private func makeCostHistorySubmenu(provider: UsageProvider) -> NSMenu? {
        guard provider == .codex || provider == .claude else { return nil }
        let width = Self.menuCardBaseWidth
        guard let tokenSnapshot = self.store.tokenSnapshot(for: provider) else { return nil }
        guard !tokenSnapshot.daily.isEmpty else { return nil }

        let submenu = NSMenu()
        submenu.delegate = self
        let chartView = CostHistoryChartMenuView(
            provider: provider,
            daily: tokenSnapshot.daily,
            totalCostUSD: tokenSnapshot.last30DaysCostUSD,
            width: width)
        let hosting = MenuHostingView(rootView: chartView)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 1))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: size.height))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = false
        chartItem.representedObject = "costHistoryChart"
        submenu.addItem(chartItem)
        return submenu
    }

    private func isHostedSubviewMenu(_ menu: NSMenu) -> Bool {
        let ids: Set<String> = [
            "usageBreakdownChart",
            "creditsHistoryChart",
            "costHistoryChart",
        ]
        return menu.items.contains { item in
            guard let id = item.representedObject as? String else { return false }
            return ids.contains(id)
        }
    }

    private func refreshHostedSubviewHeights(in menu: NSMenu) {
        let enabledProviders = self.store.enabledProviders()
        let width = self.menuCardWidth(for: enabledProviders, menu: menu)

        for item in menu.items {
            guard let view = item.view else { continue }
            view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 1))
            view.layoutSubtreeIfNeeded()
            let height = view.fittingSize.height
            view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        }
    }

    private func menuCardModel(for provider: UsageProvider?) -> UsageMenuCardView.Model? {
        let target = provider ?? self.store.enabledProviders().first ?? .codex
        let metadata = self.store.metadata(for: target)

        let snapshot = self.store.snapshot(for: target)
        let credits: CreditsSnapshot?
        let creditsError: String?
        let dashboard: OpenAIDashboardSnapshot?
        let dashboardError: String?
        let tokenSnapshot: CCUsageTokenSnapshot?
        let tokenError: String?
        if target == .codex {
            credits = self.store.credits
            creditsError = self.store.lastCreditsError
            dashboard = self.store.openAIDashboardRequiresLogin ? nil : self.store.openAIDashboard
            dashboardError = self.store.lastOpenAIDashboardError
            tokenSnapshot = self.store.tokenSnapshot(for: target)
            tokenError = self.store.tokenError(for: target)
        } else if target == .claude {
            credits = nil
            creditsError = nil
            dashboard = nil
            dashboardError = nil
            tokenSnapshot = self.store.tokenSnapshot(for: target)
            tokenError = self.store.tokenError(for: target)
        } else {
            credits = nil
            creditsError = nil
            dashboard = nil
            dashboardError = nil
            tokenSnapshot = nil
            tokenError = nil
        }

        let input = UsageMenuCardView.Model.Input(
            provider: target,
            metadata: metadata,
            snapshot: snapshot,
            credits: credits,
            creditsError: creditsError,
            dashboard: dashboard,
            dashboardError: dashboardError,
            tokenSnapshot: tokenSnapshot,
            tokenError: tokenError,
            account: self.account,
            isRefreshing: self.store.isRefreshing,
            lastError: self.store.error(for: target),
            usageBarsShowUsed: self.settings.usageBarsShowUsed,
            tokenCostUsageEnabled: self.settings.isCCUsageCostUsageEffectivelyEnabled(for: target),
            showOptionalCreditsAndExtraUsage: self.settings.showOptionalCreditsAndExtraUsage,
            now: Date())
        return UsageMenuCardView.Model.make(input)
    }

    @objc private func menuCardNoOp(_ sender: NSMenuItem) {
        _ = sender
    }
}

private final class ProviderSwitcherView: NSView {
    private struct Segment {
        let provider: UsageProvider
        let image: NSImage
        let title: String
    }

    private struct WeeklyIndicator {
        let provider: UsageProvider
        let track: NSView
        let fill: NSView
    }

    private let segments: [Segment]
    private let onSelect: (UsageProvider) -> Void
    private let showsIcons: Bool
    private let weeklyRemainingProvider: (UsageProvider) -> Double?
    private var buttons: [NSButton] = []
    private var weeklyIndicators: [ObjectIdentifier: WeeklyIndicator] = [:]
    private var segmentWidths: [CGFloat] = []
    private let selectedBackground = NSColor.controlAccentColor.cgColor
    private let unselectedBackground = NSColor.clear.cgColor
    private let selectedTextColor = NSColor.white
    private let unselectedTextColor = NSColor.secondaryLabelColor
    private let stackedIcons: Bool
    private let useTwoRows: Bool
    private let rowSpacing: CGFloat
    private let rowHeight: CGFloat
    private var preferredWidth: CGFloat = 0

    init(
        providers: [UsageProvider],
        selected: UsageProvider?,
        width: CGFloat,
        showsIcons: Bool,
        iconProvider: (UsageProvider) -> NSImage,
        weeklyRemainingProvider: @escaping (UsageProvider) -> Double?,
        onSelect: @escaping (UsageProvider) -> Void)
    {
        let minimumGap: CGFloat = 1
        self.segments = providers.map { provider in
            let fullTitle = Self.switcherTitle(for: provider)
            let icon = iconProvider(provider)
            icon.isTemplate = true
            // Avoid any resampling: we ship exact 16pt/32px assets for crisp rendering.
            icon.size = NSSize(width: 16, height: 16)
            return Segment(
                provider: provider,
                image: icon,
                title: fullTitle)
        }
        self.onSelect = onSelect
        self.showsIcons = showsIcons
        self.weeklyRemainingProvider = weeklyRemainingProvider
        self.stackedIcons = showsIcons && providers.count > 3
        let initialOuterPadding = Self.switcherOuterPadding(
            for: width,
            count: self.segments.count,
            minimumGap: minimumGap)
        let initialMaxAllowedSegmentWidth = Self.maxAllowedUniformSegmentWidth(
            for: width,
            count: self.segments.count,
            outerPadding: initialOuterPadding,
            minimumGap: minimumGap)
        self.useTwoRows = Self.shouldUseTwoRows(
            count: self.segments.count,
            maxAllowedSegmentWidth: initialMaxAllowedSegmentWidth,
            stackedIcons: self.stackedIcons)
        self.rowSpacing = self.stackedIcons ? 4 : 2
        self.rowHeight = self.stackedIcons ? 36 : 30
        let height: CGFloat = self.useTwoRows ? (self.rowHeight * 2 + self.rowSpacing) : self.rowHeight
        self.preferredWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let layoutCount = self.useTwoRows
            ? Int(ceil(Double(self.segments.count) / 2.0))
            : self.segments.count
        let outerPadding: CGFloat = Self.switcherOuterPadding(
            for: width,
            count: layoutCount,
            minimumGap: minimumGap)
        let maxAllowedSegmentWidth = Self.maxAllowedUniformSegmentWidth(
            for: width,
            count: layoutCount,
            outerPadding: outerPadding,
            minimumGap: minimumGap)

        func makeButton(index: Int, segment: Segment) -> NSButton {
            let button: NSButton
            if self.stackedIcons {
                let stacked = StackedToggleButton(
                    title: segment.title,
                    image: segment.image,
                    target: self,
                    action: #selector(self.handleSelection(_:)))
                button = stacked
            } else if self.showsIcons {
                let inline = InlineIconToggleButton(
                    title: segment.title,
                    image: segment.image,
                    target: self,
                    action: #selector(self.handleSelection(_:)))
                button = inline
            } else {
                button = PaddedToggleButton(
                    title: segment.title,
                    target: self,
                    action: #selector(self.handleSelection(_:)))
            }
            button.tag = index
            if self.showsIcons {
                if self.stackedIcons {
                    // StackedToggleButton manages its own image view.
                } else {
                    // InlineIconToggleButton manages its own image view.
                }
            } else {
                button.image = nil
                button.imagePosition = .noImage
            }

            let remaining = self.weeklyRemainingProvider(segment.provider)
            self.addWeeklyIndicator(to: button, provider: segment.provider, remainingPercent: remaining)
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            button.setButtonType(.toggle)
            button.contentTintColor = self.unselectedTextColor
            button.alignment = .center
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.state = (selected == segment.provider) ? .on : .off
            button.toolTip = nil
            button.translatesAutoresizingMaskIntoConstraints = false
            self.buttons.append(button)
            return button
        }

        for (index, segment) in self.segments.enumerated() {
            let button = makeButton(index: index, segment: segment)
            self.addSubview(button)
        }

        let uniformWidth: CGFloat
        if self.useTwoRows || !self.stackedIcons {
            uniformWidth = self.applyUniformSegmentWidth(maxAllowedWidth: maxAllowedSegmentWidth)
            if uniformWidth > 0 {
                self.segmentWidths = Array(repeating: uniformWidth, count: self.buttons.count)
            }
        } else {
            self.segmentWidths = self.applyNonUniformSegmentWidths(
                totalWidth: width,
                outerPadding: outerPadding,
                minimumGap: minimumGap)
            uniformWidth = 0
        }

        self.applyLayout(
            outerPadding: outerPadding,
            minimumGap: minimumGap,
            uniformWidth: uniformWidth)
        if width > 0 {
            self.preferredWidth = width
            self.frame.size.width = width
        }

        self.updateButtonStyles()
    }

    private func applyLayout(
        outerPadding: CGFloat,
        minimumGap: CGFloat,
        uniformWidth: CGFloat)
    {
        if self.useTwoRows {
            self.applyTwoRowLayout(
                outerPadding: outerPadding,
                minimumGap: minimumGap,
                uniformWidth: uniformWidth)
            return
        }

        if self.buttons.count == 2 {
            let left = self.buttons[0]
            let right = self.buttons[1]
            let gap = right.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: minimumGap)
            gap.priority = .defaultHigh
            NSLayoutConstraint.activate([
                left.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: outerPadding),
                left.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                right.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -outerPadding),
                right.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                gap,
            ])
            return
        }

        if self.buttons.count == 3 {
            let left = self.buttons[0]
            let mid = self.buttons[1]
            let right = self.buttons[2]

            let leftGap = mid.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: minimumGap)
            leftGap.priority = .defaultHigh
            let rightGap = right.leadingAnchor.constraint(
                greaterThanOrEqualTo: mid.trailingAnchor,
                constant: minimumGap)
            rightGap.priority = .defaultHigh

            NSLayoutConstraint.activate([
                left.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: outerPadding),
                left.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                mid.centerXAnchor.constraint(equalTo: self.centerXAnchor),
                mid.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                right.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -outerPadding),
                right.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                leftGap,
                rightGap,
            ])
            return
        }

        if self.buttons.count >= 4 {
            let widths = self.segmentWidths.isEmpty
                ? self.buttons.map { ceil($0.fittingSize.width) }
                : self.segmentWidths
            let layoutWidth = self.preferredWidth > 0 ? self.preferredWidth : self.bounds.width
            let availableWidth = max(0, layoutWidth - outerPadding * 2)
            let gaps = max(1, widths.count - 1)
            let computedGap = gaps > 0
                ? max(minimumGap, (availableWidth - widths.reduce(0, +)) / CGFloat(gaps))
                : 0
            let rowContainer = NSView()
            rowContainer.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(rowContainer)

            NSLayoutConstraint.activate([
                rowContainer.topAnchor.constraint(equalTo: self.topAnchor),
                rowContainer.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                rowContainer.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: outerPadding),
                rowContainer.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -outerPadding),
            ])

            var xOffset: CGFloat = 0
            for (index, button) in self.buttons.enumerated() {
                let width = index < widths.count ? widths[index] : 0
                if self.stackedIcons {
                    NSLayoutConstraint.activate([
                        button.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor, constant: xOffset),
                        button.topAnchor.constraint(equalTo: rowContainer.topAnchor),
                    ])
                } else {
                    NSLayoutConstraint.activate([
                        button.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor, constant: xOffset),
                        button.centerYAnchor.constraint(equalTo: rowContainer.centerYAnchor),
                    ])
                }
                xOffset += width + computedGap
            }
            return
        }

        if let first = self.buttons.first {
            NSLayoutConstraint.activate([
                first.centerXAnchor.constraint(equalTo: self.centerXAnchor),
                first.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            ])
        }
    }

    private func applyTwoRowLayout(
        outerPadding: CGFloat,
        minimumGap: CGFloat,
        uniformWidth: CGFloat)
    {
        let splitIndex = Int(ceil(Double(self.buttons.count) / 2.0))
        let topButtons = Array(self.buttons.prefix(splitIndex))
        let bottomButtons = Array(self.buttons.dropFirst(splitIndex))

        let columns = max(topButtons.count, bottomButtons.count)
        let layoutWidth = self.preferredWidth > 0 ? self.preferredWidth : self.bounds.width
        let availableWidth = max(0, layoutWidth - outerPadding * 2)
        let gaps = max(1, columns - 1)
        let totalWidth = uniformWidth * CGFloat(columns)
        let computedGap = gaps > 0
            ? max(minimumGap, (availableWidth - totalWidth) / CGFloat(gaps))
            : 0
        let gridContainer = NSView()
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(gridContainer)

        NSLayoutConstraint.activate([
            gridContainer.topAnchor.constraint(equalTo: self.topAnchor),
            gridContainer.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            gridContainer.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: outerPadding),
            gridContainer.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -outerPadding),
        ])

        let topRow = NSView()
        topRow.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.addSubview(topRow)

        let bottomRow = NSView()
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.addSubview(bottomRow)

        NSLayoutConstraint.activate([
            topRow.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: gridContainer.trailingAnchor),
            topRow.topAnchor.constraint(equalTo: gridContainer.topAnchor),
            topRow.heightAnchor.constraint(equalToConstant: self.rowHeight),
            bottomRow.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor),
            bottomRow.trailingAnchor.constraint(equalTo: gridContainer.trailingAnchor),
            bottomRow.bottomAnchor.constraint(equalTo: gridContainer.bottomAnchor),
            bottomRow.heightAnchor.constraint(equalToConstant: self.rowHeight),
            bottomRow.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: self.rowSpacing),
        ])

        for index in 0..<columns {
            let xOffset = CGFloat(index) * (uniformWidth + computedGap)
            if index < topButtons.count {
                let button = topButtons[index]
                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor, constant: xOffset),
                    button.centerYAnchor.constraint(equalTo: topRow.centerYAnchor),
                ])
            }
            if index < bottomButtons.count {
                let button = bottomButtons[index]
                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor, constant: xOffset),
                    button.centerYAnchor.constraint(equalTo: bottomRow.centerYAnchor),
                ])
            }
        }
    }

    private static func shouldUseTwoRows(
        count: Int,
        maxAllowedSegmentWidth: CGFloat,
        stackedIcons: Bool) -> Bool
    {
        guard count > 1 else { return false }
        let minimumComfortableAverage: CGFloat = stackedIcons ? 44 : 54
        return maxAllowedSegmentWidth < minimumComfortableAverage
    }

    private static func switcherOuterPadding(for width: CGFloat, count: Int, minimumGap: CGFloat) -> CGFloat {
        // Align with the card's left/right content grid when possible.
        let preferred: CGFloat = 16
        let reduced: CGFloat = 10
        let minimal: CGFloat = 6

        func averageButtonWidth(outerPadding: CGFloat) -> CGFloat {
            let available = width - outerPadding * 2 - minimumGap * CGFloat(max(0, count - 1))
            guard count > 0 else { return 0 }
            return available / CGFloat(count)
        }

        // Only sacrifice padding when we'd otherwise squeeze buttons into unreadable widths.
        let minimumComfortableAverage: CGFloat = count >= 5 ? 46 : 54

        if averageButtonWidth(outerPadding: preferred) >= minimumComfortableAverage { return preferred }
        if averageButtonWidth(outerPadding: reduced) >= minimumComfortableAverage { return reduced }
        return minimal
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: self.preferredWidth, height: self.frame.size.height)
    }

    @objc private func handleSelection(_ sender: NSButton) {
        let index = sender.tag
        guard self.segments.indices.contains(index) else { return }
        for (idx, button) in self.buttons.enumerated() {
            button.state = (idx == index) ? .on : .off
        }
        self.updateButtonStyles()
        self.onSelect(self.segments[index].provider)
    }

    private func updateButtonStyles() {
        for button in self.buttons {
            let isSelected = button.state == .on
            button.contentTintColor = isSelected ? self.selectedTextColor : self.unselectedTextColor
            button.layer?.backgroundColor = isSelected ? self.selectedBackground : self.unselectedBackground
            self.updateWeeklyIndicatorVisibility(for: button)
            (button as? StackedToggleButton)?.setContentTintColor(button.contentTintColor)
            (button as? InlineIconToggleButton)?.setContentTintColor(button.contentTintColor)
        }
    }

    private static func maxToggleWidth(for button: NSButton) -> CGFloat {
        let originalState = button.state
        defer { button.state = originalState }

        button.state = .off
        button.layoutSubtreeIfNeeded()
        let offWidth = button.fittingSize.width

        button.state = .on
        button.layoutSubtreeIfNeeded()
        let onWidth = button.fittingSize.width

        return max(offWidth, onWidth)
    }

    private func applyUniformSegmentWidth(maxAllowedWidth: CGFloat) -> CGFloat {
        guard !self.buttons.isEmpty else { return 0 }

        var desiredWidths: [CGFloat] = []
        desiredWidths.reserveCapacity(self.buttons.count)

        for (index, button) in self.buttons.enumerated() {
            if self.stackedIcons,
               self.segments.indices.contains(index)
            {
                let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                let titleWidth = ceil((self.segments[index].title as NSString).size(withAttributes: [.font: font])
                    .width)
                let contentPadding: CGFloat = 4 + 4
                let extraSlack: CGFloat = 1
                desiredWidths.append(ceil(titleWidth + contentPadding + extraSlack))
            } else {
                desiredWidths.append(ceil(Self.maxToggleWidth(for: button)))
            }
        }

        let maxDesired = desiredWidths.max() ?? 0
        let evenMaxDesired = maxDesired.truncatingRemainder(dividingBy: 2) == 0 ? maxDesired : maxDesired + 1
        let evenMaxAllowed = maxAllowedWidth > 0
            ? (maxAllowedWidth.truncatingRemainder(dividingBy: 2) == 0 ? maxAllowedWidth : maxAllowedWidth - 1)
            : 0
        let finalWidth: CGFloat = if evenMaxAllowed > 0 {
            min(evenMaxDesired, evenMaxAllowed)
        } else {
            evenMaxDesired
        }

        if finalWidth > 0 {
            for button in self.buttons {
                button.widthAnchor.constraint(equalToConstant: finalWidth).isActive = true
            }
        }

        return finalWidth
    }

    @discardableResult
    private func applyNonUniformSegmentWidths(
        totalWidth: CGFloat,
        outerPadding: CGFloat,
        minimumGap: CGFloat) -> [CGFloat]
    {
        guard !self.buttons.isEmpty else { return [] }

        let count = self.buttons.count
        let available = totalWidth -
            outerPadding * 2 -
            minimumGap * CGFloat(max(0, count - 1))
        guard available > 0 else { return [] }

        func evenFloor(_ value: CGFloat) -> CGFloat {
            var v = floor(value)
            if Int(v) % 2 != 0 { v -= 1 }
            return v
        }

        let desired = self.buttons.map { ceil(Self.maxToggleWidth(for: $0)) }
        let desiredSum = desired.reduce(0, +)
        let avg = floor(available / CGFloat(count))
        let minWidth = max(24, min(40, avg))

        var widths: [CGFloat]
        if desiredSum <= available {
            widths = desired
        } else {
            let totalCapacity = max(0, desiredSum - minWidth * CGFloat(count))
            if totalCapacity <= 0 {
                widths = Array(repeating: available / CGFloat(count), count: count)
            } else {
                let overflow = desiredSum - available
                widths = desired.map { desiredWidth in
                    let capacity = max(0, desiredWidth - minWidth)
                    let shrink = overflow * (capacity / totalCapacity)
                    return desiredWidth - shrink
                }
            }
        }

        widths = widths.map { max(minWidth, evenFloor($0)) }
        var used = widths.reduce(0, +)

        while available - used >= 2 {
            if let best = widths.indices
                .filter({ desired[$0] - widths[$0] >= 2 })
                .max(by: { lhs, rhs in
                    (desired[lhs] - widths[lhs]) < (desired[rhs] - widths[rhs])
                })
            {
                widths[best] += 2
                used += 2
                continue
            }

            guard let best = widths.indices.min(by: { lhs, rhs in widths[lhs] < widths[rhs] }) else { break }
            widths[best] += 2
            used += 2
        }

        for (index, button) in self.buttons.enumerated() where index < widths.count {
            button.widthAnchor.constraint(equalToConstant: widths[index]).isActive = true
        }

        return widths
    }

    private static func maxAllowedUniformSegmentWidth(
        for totalWidth: CGFloat,
        count: Int,
        outerPadding: CGFloat,
        minimumGap: CGFloat) -> CGFloat
    {
        guard count > 0 else { return 0 }
        let available = totalWidth -
            outerPadding * 2 -
            minimumGap * CGFloat(max(0, count - 1))
        guard available > 0 else { return 0 }
        return floor(available / CGFloat(count))
    }

    private static func paddedImage(_ image: NSImage, leading: CGFloat) -> NSImage {
        let size = NSSize(width: image.size.width + leading, height: image.size.height)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        let y = (size.height - image.size.height) / 2
        image.draw(
            at: NSPoint(x: leading, y: y),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0)
        newImage.unlockFocus()
        newImage.isTemplate = image.isTemplate
        return newImage
    }

    private func addWeeklyIndicator(to view: NSView, provider: UsageProvider, remainingPercent: Double?) {
        guard let remainingPercent else { return }

        let track = NSView()
        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.55).cgColor
        track.layer?.cornerRadius = 2
        track.layer?.masksToBounds = true
        track.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(track)

        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.backgroundColor = Self.weeklyIndicatorColor(for: provider).cgColor
        fill.layer?.cornerRadius = 2
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        let ratio = CGFloat(max(0, min(1, remainingPercent / 100)))

        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            track.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            track.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -1),
            track.heightAnchor.constraint(equalToConstant: 4),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
        ])

        fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: ratio).isActive = true

        self.weeklyIndicators[ObjectIdentifier(view)] = WeeklyIndicator(provider: provider, track: track, fill: fill)
        self.updateWeeklyIndicatorVisibility(for: view)
    }

    private func updateWeeklyIndicatorVisibility(for view: NSView) {
        guard let indicator = self.weeklyIndicators[ObjectIdentifier(view)] else { return }
        let isSelected = (view as? NSButton)?.state == .on

        // Hide indicator on selected segment; also hide when we have no data.
        indicator.track.isHidden = isSelected
        indicator.fill.isHidden = isSelected
    }

    private static func weeklyIndicatorColor(for provider: UsageProvider) -> NSColor {
        switch provider {
        case .codex:
            NSColor(deviceRed: 73 / 255, green: 163 / 255, blue: 176 / 255, alpha: 1)
        case .claude:
            NSColor(deviceRed: 204 / 255, green: 124 / 255, blue: 94 / 255, alpha: 1)
        case .zai:
            NSColor(deviceRed: 232 / 255, green: 90 / 255, blue: 106 / 255, alpha: 1)
        case .gemini:
            NSColor(deviceRed: 171 / 255, green: 135 / 255, blue: 234 / 255, alpha: 1) // #AB87EA
        case .antigravity:
            NSColor(deviceRed: 96 / 255, green: 186 / 255, blue: 126 / 255, alpha: 1)
        case .cursor:
            NSColor(deviceRed: 0 / 255, green: 191 / 255, blue: 165 / 255, alpha: 1) // #00BFA5
        case .factory:
            NSColor(deviceRed: 255 / 255, green: 107 / 255, blue: 53 / 255, alpha: 1) // Factory orange
        case .copilot:
            NSColor(deviceRed: 168 / 255, green: 85 / 255, blue: 247 / 255, alpha: 1) // Purple
        }
    }

    private static func switcherTitle(for provider: UsageProvider) -> String {
        switch provider {
        case .codex: "Codex"
        case .claude: "Claude"
        case .zai: "z.ai"
        case .gemini: "Gemini"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        case .factory: "Droid"
        case .copilot: "Copilot"
        }
    }
}
