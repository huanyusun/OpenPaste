# OpenPaste

Paste（pasteapp.io）的开源复刻版——macOS 剪贴板管理器，Swift/SwiftUI 原生实现，零第三方依赖。

## 当前能力（v0.3.1）

| 功能 | 快捷键 | 说明 |
|---|---|---|
| 剪贴板监听 | — | 自动捕获文本/富文本/URL/图片/文件，来源 App 记录 |
| 无限历史 | — | SQLite 本地存储，CRC32 指纹去重（Paste 同款），资产落盘 |
| 底部卡片流 | ⇧⌘V | Paste 原版同款规格：全屏宽 × 332pt 贴屏幕底、layer 24 压过 Dock、300×236 大预览卡片（CGWindowList 实测对齐）；另支持 `openpaste://toggle` URL scheme 唤出 |
| 快速粘贴 | ⌘1–9 | 仅面板可见时生效（不劫持系统快捷键） |
| **评分搜索** | 自动聚焦 | 匹配位置 + 使用频次 + 时间衰减三维排序（Paste candidate{score} 同思路） |
| Pinboard | — | 固定板创建/固定/取消，页签切换；页签右键可重命名/删除（删除时板上条目回到历史流，不丢数据） |
| **粘贴队列** | ⌘N / ⌘Return | Paste Stack：多条排队，逐条粘贴（填表单场景） |
| **重命名** | ⌘R | 给条目起好认的名字 |
| **编辑** | ⌘E | 文本条目原位编辑 |
| **预览** | 空格 | 文本全文/图片大图/文件列表浮层 |
| **智能分类** | — | 8 类（secret/password/code/email…），启发式 + Apple Intelligence 双客户端；敏感条目预览自动遮蔽 🔒 |
| **MCP 服务器** | — | 本地 127.0.0.1:3789，Bearer token 鉴权，4 工具（search/read_item/list_pinboards/copy_to_clipboard），接 Claude/Cursor |
| 直接粘贴 | Return | 模拟 ⌘V 写入光标处（需辅助功能权限） |
| 纯文本粘贴 | ⇧Return | 剥离格式 |
| 敏感应用排除 | — | 内置 1Password/Bitwarden/钥匙串黑名单 |
| 保留时长 | — | 永久/30/90/365 天（Pinboard 不受影响） |
| **开机自启** | — | SMAppService 登录项（偏好设置） |

### MCP 接入（AI 客户端读取剪贴板历史）

偏好设置 →「MCP 服务器」开启后（默认开），拷贝 token 后执行：

```bash
claude mcp add --transport http --scope user openpaste http://127.0.0.1:3789/mcp \
  --header "Authorization: Bearer <你的token>"
```

安全设计（对标 Paste）：仅监听 127.0.0.1；无 token 请求 transport 层直接 401；secret/password 类条目经 MCP 搜索时预览自动遮蔽，完整内容仅 read_item 可读。

## 构建与运行

```bash
# Debug 构建
swift build --package-path ./OpenPaste

# 打包成 OpenPaste.app（release）
./Scripts/build_app.sh
# 产物: OpenPaste/dist/OpenPaste.app
```

首次运行请到 **系统设置 → 隐私与安全性 → 辅助功能** 授权，否则「直接粘贴到光标处」不生效（仍可复制回剪贴板后手动 ⌘V）。

### 用 Xcode 打开（可选）

SPM 包可直接被 Xcode 打开：`open OpenPaste/Package.swift`，选中 OpenPaste scheme 直接 ⌘R 运行调试。

## 目录结构

```
OpenPaste/
├── Package.swift                  # SPM 清单（零依赖，macOS 13+）
├── Scripts/build_app.sh           # .app 打包脚本
└── Sources/OpenPaste/
    ├── OpenPasteApp.swift         # @main 入口
    ├── AppDelegate.swift          # 生命周期/菜单栏/服务装配/MCP 启动
    ├── Models.swift               # ClipItem / PinBoard / ItemKind / ItemCategory(8类)
    ├── HistoryStore.swift         # SQLite 存储 + CRC32 去重 + 评分搜索 + 迁移链
    ├── ClipboardMonitor.swift     # 剪贴板轮询捕获 + PNG 落盘 + ⌘V 模拟
    ├── CRC32.swift                # CRC32 指纹（Paste 同款去重算法）
    ├── ItemClassifier.swift       # 智能分类：启发式 + FoundationModels（Paste 原 Prompt）
    ├── MCPServer.swift            # MCP 服务器：JSON-RPC 2.0 + Bearer token + 4 工具
    ├── HotKeyCenter.swift         # Carbon RegisterEventHotKey 全局快捷键
    ├── PanelController.swift      # 底部悬浮面板 + 面板内键盘导航（本地监听）
    ├── HistoryViewModel.swift     # 卡片流状态 + 粘贴队列 + 编辑/重命名动作
    ├── HistoryView.swift          # SwiftUI 卡片流 UI + 队列条 + 状态提示
    ├── Overlays.swift             # 预览/编辑/重命名浮层
    └── SettingsView.swift         # 偏好设置（自启/保留时长/MCP/快捷键速查/权限）
```

## 与原版 Paste 的差距

见 [ROADMAP.md](ROADMAP.md)。v0.3.1 覆盖了 Paste 的核心体验 + 组织编辑（含 Pinboard 重命名/删除）+ 智能分类 + MCP 四件套；多端同步（CloudKit）、OCR/Spotlight 见 Phase 3；MCP OAuth 2.1、创建/删除工具见 Phase 4 后半。

## License

MIT（原版 Paste 为商业软件，本项目为独立学习性质实现，未使用其任何代码与资源）
