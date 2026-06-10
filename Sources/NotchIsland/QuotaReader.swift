import Foundation

/// 读取额度缓存并解析成 AgentQuota。
/// - Claude: ~/.notch-island/cache/rl.json（statusLine 采集器写入；仅终端会话触发，
///   Claude Desktop 不渲染 statusLine 所以不会产出）
/// - Codex : 码岛缓存 → 回退 Vibe Island 的 usage-persist-openai.json（OpenAI app-server 真实用量）
/// 所有来源都做新鲜度检查，过期数据宁可不显示也不骗人。
enum QuotaReader {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var notchDir: URL { home.appendingPathComponent(".notch-island/cache") }
    static var vibeDir: URL  { home.appendingPathComponent(".vibe-island/cache") }

    /// 数据超过这个时长视为过期（秒）
    static let maxAge: TimeInterval = 6 * 3600

    static func readAll() -> [AgentQuota] {
        var out: [AgentQuota] = []
        if let c = readClaude() { out.append(c) }
        if let x = readCodex() { out.append(x) }
        return out
    }

    private static func readClaude() -> AgentQuota? {
        guard let json = freshJSON([notchDir.appendingPathComponent("rl.json")]) else { return nil }
        return quota(.claude, json)
    }

    private static func readCodex() -> AgentQuota? {
        let candidates = [
            notchDir.appendingPathComponent("usage-openai.json"),
            vibeDir.appendingPathComponent("usage-persist-openai.json"),
        ]
        guard let json = freshJSON(candidates) else { return nil }
        return quota(.codex, json)
    }

    private static func quota(_ agent: AgentKind, _ json: [String: Any]) -> AgentQuota? {
        let five = window("5h", json["five_hour"])
        let seven = window("7d", json["seven_day"])
        guard five != nil || seven != nil else { return nil }
        return AgentQuota(agent: agent,
                          fiveHour: five ?? QuotaWindow(label: "5h", usedPercent: 0, resetsAt: nil),
                          sevenDay: seven ?? QuotaWindow(label: "7d", usedPercent: 0, resetsAt: nil))
    }

    private static func window(_ label: String, _ any: Any?) -> QuotaWindow? {
        guard let d = any as? [String: Any] else { return nil }
        let pct = (d["used_percentage"] as? NSNumber)?.intValue ?? -1
        guard pct >= 0 else { return nil }
        var reset: Date? = nil
        if let r = (d["resets_at"] as? NSNumber)?.doubleValue {
            reset = Date(timeIntervalSince1970: r)
        }
        return QuotaWindow(label: label, usedPercent: pct, resetsAt: reset)
    }

    /// 依次尝试候选文件，返回第一个「新鲜」的 JSON。
    /// 新鲜度：fetched_at 字段优先，否则文件 mtime；超过 maxAge 跳过。
    private static func freshJSON(_ urls: [URL]) -> [String: Any]? {
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let ts: Date
            if let f = (obj["fetched_at"] as? NSNumber)?.doubleValue {
                ts = Date(timeIntervalSince1970: f)
            } else if let m = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date {
                ts = m
            } else { continue }
            if Date().timeIntervalSince(ts) <= maxAge { return obj }
        }
        return nil
    }
}
