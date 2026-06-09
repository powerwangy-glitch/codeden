import Foundation

/// 实时 tail 一个 JSONL 事件文件：用 DispatchSource 监听追加写入，增量解析每一行。
/// 这是 App 唯一的数据入口——bridge 往文件追加，App 立即读到。
final class EventTailer {
    private let url: URL
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var offset: UInt64 = 0
    private var buffer = Data()
    private let onEvent: (IngestEvent) -> Void
    private let queue = DispatchQueue(label: "notch.tailer")

    init(url: URL, onEvent: @escaping (IngestEvent) -> Void) {
        self.url = url
        self.onEvent = onEvent
    }

    func start() {
        ensureFile()
        openAndSeekToEnd()
        watch()
    }

    private func ensureFile() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    private func openAndSeekToEnd() {
        fileHandle = try? FileHandle(forReadingFrom: url)
        // 从文件末尾开始，只关心新事件（避免重放历史）
        offset = (try? fileHandle?.seekToEnd()) ?? 0
    }

    private func watch() {
        guard let fh = fileHandle else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fh.fileDescriptor,
            eventMask: [.extend, .write, .delete, .rename],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // 文件被轮转/删除，重新打开
                self.reopen()
                return
            }
            self.readNew()
        }
        src.setCancelHandler { [weak self] in try? self?.fileHandle?.close() }
        source = src
        src.resume()
        // 启动后先读一次（覆盖 start 到 watch 之间的写入）
        readNew()
    }

    private func reopen() {
        source?.cancel(); source = nil
        try? fileHandle?.close(); fileHandle = nil
        offset = 0; buffer.removeAll()
        ensureFile()
        fileHandle = try? FileHandle(forReadingFrom: url)
        offset = 0
        watch()
    }

    private func readNew() {
        guard let fh = fileHandle else { return }
        do {
            // 处理文件被截断（清空/轮转）：当前大小小于已读 offset → 从头再读
            let size = (try? fh.seekToEnd()) ?? 0
            if size < offset { offset = 0; buffer.removeAll() }
            try fh.seek(toOffset: offset)
            let data = fh.readDataToEndOfFile()
            guard !data.isEmpty else { return }
            offset += UInt64(data.count)
            buffer.append(data)
            flushLines()
        } catch {
            reopen()
        }
    }

    private func flushLines() {
        let newline = UInt8(0x0A)
        while let idx = buffer.firstIndex(of: newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            guard !lineData.isEmpty else { continue }
            if let event = try? JSONDecoder().decode(IngestEvent.self, from: lineData) {
                DispatchQueue.main.async { self.onEvent(event) }
            }
        }
    }

    func stop() { source?.cancel(); source = nil }
}
