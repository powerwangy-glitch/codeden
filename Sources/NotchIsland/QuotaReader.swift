import Foundation

/// 读取额度缓存并解析成 AgentQuota。
/// - Claude: rate_limits 缓存（Claude Code statusLine 的 .rate_limits 字段落盘）
/// - Codex : OpenAI app-server 用量缓存（{five_hour,seven_day:{used_percentage,resets_at}}）
///
/// 缓存路径默认指向本项目自己的 ~/.notch-island/，若不存在则回退读取已安装的
/// Vibe Island 缓存（方便本机演示出真实数字），都没有则返回占位。
enum QuotaReader {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var notchDir: URL { home.appendingPathComponent(".notch-island/cache") }
    static var vibeDir: URL  { home.appendingPathComponent(".vibe-island/cache") }

    static func readAll() -> [AgentQuota] {
        var out: [AgentQuota] = []
        if let c = readClaude() { out.append(c) }
        if let x = readCodex() { out.append(x) }
        return out
    }

    /// rl.json 形如 {"five_hour":{"used_percentage":3,"resets_at":<unix>}, "seven_day":{...}}
    /// Claude Code 的 rate_limits 实际字段名以版本为准，这里做容错解析。
    private static func readClaude() -> AgentQuota? {
        guard let json = firstJSON(["rl.json"]) else { return nil }
        let five = window("5h", json["five_hour"] ?? json["fiveHour"] ?? json["primary"])
        let seven = window("7d", json["seven_day"] ?? json["sevenDay"] ?? json["secondary"])
        guard five != nil || seven != nil else { return nil }
        return AgentQuota(agent: .claude,
                          fiveHour: five ?? QuotaWindow(label: "5h", usedPercent: 0, resetsAt: nil),
                          sevenDay: seven ?? QuotaWindow(label: "7d", usedPercent: 0, resetsAt: nil))
    }

    private static func readCodex() -> AgentQuota? {
        guard let json = firstJSON(["usage-openai.json", "usage-persist-openai.json"]) else { return nil }
        let five = window("5h", json["five_hour"])
        let seven = window("7d", json["seven_day"])
        guard five != nil || seven != nil else { return nil }
        return AgentQuota(agent: .codex,
                          fiveHour: five ?? QuotaWindow(label: "5h", usedPercent: 0, resetsAt: nil),
                          sevenDay: seven ?? QuotaWindow(label: "7d", usedPercent: 0, resetsAt: nil))
    }

    private static func window(_ label: String, _ any: Any?) -> QuotaWindow? {
        guard let d = any as? [String: Any] else { return nil }
        let pct = (d["used_percentage"] as? NSNumber)?.intValue
            ?? (d["used_percentage"] as? Int)
            ?? Int((d["used_percentage"] as? Double) ?? -1)
        guard pct >= 0 else { return nil }
        var reset: Date? = nil
        if let r = (d["resets_at"] as? NSNumber)?.doubleValue ?? (d["resets_at"] as? Double) {
            reset = Date(timeIntervalSince1970: r)
        }
        return QuotaWindow(label: label, usedPercent: pct, resetsAt: reset)
    }

    // 只读码岛自己采集的缓存，避免串到别的 App（如 Vibe Island）的数据导致额度不符。
    private static func firstJSON(_ names: [String]) -> [String: Any]? {
        for n in names {
            let url = notchDir.appendingPathComponent(n)
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }
        return nil
    }
}
