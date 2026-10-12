# OpenPaste 全量复刻路线图

对照 Paste（pasteapp.io，截至 2026-10 的 Paste 7）的功能全景，分五期推进。

## Phase 1 — MVP 核心体验 ✅（当前完成）

- [x] 剪贴板监听（文本/富文本/URL/图片/文件）
- [x] SQLite 无限历史 + 资产落盘 + 去重（相同内容只刷新时间）
- [x] 底部卡片流 UI（毛玻璃、悬停选中、双击粘贴、来源 App 标注）
- [x] 全局快捷键 ⇧⌘V；⌘1–9 仅面板可见时拦截（不劫持系统快捷键）
- [x] 搜索（内容 + 来源应用）+ 面板唤出自动聚焦搜索框
- [x] Pinboard 固定板（创建/固定/取消）
- [x] 纯文本粘贴 / 直接粘贴（CGEvent ⌘V）
- [x] 敏感应用排除（内置黑名单）
- [x] 暂停捕获 / 保留时长 / 菜单栏

## Phase 1.5 — 组织与编辑 ✅（v0.2.0 完成）

- [x] **Paste Stack 粘贴队列**：右键/⌘N 加入队列（橙色描边标识），队列条显示顺序，⌘Return 或按钮「粘贴下一条」逐条弹出，队列激活时面板不自动收起
- [x] **条目重命名（⌘R）**：custom_name 列（平滑迁移），重命名后卡片加粗显示自定义名
- [x] **条目编辑（⌘E）**：文本类条目原位编辑保存
- [x] **Quick Look 预览（空格）**：文本等宽字体全文/图片大图/文件路径列表浮层
- [x] **键盘导航完善**：Esc 逐层关闭浮层→收面板；⌘N/⌘E/⌘R 面板内快捷键；状态提示浮层
- [x] **开机自启**：SMAppService 登录项（偏好设置开关）
- [x] **Pinboard 管理（v0.3.1）**：页签右键重命名/删除（删除带确认，板上条目解绑回历史流不删数据）；「+」新建改为输入板名弹窗
- [ ] 上下左右跨行选择（当前单行卡片流，↑↓ 同 ←→）
- [ ] Pinboard 独立快捷键（每板可绑定）

## Phase 2 — 组织与效率

- [ ] 高级过滤器：按类型/应用/日期/设备/智能分类组合过滤
- [ ] Jump to History：搜索结果跳回历史原位（带上下文）
- [ ] 拖拽粘贴：卡片拖入目标应用
- [ ] 链接内置预览（WKWebView 小窗）
- [ ] 图片条目编辑（旋转/裁剪/提取文字）
- [ ] 排除应用管理界面（当前为硬编码黑名单）
- [ ] 快捷键自定义 UI（当前 Carbon 固定 ⇧⌘V）
- [ ] CoreSpotlight 集成（剪贴板历史进系统全局搜索，对标 PasteSearch 模块）

## Phase 3 — 跨设备同步（对标 iCloud Sync）

- [ ] CloudKit 同步历史与 Pinboard（NSPersistentCloudKitContainer 或手推 CKRecord）
- [ ] iOS/iPadOS 客户端（SwiftUI 共享 Model 层）
- [ ] Paste Keyboard 自定义键盘扩展（iOS 端历史调出）
- [ ] 端到端加密选项（CloudKit encrypted fields）

## Phase 4 — AI 层（对标 2025-2026 的 Paste）✅ 最小闭环完成（v0.3.0）

- [ ] Power Search：截图内文字 OCR 检索（Vision framework，VNRecognizeTextRequest）
- [x] **OpenPaste MCP Server**：本地 MCP 服务器暴露剪贴板历史给 Claude/Cursor
  - [x] JSON-RPC 2.0 over HTTP（127.0.0.1:3789，NWListener）+ Bearer token 鉴权（401 transport 层拒）
  - [x] 工具四件套：`search` / `read_item` / `list_pinboards` / `copy_to_clipboard`（对标 Paste 11 工具）
  - [x] 隐私遮蔽：secret/password 条目经 MCP 搜索时预览自动遮蔽（Paste「内容不出设备」原则）
  - [ ] OAuth 2.1 完整流（对标 Paste：动态客户端注册 + PKCE，先 token 最小闭环）
  - [ ] 写操作工具（create_pinboard/pin_items/delete 两步确认，Paste 同款确认协议）
  - [ ] stdio 代理桥接器（Paste paste-mcp-stdio 同款，兼容不支持 HTTP 的客户端）
- [x] **Intelligent Clipboard 最小闭环**：智能分类 8 类（Paste LanguageModelItemClassifier 同款）
  - [x] 启发式客户端：正则识别 secret/password/code/email/phone/address/number（同步快、零依赖）
  - [x] Apple FoundationModels 客户端（macOS 26+，Paste 原 Prompt 原文，双客户端架构同 Paste）
  - [x] 敏感条目 UI 预览自动遮蔽（••••）+ 卡片角标
  - [ ] 基于 App+时段+共现的「下一个要贴」预测排序
- [ ] Apple Intelligence 写作工具集成（粘贴前校对/改写，需 macOS 15+）

## Phase 5 — 团队协作（对标 Paste for Teams）

- [ ] 共享 Pinboard（CloudKit public database 或自建同步服务）
- [ ] 成员管理 / 权限 / 统一账单（如走商业化）
- [ ] 屏幕共享时隐藏（对标 Paste 2025-10 隐私更新：检测屏幕共享会话自动遮蔽）

## 工程化事项（贯穿）

- [ ] Xcode 工程化（当前为 SPM CLI 构建，够用但缺 Assets/图标管理）
- [ ] App 图标 + 关于页
- [ ] 单元测试（HistoryStore SQLite 层优先）
- [ ] Sandbox 评估：App Store 上架需沙盒；直接粘贴 + 全局快捷键在沙盒下的兼容性方案
- [ ] 公证（Notarization）与 Developer ID 签名

## 已知技术债 / 限制（v0.1）

1. **HistoryStore 非线程安全封装**：内部串行队列保护了写入，但 `ClipItem` 在多端的 Hashable 一致性依赖自增 id，未来同步需改 UUID 主键
2. **Carbon HotKey 与系统冲突**：⇧⌘V 与部分应用冲突，Phase 2 需要快捷键录制 UI
3. **RTF 路径**：`writeToSystemClipboard` 的 RTF 分支目前未真正回写 rtf 数据（存了 asset 但回写只给纯文本），Phase 1.5 修
4. **辅助功能权限**：未授权时 CGEvent 模拟静默失败，需在 UI 上提示引导
5. **changeCount 轮询**：0.4s 轮询是业界通用做法（Paste 同样如此），但可评估 NSPasteboard 深度监听方案省电
