import { defineConfig } from '@playwright/test';

export default defineConfig({
    testDir: './tests',
    timeout: 30000,
    retries: 0,
    reporter: [['html', { open: 'never' }]],
    use: {
        screenshot: 'only-on-failure',
        trace: 'retain-on-failure',
    },
    projects: [
        {
            name: 'electron',
            use: {
                // Electron-specific options would go here
            },
        },
    ],
});
