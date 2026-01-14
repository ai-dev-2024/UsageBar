import { describe, it, expect, vi } from 'vitest';
import { Logger } from '../src/main/utils/logger';

describe('Logger', () => {
    it('should log messages at INFO level by default', () => {
        const logger = new Logger({ prefix: 'test' });
        const consoleSpy = vi.spyOn(console, 'info').mockImplementation(() => {});

        logger.info('test message', { key: 'value' });

        expect(consoleSpy).toHaveBeenCalled();
        const output = consoleSpy.mock.calls[0][0];
        expect(output).toContain('[INFO]');
        expect(output).toContain('[test]');
        expect(output).toContain('test message');
    });

    it('should not log DEBUG messages by default', () => {
        const logger = new Logger();
        const consoleSpy = vi.spyOn(console, 'debug').mockImplementation(() => {});

        logger.debug('debug message');

        expect(consoleSpy).not.toHaveBeenCalled();
    });

    it('should log DEBUG messages when level is DEBUG', () => {
        const logger = new Logger({ level: 'DEBUG' });
        const consoleSpy = vi.spyOn(console, 'debug').mockImplementation(() => {});

        logger.debug('debug message');

        expect(consoleSpy).toHaveBeenCalled();
    });

    it('should include error stack traces', () => {
        const logger = new Logger();
        const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        const error = new Error('test error');

        logger.error('error occurred', error);

        expect(consoleSpy).toHaveBeenCalled();
        const output = consoleSpy.mock.calls[0][0];
        expect(output).toContain('test error');
        expect(output).toContain('stack');
    });
});
