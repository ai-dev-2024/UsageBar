export interface RetryOptions {
    maxAttempts?: number;
    baseDelay?: number;
    maxDelay?: number;
    backoffMultiplier?: number;
    retryOn?: number[];
}

export async function withRetry<T>(
    fn: () => Promise<T>,
    options: RetryOptions = {}
): Promise<T> {
    const {
        maxAttempts = 3,
        baseDelay = 1000,
        maxDelay = 30000,
        backoffMultiplier = 2,
        retryOn = [429, 500, 502, 503, 504]
    } = options;

    let lastError: Error | undefined;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
            return await fn();
        } catch (error) {
            lastError = error as Error;
            const axiosError = error as { response?: { status?: number } };
            const status = axiosError.response?.status;

            if (status && !retryOn.includes(status)) {
                throw error;
            }

            if (attempt === maxAttempts) {
                throw lastError;
            }

            const delay = Math.min(baseDelay * Math.pow(backoffMultiplier, attempt - 1), maxDelay);
            const jitter = Math.random() * 0.3 * delay;

            await new Promise(resolve => setTimeout(resolve, delay + jitter));
        }
    }

    throw lastError;
}
