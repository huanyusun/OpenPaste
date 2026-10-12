import Foundation
import AppKit

/// 剪贴板条目类型
enum ItemKind: Int32, Codable, CaseIterable {
    case text = 0
    case image = 1
    case file = 2
    case url = 3
    case rtf = 4
}

/// 智能分类类别（Paste LanguageModelItemClassifier 同款 8 类）
enum ItemCategory: String, Codable, CaseIterable {
    case secret   // 密码 / API key / token / 私钥
    case password
    case code
    case address
    case email
    case phone
    case number
    case other

    var displayName: String {
        switch self {
        case .secret: return "敏感信息"
        case .password: return "密码"
        case .code: return "代码"
        case .address: return "地址"
        case .email: return "邮箱"
        case .phone: return "电话"
        case .number: return "数字"
        case .other: return "文本"
        }
    }

    /// 敏感类别：预览需遮蔽
    var isSensitive: Bool { self == .secret || self == .password }

    /// 卡片角标符号
    var badge: String? {
        switch self {
        case .secret, .password: return "􀟹"
        case .code: return "{ }"
        case .email: return "✉"
        case .phone: return "☎"
        default: return nil
        }
    }
}

/// 一条剪贴板历史记录
struct ClipItem: Identifiable, Hashable {
    let id: Int64
    var kind: ItemKind
    /// 纯文本内容（文本/URL/RTF 提取文本）
    var text: String?
    /// 图片/PDF/文件数据存盘路径（历史目录下）
    var assetPath: String?
    /// 复制来源应用 bundle id
    var sourceApp: String?
    /// 来源应用显示名
    var sourceAppName: String?
    /// 来源设备（为未来多端同步预留）
    var sourceDevice: String
    var pinnedBoardID: Int64?
    /// 用户自定义名称（⌘R 重命名；显示时优先于预览文本）
    var customName: String?
    var createdAt: Date
    /// 粘贴次数（搜索排序的频次信号）
    var pasteCount: Int = 0
    /// 智能分类（启发式 / Apple Intelligence，nil = 未分类）
    var category: ItemCategory?

    /// 列表预览用短文本（敏感类别自动遮蔽）
    var previewText: String {
        if let customName, !customName.isEmpty { return customName }
        let raw: String
        switch kind {
        case .text, .url, .rtf:
            let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            raw = t.count > 120 ? String(t.prefix(120)) : t
        case .image:
            return "🖼 图片"
        case .file:
            let files = decodeFilePaths()
            if files.count == 1 { return "📄 " + (files[0] as NSString).lastPathComponent }
            return "📄 \(files.count) 个文件"
        }
        if category?.isSensitive == true {
            return String(repeating: "•", count: min(max(raw.count, 8), 24))
        }
        return raw
    }

    func decodeFilePaths() -> [String] {
        guard let data = text?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Pinboard（固定板）
struct PinBoard: Identifiable, Hashable {
    let id: Int64
    var name: String
    var icon: String
    var createdAt: Date
}
