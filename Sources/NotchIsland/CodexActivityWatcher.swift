import Foundation

/// Codex Desktop currently exposes completion through `notify`, but not turn-start.
/// This watcher fills that gap by looking at Codex's local activity log and emitting
/// a lightweight running event while a thread is actively streaming.
@MainActor
final class CodexActivityWatcher {
    private let onEvent: (IngestEvent) -> Void
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var timer: Timer?
    private var lastEmittedThread: String?
    private var lastEmitAt: Date = .distantPast

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
        guard let threadID = latestActiveThreadID() else { return }
        if threadID == lastEmittedThread, Date().timeIntervalSince(lastEmitAt) < 4 {
            return
        }
        lastEmittedThread = threadID
        lastEmitAt = Date()

        let meta = threadMeta(threadID)
        let cwd = meta.cwd.isEmpty ? FileManager.default.currentDirectoryPath : meta.cwd
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        let title = meta.title.isEmpty ? "Codex" : meta.title
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

    private func latestActiveThreadID() -> String? {
        let db = home.appendingPathComponent(".codex/logs_2.sqlite").path
        guard FileManager.default.fileExists(atPath: db) else { return nil }
        let query = """
        select thread_id from logs
        where thread_id is not null
          and ts > strftime('%s','now') - 8
        order by ts desc, ts_nanos desc
        limit 1;
        """
        return runSQLite(db, query).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func threadMeta(_ id: String) -> (title: String, cwd: String, preview: String) {
        let db = home.appendingPathComponent(".codex/state_5.sqlite").path
        guard FileManager.default.fileExists(atPath: db) else { return ("Codex", "", "") }
        let safeID = id.replacingOccurrences(of: "'", with: "''")
        let query = """
        select coalesce(title,'') || char(31) || coalesce(cwd,'') || char(31) || substr(coalesce(preview,''), 1, 180)
        from threads where id = '\(safeID)' limit 1;
        """
        let parts = runSQLite(db, query)
            .trimmingCharacters(in: .newlines)
            .split(separator: Character(UnicodeScalar(31)), omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count >= 3 else { return ("Codex", "", "") }
        return (parts[0], parts[1], parts[2])
    }

    private func runSQLite(_ db: String, _ query: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [db, query]
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
