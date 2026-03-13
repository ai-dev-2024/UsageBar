/**
 * Usage History - Tracks usage data over time for trend visualization
 */

import Store from 'electron-store';

interface UsageDataPoint {
    timestamp: number;
    providerId: string;
    sessionPercent: number;
    weeklyPercent?: number;
}

interface UsageHistoryStore {
    history: UsageDataPoint[];
}

const MAX_HISTORY_DAYS = 7;
const MAX_ENTRIES = 1000; // Prevent unbounded growth

export class UsageHistory {
    private store: Store<UsageHistoryStore>;

    constructor() {
        this.store = new Store<UsageHistoryStore>({
            name: 'usage-history',
            defaults: {
                history: []
            }
        });

        // Clean old entries on startup
        this.cleanup();
    }

    /**
     * Record a usage data point
     */
    record(providerId: string, sessionPercent: number, weeklyPercent?: number): void {
        const history = this.store.get('history', []);

        history.push({
            timestamp: Date.now(),
            providerId,
            sessionPercent,
            weeklyPercent
        });

        // Trim if too many entries
        if (history.length > MAX_ENTRIES) {
            history.splice(0, history.length - MAX_ENTRIES);
        }

        this.store.set('history', history);
    }

    /**
     * Get history for a specific provider
     */
    getProviderHistory(providerId: string, daysBack: number = 7): UsageDataPoint[] {
        const cutoff = Date.now() - (daysBack * 24 * 60 * 60 * 1000);
        const history = this.store.get('history', []);

        return history.filter(
            (point) => point.providerId === providerId && point.timestamp >= cutoff
        );
    }

    /**
     * Get aggregated daily averages for a provider
     */
    getDailyAverages(providerId: string, daysBack: number = 7): { date: string; avgSession: number; avgWeekly: number }[] {
        const history = this.getProviderHistory(providerId, daysBack);
        const byDay: { [date: string]: { sessions: number[]; weeklys: number[] } } = {};

        history.forEach((point) => {
            const date = new Date(point.timestamp).toISOString().split('T')[0];
            if (!byDay[date]) {
                byDay[date] = { sessions: [], weeklys: [] };
            }
            byDay[date].sessions.push(point.sessionPercent);
            if (point.weeklyPercent !== undefined) {
                byDay[date].weeklys.push(point.weeklyPercent);
            }
        });

        return Object.entries(byDay).map(([date, data]) => ({
            date,
            avgSession: data.sessions.reduce((a, b) => a + b, 0) / data.sessions.length,
            avgWeekly: data.weeklys.length > 0
                ? data.weeklys.reduce((a, b) => a + b, 0) / data.weeklys.length
                : 0
        })).sort((a, b) => a.date.localeCompare(b.date));
    }

    /**
     * Remove entries older than MAX_HISTORY_DAYS
     */
    private cleanup(): void {
        const cutoff = Date.now() - (MAX_HISTORY_DAYS * 24 * 60 * 60 * 1000);
        const history = this.store.get('history', []);
        const filtered = history.filter((point) => point.timestamp >= cutoff);

        if (filtered.length !== history.length) {
            this.store.set('history', filtered);
            console.log(`Cleaned ${history.length - filtered.length} old history entries`);
        }
    }

    /**
     * Clear all history
     */
    clear(): void {
        this.store.set('history', []);
    }
}
