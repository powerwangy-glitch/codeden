import Foundation
import SwiftUI

/// 支持的 agent 种类。color/displayName 用于 UI；rawValue 用于事件里的 "agent" 字段。
enum AgentKind: String, Codable, CaseIterable {
    case claude, codex, gemini, cursor, unknown

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex:  return "Codex"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor"
        case .unknown: return "Agent"
        }
    }
    var color: Color {
        switch self {
        case .claude: return Color(red: 0xFF/255, green: 0xC8/255, blue: 0x57/255)
        case .codex:  return Color(red: 0x10/255, green: 0xA3/255, blue: 0x7F/255)
        case .gemini: return Color(red: 0x5E/255, green: 0xA0/255, blue: 1.0)
        case .cursor: return Color(red: 0xC0/255, green: 0x8B/255, blue: 1.0)
        case .unknown: return .gray
        }
    }
    static func from(_ raw: String?) -> AgentKind {
        AgentKind(rawValue: (raw ?? "").lowercased()) ?? .unknown
    }
}

/// 一个会话当前的状态，由事件驱动。
enum SessionState: String {
    case running     // 正在跑工具 / 思考
    case compacting  // 压缩上下文中
    case waiting     // 需要你：权限审批 或 提问
    case done        // 刚完成一轮（短暂）
    case idle        // 等待你输入

    var label: String {
        switch self {
        case .running:    return "运行中"
        case .compacting: return "压缩中"
        case .waiting:    return "需要你处理"
        case .done:       return "已完成"
        case .idle:       return "等待输入"
        }
    }
    var dotColor: Color {
        switch self {
        case .running:    return Color(red: 0x5E/255, green: 0x9E/255, blue: 1.0)
        case .compacting: return Color(red: 0xC0/255, green: 0x8B/255, blue: 1.0)
        case .waiting:    return Color(red: 1.0, green: 0xB3/255, blue: 0x40/255)
        case .done:       return Color(red: 0x5F/255, green: 0xD4/255, blue: 0x7F/255)
        case .idle:       return Color(white: 0.42)
        }
    }
    /// 算「忙」的状态（收起态归入运行）
    var isBusy: Bool { self == .running || self == .compacting }
}

/// 归一化事件：bridge 写入 events.jsonl 的每一行。
struct IngestEvent: Codable {
    var ts: Double?
    var session: String
    var agent: String?
    var project: String?
    var cwd: String?
    var event: String                 // hook_event_name
    var tool: String?
    var tool_summary: String?         // 工具参数摘要，如文件路径
    var user: String?                 // 你最后说的话
    var assistant: String?            // agent 最后输出片段
    var message: String?              // Notification 文本
    var subagents: Int?               // 当前子 agent 数
    var request_id: String?           // PermissionRequest 关联 id（审批回写用）
    var term: String?                 // 终端显示名（iTerm2/Ghostty…）
    var term_bundle: String?          // 终端 bundle id（点击跳转用）
    var term_tty: String?             // 终端 TTY（用于精确跳回 tab/session）
    var plan: String?                 // ExitPlanMode 的计划全文
    var questions: [QuestionSpec]?    // AskUserQuestion 的问题列表
}

/// AskUserQuestion 的问题结构（与 Claude Code tool_input 对齐）。
struct QuestionSpec: Codable, Hashable {
    var question: String
    var header: String?
    var multiSelect: Bool?
    var options: [Option]
    struct Option: Codable, Hashable {
        var label: String
        var description: String?
    }
}

/// 渲染用的会话视图模型。
struct Session: Identifiable {
    let id: String                    // session_id
    var agent: AgentKind
    var project: String
    var task: String                  // 任务标题（来自终端标题/首条 prompt）
    var state: SessionState
    var user: String                  // "你：…"
    var line: ActivityLine            // 第三行：工具或 agent 输出
    var badges: [Badge]
    var lastUpdate: Date
    var subagents: Int                // 额外 sprite 数量
    var requestID: String? = nil      // 非空 = 正在等你审批（可回写决定）
    var terminal: String = ""         // 终端显示名
    var bundleID: String? = nil       // 终端 bundle id（点击跳转）
    var tty: String? = nil            // 终端 TTY（Terminal/iTerm 精确跳转）
    var cwd: String = ""              // 工作目录（会话过滤用）
    var plan: String? = nil           // 待审批的计划全文（ExitPlanMode）
    var questions: [QuestionSpec]? = nil  // 待回答的提问（AskUserQuestion）
    var questionIndex: Int = 0        // 答题向导当前题号

    struct ActivityLine {
        var tool: String?             // 上色的工具名，如 "Bash"
        var text: String
    }
    struct Badge: Hashable { var text: String; var kind: Kind; enum Kind { case auto, neutral } }

    /// 距今多久，格式化成 "<1m" / "12m" / "3h"
    var elapsedLabel: String {
        let s = Int(Date().timeIntervalSince(lastUpdate))
        if s < 60 { return "<1m" }
        if s < 3600 { return "\(s/60)m" }
        return "\(s/3600)h"
    }
}

/// 单个额度窗口。
struct QuotaWindow {
    var label: String          // "5h" / "7d"
    var usedPercent: Int
    var resetsAt: Date?

    /// 距重置的人类可读时间，如 "3h29m" / "5d16h"
    var resetLabel: String {
        guard let r = resetsAt else { return "" }
        let s = Int(r.timeIntervalSinceNow)
        if s <= 0 { return "—" }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d\(h)h" }
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }
}

/// 一个 agent 账号的额度（5h + 7d）。
struct AgentQuota {
    var agent: AgentKind
    var fiveHour: QuotaWindow
    var sevenDay: QuotaWindow
    var danger: Bool { fiveHour.usedPercent >= 90 || sevenDay.usedPercent >= 90 }
}
