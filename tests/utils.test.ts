import { describe, it, expect, vi } from 'vitest';
import { withRetry } from '../src/main/utils/retry';
import { CircuitBreaker, CircuitState } from '../src/main/utils/circuit-breaker';

describe('withRetry', () => {
    it('should succeed on first attempt', async () => {
        const fn = vi.fn().mockResolvedValue('success');
        const result = await withRetry(fn);
        expect(result).toBe('success');
        expect(fn).toHaveBeenCalledTimes(1);
    });

    it('should retry on failure and succeed', async () => {
        const fn = vi.fn()
            .mockRejectedValueOnce({ response: { status: 500 } })
            .mockResolvedValue('success');
        const result = await withRetry(fn, { maxAttempts: 3, baseDelay: 10 });
        expect(result).toBe('success');
        expect(fn).toHaveBeenCalledTimes(2);
    });

    it('should throw after max attempts', async () => {
        const fn = vi.fn().mockRejectedValue({ response: { status: 500 } });
        await expect(withRetry(fn, { maxAttempts: 2, baseDelay: 10 })).rejects.toThrow();
        expect(fn).toHaveBeenCalledTimes(2);
    });

    it('should not retry on non-retryable errors', async () => {
        const fn = vi.fn().mockRejectedValue({ response: { status: 400 } });
        await expect(withRetry(fn, { maxAttempts: 3, baseDelay: 10 })).rejects.toThrow();
        expect(fn).toHaveBeenCalledTimes(1);
    });
});

describe('CircuitBreaker', () => {
    it('should start in CLOSED state', () => {
        const breaker = new CircuitBreaker('test');
        expect(breaker.getState()).toBe(CircuitState.CLOSED);
    });

    it('should open after failure threshold', async () => {
        const breaker = new CircuitBreaker('test', { failureThreshold: 2, timeout: 1000 });

        try {
            await breaker.execute(() => Promise.reject(new Error('fail')));
        } catch {}
        try {
            await breaker.execute(() => Promise.reject(new Error('fail')));
        } catch {}

        expect(breaker.getState()).toBe(CircuitState.OPEN);
    });

    it('should allow execution when CLOSED', async () => {
        const breaker = new CircuitBreaker('test');
        const fn = vi.fn().mockResolvedValue('success');
        const result = await breaker.execute(fn);
        expect(result).toBe('success');
    });

    it('should reject when OPEN', async () => {
        const breaker = new CircuitBreaker('test', { failureThreshold: 1, timeout: 1000 });
        try {
            await breaker.execute(() => Promise.reject(new Error('fail')));
        } catch {}

        await expect(breaker.execute(() => Promise.resolve('success')))
            .rejects.toThrow('Circuit breaker test is OPEN');
    });
});
