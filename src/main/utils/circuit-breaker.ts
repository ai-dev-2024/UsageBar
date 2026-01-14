export enum CircuitState {
    CLOSED = 'CLOSED',
    OPEN = 'OPEN',
    HALF_OPEN = 'HALF_OPEN'
}

export interface CircuitBreakerOptions {
    failureThreshold?: number;
    successThreshold?: number;
    timeout?: number;
}

export class CircuitBreaker {
    private state: CircuitState = CircuitState.CLOSED;
    private failureCount = 0;
    private successCount = 0;
    private lastFailureTime = 0;
    private readonly failureThreshold: number;
    private readonly successThreshold: number;
    private readonly timeout: number;
    private readonly name: string;

    constructor(name: string, options: CircuitBreakerOptions = {}) {
        this.name = name;
        this.failureThreshold = options.failureThreshold || 5;
        this.successThreshold = options.successThreshold || 2;
        this.timeout = options.timeout || 30000;
    }

    getState(): CircuitState {
        if (this.state === CircuitState.OPEN && Date.now() - this.lastFailureTime > this.timeout) {
            this.state = CircuitState.HALF_OPEN;
        }
        return this.state;
    }

    async execute<T>(fn: () => Promise<T>): Promise<T> {
        const state = this.getState();

        if (state === CircuitState.OPEN) {
            throw new Error(`Circuit breaker ${this.name} is OPEN`);
        }

        try {
            const result = await fn();
            this.onSuccess();
            return result;
        } catch (error) {
            this.onFailure();
            throw error;
        }
    }

    private onSuccess(): void {
        if (this.state === CircuitState.HALF_OPEN) {
            this.successCount++;
            if (this.successCount >= this.successThreshold) {
                this.reset();
            }
        } else {
            this.failureCount = 0;
        }
    }

    private onFailure(): void {
        this.failureCount++;
        this.lastFailureTime = Date.now();

        if (this.failureCount >= this.failureThreshold) {
            this.state = CircuitState.OPEN;
        }
    }

    private reset(): void {
        this.state = CircuitState.CLOSED;
        this.failureCount = 0;
        this.successCount = 0;
    }
}

export const createCircuitBreaker = (name: string, options?: CircuitBreakerOptions): CircuitBreaker => {
    return new CircuitBreaker(name, options);
};
