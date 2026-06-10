import Foundation

/// Codex Desktop currently exposes completion through `notify`, but not turn-start.
/// This watcher fills that gap by looking at Codex's local activity log and emitting
/// a lightweight running event while a thread is actively streaming.
@MainActor
final class CodexActivityWatcher {
    private let onEvent: (IngestEvent) -> Void
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var timer: Timer?
    private var activeThreads: [String: Date] = [:]
    private var lastRunningEmitAt: [String: Date] = [:]
    private let activeLookbackSeconds = 12
    private let idleAfterSeconds: TimeInterval = 16

    init(onEvent: @escaping (IngestEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let activeIDs = activeThreadIDs()
        guard !activeIDs.isEmpty else {
            markIdleIfStale()
            return
        }
        let now = Date()
        for threadID in activeIDs {
            activeThreads[threadID] = now
            if now.timeIntervalSince(lastRunningEmitAt[threadID] ?? .distantPast) >= 4 {
                emitRunning(threadID)
                lastRunningEmitAt[threadID] = now
            }
        }
        markIdleIfStale()
    }

    private func emitRunning(_ threadID: String) {
        let meta = threadMeta(threadID)
        let cwd = meta.cwd.isEmpty ? FileManager.default.currentDirectoryPath : meta.cwd
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        let title = cleanedTitle(meta.title, fallback: meta.preview)
        let prompt = meta.preview.isEmpty ? title : meta.preview
        onEvent(.init(session: "codex-\(threadID)",
                      agent: "codex",
                      project: project.isEmpty ? "Codex" : project,
                      cwd: cwd,
                      event: "PreToolUse",
                      tool: "Codex",
                      tool_summary: "正在运行",
                      user: prompt))
    }

    private func activeThreadIDs() -> [String] {
        let db = home.appendingPathComponent(".codex/logs_2.sqlite").path
        guard FileManager.default.fileExists(atPath: db) else { return [] }
        let query = """
        select thread_id from logs
        where thread_id is not null
          and ts > strftime('%s','now') - \(activeLookbackSeconds)
          and target in (
            'codex_api::sse::responses',
            'codex_api::endpoint::responses_websocket',
            'codex_core::stream_events_utils',
            'codex_client::request',
            'hyper_util::client::legacy::client',
            'hyper_util::client::legacy::pool',
            'hyper_util::client::legacy::connect::http'
          )
        group by thread_id
        order by max(ts) desc, max(ts_nanos) desc
        limit 8;
        """
        return runSQLite(db, query)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func markIdleIfStale() {
        let now = Date()
        let staleIDs = activeThreads.compactMap { threadID, lastSeen in
            now.timeIntervalSince(lastSeen) >= idleAfterSeconds ? threadID : nil
        }
        for threadID in staleIDs {
            emitIdle(threadID)
            activeThreads.removeValue(forKey: threadID)
            lastRunningEmitAt.removeValue(forKey: threadID)
        }
    }

    private func emitIdle(_ threadID: String) {
        let meta = threadMeta(threadID)
        let cwd = meta.cwd.isEmpty ? FileManager.default.currentDirectoryPath : meta.cwd
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        onEvent(.init(session: "codex-\(threadID)",
                      agent: "codex",
                      project: project.isEmpty ? "Codex" : project,
                      cwd: cwd,
                      event: "Notification",
                      message: "Codex 空闲"))
    }

    private func threadMeta(_ id: String) -> (title: String, cwd: String, preview: String) {
        let db = home.appendingPathComponent(".codex/state_5.sqlite").path
        guard FileManager.default.fileExists(atPath: db) else { return ("Codex", "", "") }
        let safeID = id.replacingOccurrences(of: "'", with: "''")
        let query = """
        select coalesce(title,'') as title, coalesce(cwd,'') as cwd, substr(coalesce(preview,''), 1, 180) as preview
        from threads where id = '\(safeID)' limit 1;
        """
        guard let meta = decodeCodexMeta(runSQLite(db, query, json: true)) else { return ("Codex", "", "") }
        return (meta.title, meta.cwd, meta.preview)
    }

    private func decodeCodexMeta(_ json: String) -> CodexThreadMeta? {
        guard let data = json.data(using: .utf8),
              let rows = try? JSONDecoder().decode([CodexThreadMeta].self, from: data) else { return nil }
        return rows.first
    }

    private struct CodexThreadMeta: Decodable {
        var title: String
        var cwd: String
        var preview: String
    }

    private func cleanedTitle(_ title: String, fallback: String) -> String {
        for source in [title, fallback] {
            for rawLine in source.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line.hasPrefix("http://") || line.hasPrefix("https://") { continue }
                return line
            }
        }
        return "Codex"
    }

    private func runSQLite(_ db: String, _ query: String, json: Bool = false) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = json ? ["-json", db, query] : [db, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
