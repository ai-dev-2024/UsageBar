import CodexBarCore
import Foundation

extension UsageStore {
    func tokenSnapshot(for provider: UsageProvider) -> CCUsageTokenSnapshot? {
        self.tokenSnapshots[provider]
    }

    func tokenError(for provider: UsageProvider) -> String? {
        self.tokenErrors[provider]
    }

    func refreshTokenUsage(_ provider: UsageProvider) async {
        guard provider == .codex else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            return
        }

        guard self.settings.tokenCostUsageEnabled else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            return
        }

        guard self.isEnabled(provider) else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            return
        }

        let now = Date()
        if let last = self.lastTokenFetchAt[provider],
           now.timeIntervalSince(last) < self.tokenFetchTTL,
           self.tokenSnapshots[provider] != nil
        {
            return
        }
        self.lastTokenFetchAt[provider] = now

        do {
            let fetcher = self.ccusageFetcher
            let snapshot = try await Task.detached(priority: .utility) {
                try await fetcher.loadTokenSnapshot(cli: CCUsageFetcher.CLI.codex, now: now)
            }.value
            self.tokenSnapshots[provider] = snapshot
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.recordSuccess()
        } catch {
            if let ccusageError = error as? CCUsageError,
               case .cliNotInstalled = ccusageError
            {
                self.tokenSnapshots.removeValue(forKey: provider)
                self.tokenErrors[provider] = nil
                return
            }
            let hadPriorData = self.tokenSnapshots[provider] != nil
            let shouldSurface = self.tokenFailureGates[provider]?
                .shouldSurfaceError(onFailureWithPriorData: hadPriorData) ?? true
            if shouldSurface {
                self.tokenErrors[provider] = error.localizedDescription
                self.tokenSnapshots.removeValue(forKey: provider)
            } else {
                self.tokenErrors[provider] = nil
            }
        }
    }
}
