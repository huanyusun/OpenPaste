import SwiftUI
import ServiceManagement

/// 偏好设置
struct SettingsView: View {
    @AppStorage("retentionDays") private var retentionDays = 0 // 0 = 永久
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("mcpEnabled") private var mcpEnabled = true
    @AppStorage("mcpToken") private var mcpToken = ""

    var body: some View {
        Form {
            Section("通用") {
                Toggle("登录时自动启动 OpenPaste", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        setLaunchAtLogin(enabled)
                    }
                Text("首次开启时系统可能弹出确认框，请在通知中允许。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("历史") {
                Picker("保留时长", selection: $retentionDays) {
                    Text("永久保留").tag(0)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                    Text("1 年").tag(365)
                }
                .pickerStyle(.segmented)
                Text("固定到 Pinboard 的条目不受保留时长影响。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("MCP 服务器（接 Claude / Cursor 等 AI 客户端）") {
                Toggle("启用本地 MCP 服务器", isOn: $mcpEnabled)
                if mcpEnabled {
                    LabeledContent("端点", value: "http://127.0.0.1:3789/mcp")
                        .font(.system(size: 11).monospaced())
                    HStack {
                        Text("令牌").font(.callout)
                        Text(mcpToken.isEmpty ? "（启动后生成）" : mcpToken)
                            .font(.system(size: 11).monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("拷贝") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(mcpToken, forType: .string)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("接入 Claude Code：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("claude mcp add --transport http --scope user openpaste \(endpointDescription) --header \"Authorization: Bearer \(mcpToken)\"")
                            .font(.system(size: 10).monospaced())
                            .textSelection(.enabled)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    Text("仅监听 127.0.0.1，外部设备无法访问；令牌等同本机剪贴板读取权限，勿外传。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("快捷键速查") {
                VStack(alignment: .leading, spacing: 4) {
                    shortcutRow("⇧⌘V", "呼出 / 收起面板")
                    shortcutRow("⌘1–9", "粘贴最近 1–9 条（面板打开时）")
                    shortcutRow("← →", "切换选中卡片")
                    shortcutRow("Return", "粘贴选中（队列激活时=粘贴下一条）")
                    shortcutRow("⇧Return", "按纯文本粘贴")
                    shortcutRow("⌘N", "加入 / 移出粘贴队列")
                    shortcutRow("空格", "大图预览（Quick Look）")
                    shortcutRow("⌘E / ⌘R", "编辑内容 / 重命名")
                    shortcutRow("Esc", "逐层关闭浮层 → 收起面板")
                }
            }
            Section("权限") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: AccessibilityHelper.isGranted() ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(AccessibilityHelper.isGranted() ? .green : .orange)
                        Text(AccessibilityHelper.isGranted() ? "辅助功能权限已授予（可直接粘贴到光标处）" : "需要辅助功能权限才能直接粘贴到光标处")
                            .font(.callout)
                    }
                    if !AccessibilityHelper.isGranted() {
                        Button("打开系统设置授予") {
                            AccessibilityHelper.openSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }
            Section("关于") {
                LabeledContent("OpenPaste", value: "Paste 复刻 · v0.3.0")
                LabeledContent("数据目录", value: HistoryStore.appSupportDir.path)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 680)
    }

    private var endpointDescription: String {
        "http://127.0.0.1:3789/mcp"
    }

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 4))
                .frame(width: 90, alignment: .leading)
            Text(desc).font(.callout)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}

/// 辅助功能权限检测
enum AccessibilityHelper {
    static func isGranted() -> Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
