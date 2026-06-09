import Foundation
import SwiftUI

/// 养成系统：每个 agent 的「伙伴」随干活攒经验、升级、进化。持久化到 UserDefaults。
struct BuddyStat: Codable {
    var exp: Int = 0
    var completed: Int = 0     // 完成轮数（Stop）
    var tools: Int = 0         // 工具调用
    var approvals: Int = 0     // 被你批准次数
}

@MainActor
final class BuddyStore: ObservableObject {
    @Published private(set) var stats: [String: BuddyStat] = [:]
    private let key = "buddyStats"

    enum Gain { case tool, approval, completion
        var exp: Int { switch self { case .tool: return 2; case .approval: return 5; case .completion: return 20 } }
    }

    init() { load() }

    func record(_ agent: AgentKind, _ g: Gain) {
        var s = stats[agent.rawValue] ?? BuddyStat()
        s.exp += g.exp
        switch g {
        case .tool: s.tools += 1
        case .approval: s.approvals += 1
        case .completion: s.completed += 1
        }
        stats[agent.rawValue] = s
        save()
    }

    func stat(_ agent: AgentKind) -> BuddyStat { stats[agent.rawValue] ?? BuddyStat() }

    // 每 100 exp 升一级
    func level(_ agent: AgentKind) -> Int { stat(agent).exp / 100 + 1 }
    func expInLevel(_ agent: AgentKind) -> Int { stat(agent).exp % 100 }

    func title(_ agent: AgentKind) -> String {
        switch level(agent) {
        case let l where l >= 20: return "宗师"
        case let l where l >= 12: return "大师"
        case let l where l >= 8:  return "资深"
        case let l where l >= 4:  return "熟练"
        case let l where l >= 2:  return "学徒"
        default: return "见习"
        }
    }

    /// 进化阶段（影响外观）：1 初始 / 2 长出星星 / 3 戴上皇冠
    func stage(_ agent: AgentKind) -> Int {
        let l = level(agent)
        return l >= 12 ? 3 : l >= 4 ? 2 : 1
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: BuddyStat].self, from: data) else { return }
        stats = decoded
    }
    private func save() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
