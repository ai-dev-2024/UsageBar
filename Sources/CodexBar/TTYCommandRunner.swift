import Darwin
import Foundation

/// Executes an interactive CLI inside a pseudo-terminal and returns all captured text.
/// Keeps it minimal so we can reuse for Codex and Claude without tmux.
struct TTYCommandRunner {
    struct Result {
        let text: String
    }

    struct Options {
        var rows: UInt16 = 50
        var cols: UInt16 = 160
        var timeout: TimeInterval = 20.0
        var extraArgs: [String] = []
    }

    enum Error: Swift.Error, LocalizedError {
        case binaryNotFound(String)
        case launchFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case let .binaryNotFound(bin): "Binary not found on PATH: \(bin)"
            case let .launchFailed(msg): "Failed to launch process: \(msg)"
            case .timedOut: "PTY command timed out."
            }
        }
    }

    // swiftlint:disable cyclomatic_complexity
    func run(binary: String, send script: String, options: Options = Options()) throws -> Result {
        guard let resolved = Self.which(binary) else { throw Error.binaryNotFound(binary) }

        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var term = termios()
        var win = winsize(ws_row: options.rows, ws_col: options.cols, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &secondaryFD, nil, &term, &win) == 0 else {
            throw Error.launchFailed("openpty failed")
        }
        // Make primary side non-blocking so read loops don't hang when no data is available.
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let primaryHandle = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: true)
        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: resolved)
        proc.arguments = options.extraArgs
        proc.standardInput = secondaryHandle
        proc.standardOutput = secondaryHandle
        proc.standardError = secondaryHandle

        try proc.run()

        func send(_ text: String) throws {
            guard let data = text.data(using: .utf8) else { return }
            try primaryHandle.write(contentsOf: data)
        }

        let deadline = Date().addingTimeInterval(options.timeout)
        var buffer = Data()
        func readChunk() {
            var tmp = [UInt8](repeating: 0, count: 8192)
            let n = Darwin.read(primaryFD, &tmp, tmp.count)
            if n > 0 { buffer.append(contentsOf: tmp.prefix(n)) }
        }

        func containsSession() -> Bool {
            let marker = Data("Current session".utf8)
            return buffer.contains(marker)
        }

        func containsWeek() -> Bool {
            let marker = Data("Current week (all models)".utf8)
            return buffer.contains(marker)
        }

        func containsCodexStatus() -> Bool {
            let markers = [
                "Credits:",
                "5h limit",
                "5-hour limit",
                "Weekly limit",
            ].map { Data($0.utf8) }
            return markers.contains { buffer.contains($0) }
        }

        func respondIfCursorQuerySeen() {
            let query = Data([0x1b, 0x5b, 0x36, 0x6e]) // ESC [ 6 n
            if buffer.contains(query) {
                // Pretend cursor is at 1;1, which is enough to satisfy Codex CLI's probe.
                try? send("\u{1b}[1;1R")
            }
        }

        func containsCodexUpdatePrompt() -> Bool {
            let needles = [
                "Update available!",
                "Run bun install -g @openai/codex",
                "0.60.1 ->",
            ]
            let lower = String(data: buffer, encoding: .utf8)?.lowercased() ?? ""
            return needles.contains { lower.contains($0.lowercased()) }
        }

        func containsCodexReadyScreen() -> Bool {
            // The main Codex shell shows these markers once past the update dialog.
            let lower = String(data: buffer, encoding: .utf8)?.lowercased() ?? ""
            return lower.contains("openai codex") && lower.contains("model:") && lower.contains("/status")
        }

        if script == "/usage" {
            // Boot loop: wait for TUI to be ready and handle first-run prompts.
            let bootDeadline = Date().addingTimeInterval(4.0)
            while Date() < bootDeadline {
                readChunk()
                respondIfCursorQuerySeen()
                guard let text = String(data: buffer, encoding: .utf8) else { break }
                let lower = text.lowercased()

                if lower.contains("do you trust the files in this folder") {
                    try send("1\r"); buffer.removeAll(); usleep(300_000); continue
                }
                if lower.contains("select a workspace") {
                    try send("\r"); buffer.removeAll(); usleep(300_000); continue
                }
                if lower.contains("telemetry") && lower.contains("(y/n)") {
                    try send("n\r"); buffer.removeAll(); usleep(300_000); continue
                }
                if lower.contains("sign in") || lower
                    .contains("login") || (lower.contains("please run") && lower.contains("claude login"))
                {
                    throw Error.launchFailed("Claude CLI requires login (`claude login`).")
                }
                if lower.contains("claude code") || lower.contains("tab to toggle") || lower.contains("try ") || !lower
                    .isEmpty
                {
                    break
                }
                usleep(150_000)
            }

            // Send the `/usage` slash command directly so the CLI lands on the Usage tab
            // without depending on palette search ordering. Claude sometimes drops the very
            // first Enter when the system is busy, so we keep retrying Enter later instead
            // of spamming other navigation keys.
            usleep(800_000) // let the CLI finish booting before we start typing
            try send("/usage")
            usleep(200_000)
            try send("\r") // initial Enter to execute the slash command
            let afterSlashEnter = Date()

            // Read until we see both session and weekly blocks. The CLI occasionally ignores Enter
            // when the host is under load, so we keep re-sending Enter at a sane cadence instead of
            // spraying tabs/escapes that can leave us in autocomplete.
            var gotSession = false
            var gotWeek = false
            var enterRetries = 0
            var lastEnter = afterSlashEnter
            var resendUsageRetries = 0
            usleep(600_000) // allow usage view to render before detection
            while Date() < deadline {
                readChunk()
                respondIfCursorQuerySeen()
                if containsSession() { gotSession = true }
                if containsWeek() { gotWeek = true }
                if gotSession, gotWeek { break }

                // Re-press Enter roughly once per 1.5s until usage shows up or retries are exhausted.
                if Date().timeIntervalSince(lastEnter) >= 1.5, enterRetries < 10 {
                    try? send("\r")
                    enterRetries += 1
                    lastEnter = Date()
                    usleep(120_000)
                    continue
                }

                // As a stronger nudge, re-send "/usage" + Enter a few times. This mirrors a human
                // re-typing the command when the palette ignored Enter because it was busy.
                if Date().timeIntervalSince(lastEnter) >= 3.0,
                   enterRetries >= 2,
                   resendUsageRetries < 3
                {
                    try? send("/usage")
                    usleep(100_000)
                    try? send("\r")
                    resendUsageRetries += 1
                    enterRetries += 1
                    lastEnter = Date()
                    usleep(200_000)
                    continue
                }

                usleep(150_000)
            }
            // After usage appears, read a bit longer to capture percent lines.
            let settleDeadline = Date().addingTimeInterval(2.0)
            while Date() < settleDeadline {
                readChunk()
                usleep(80000)
            }
        } else {
            // Generic behavior for other commands.
            usleep(400_000) // small boot grace
            let delayInitialSend = script.trimmingCharacters(in: .whitespacesAndNewlines) == "/status"
            if !delayInitialSend {
                try send(script)
                try send("\r")
                usleep(150_000)
                try send("\r")
                try send("\u{1b}")
            }

            var skippedCodexUpdate = false
            var sentScript = !delayInitialSend
            var updateSkipAttempts = 0

            while Date() < deadline {
                readChunk()
                respondIfCursorQuerySeen()
                if !skippedCodexUpdate, containsCodexUpdatePrompt() {
                    // Prompt shows options: 1) Update now, 2) Skip, 3) Skip until next version.
                    // Users report one Down + Enter is enough; follow with an extra Enter for safety, then re-run /status.
                    try? send("\u{1b}[B") // highlight option 2 (Skip)
                    usleep(120_000)
                    try? send("\r")
                    usleep(150_000)
                    try? send("\r") // if still focused on prompt, confirm again
                    try? send("/status")
                    try? send("\r")
                    updateSkipAttempts += 1
                    if updateSkipAttempts >= 1 {
                        skippedCodexUpdate = true
                        sentScript = false // re-send /status after dismissing
                        buffer.removeAll()
                    }
                    usleep(300_000)
                }
                if !sentScript, (!containsCodexUpdatePrompt() || skippedCodexUpdate) {
                    try? send(script)
                    try? send("\r")
                    sentScript = true
                    usleep(200_000)
                    continue
                }
                if containsSession() || containsWeek() || containsCodexStatus() || containsCodexReadyScreen() { break }
                usleep(120_000)
            }
        }

        // try to exit gracefully
        let exitData = Data("/exit\n".utf8)
        try? primaryHandle.write(contentsOf: exitData)
        proc.terminate()
        let waitDeadline = Date().addingTimeInterval(2.0)
        while proc.isRunning, Date() < waitDeadline {
            usleep(100_000)
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
        proc.waitUntilExit()

        guard let text = String(data: buffer, encoding: .utf8), !text.isEmpty else {
            throw Error.timedOut
        }

        return Result(text: text)
    }

    // swiftlint:enable cyclomatic_complexity

    static func which(_ tool: String) -> String? {
        // First try system PATH
        if let path = runWhich(tool) { return path }
        // Fallback to common locations (Homebrew, local bins)
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/\(tool)",
            "/usr/local/bin/\(tool)",
            "\(home)/.local/bin/\(tool)",
            "\(home)/bin/\(tool)",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    private static func runWhich(_ tool: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [tool]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty else { return nil }
        return path
    }
}
