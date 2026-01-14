import { LogLevel, LoggerOptions } from '../../types';

type LogObject = Record<string, unknown>;

export class Logger {
    private level: LogLevel;
    private prefix: string;

    constructor(options: LoggerOptions = {}) {
        this.level = LogLevel[options.level || 'INFO'] ?? LogLevel.INFO;
        this.prefix = options.prefix || '';
    }

    private shouldLog(level: LogLevel): boolean {
        return level >= this.level;
    }

    private formatMessage(level: string, message: string, meta?: LogObject): string {
        const timestamp = new Date().toISOString();
        const metaStr = meta ? ` ${JSON.stringify(meta)}` : '';
        return `${timestamp} [${level}]${this.prefix ? ` [${this.prefix}]` : ''}: ${message}${metaStr}`;
    }

    debug(message: string, meta?: LogObject): void {
        if (this.shouldLog(LogLevel.DEBUG)) {
            console.debug(this.formatMessage('DEBUG', message, meta));
        }
    }

    info(message: string, meta?: LogObject): void {
        if (this.shouldLog(LogLevel.INFO)) {
            console.info(this.formatMessage('INFO', message, meta));
        }
    }

    warn(message: string, meta?: LogObject): void {
        if (this.shouldLog(LogLevel.WARN)) {
            console.warn(this.formatMessage('WARN', message, meta));
        }
    }

    error(message: string, error?: Error, meta?: LogObject): void {
        if (this.shouldLog(LogLevel.ERROR)) {
            const errorMeta = error ? { ...meta, stack: error.stack, name: error.name } : meta;
            console.error(this.formatMessage('ERROR', message, errorMeta));
        }
    }
}

export const createLogger = (options?: LoggerOptions): Logger => new Logger(options);
