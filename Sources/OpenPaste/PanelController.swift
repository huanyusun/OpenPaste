import AppKit
import SwiftUI

/// Paste 式窗口子类（对应原版 PasteStackWindow）：绕开 AppKit 的 constrainFrameRect，
/// 否则 setFrame 贴底的 frame 会被自动抬高到 Dock 上沿（实测被顶起 91pt）
final class BottomSheetPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect // 原样返回，允许窗口直达屏幕底边、盖住 Dock
    }
}

/// Paste 式底部悬浮卡片条面板（NSPanel，非激活样式，不抢焦点）
@MainActor
final class PanelController {
    private let store: HistoryStore
    private var panel: NSPanel?
    private var viewModel: HistoryViewModel?
    private var isVisible = false
    private var keyMonitor: Any?

    init(store: HistoryStore) {
        self.store = store
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        if panel == nil {
            panel = buildPanel()
            installKeyMonitor()
        }
        positionPanel()
        // nonactivatingPanel 可在不激活应用的情况下成为 key window，
        // 键盘事件仍会到达面板，但不会打断用户当前正在用的应用
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    /// ⌘N 快速粘贴（仅面板可见时由本地键盘监听触发）
    func quickPaste(at index: Int) {
        viewModel?.quickPaste(at: index)
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.frame
        // Paste 原版实测规格（CGWindowList）：全屏宽 × 332pt，贴屏幕底（盖住 Dock，layer 24）
        let width = frame.width
        let height: CGFloat = 332
        panel.setFrame(NSRect(
            x: frame.minX,
            y: frame.minY,
            width: width,
            height: height
        ), display: true)
    }

    // MARK: - 面板内键盘导航（本地监听，面板可见且为 key window 时生效）

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, event.window === self.panel else { return event }

            // 焦点在搜索框等文本视图时：Esc 收起面板，其余放行给文本编辑
            if self.panel?.firstResponder is NSTextView {
                if event.keyCode == 53 { self.hide(); return nil } // Esc
                return event
            }

            switch event.keyCode {
            case 123, 126: // ← ↑
                self.viewModel?.moveSelection(-1); return nil
            case 124, 125: // → ↓
                self.viewModel?.moveSelection(1); return nil
            case 36: // Return：Shift+Return 纯文本粘贴；队列激活时为「粘贴下一条」
                let plain = event.modifierFlags.contains(.shift)
                if !(self.viewModel?.pasteQueue.isEmpty ?? true) && !plain {
                    self.viewModel?.pasteNextFromQueue()
                } else {
                    self.viewModel?.pasteSelected(plainText: plain)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.hide() }
                }
                return nil
            case 48: // Tab：历史 ↔ 最近 Pinboard 快速切换在 View 层处理；这里放行
                return event
            case 49: // 空格：Quick Look 预览
                self.viewModel?.quickLookSelected(); return nil
            case 53: // Esc
                // 有浮层时先关浮层，再收面板
                if self.viewModel?.previewItem != nil { self.viewModel?.previewItem = nil; return nil }
                if self.viewModel?.editingItem != nil { self.viewModel?.editingItem = nil; return nil }
                if self.viewModel?.renamingItem != nil { self.viewModel?.renamingItem = nil; return nil }
                self.hide(); return nil
            case 45: // N：⌘N 加入/移出粘贴队列
                if event.modifierFlags.contains(.command) {
                    guard let idx = self.viewModel?.selectedIndex,
                          let items = self.viewModel?.items, idx < items.count else { return nil }
                    self.viewModel?.toggleQueue(items[idx])
                    return nil
                }
                return event
            case 14: // E：⌘E 编辑
                if event.modifierFlags.contains(.command) {
                    self.viewModel?.editSelected(); return nil
                }
                return event
            case 15: // R：⌘R 重命名
                if event.modifierFlags.contains(.command) {
                    self.viewModel?.renameSelected(); return nil
                }
                return event
            default:
                // ⌘1-9 快速粘贴（面板可见时才拦截，不影响浏览器切标签）
                if event.modifierFlags.contains(.command),
                   let ch = event.charactersIgnoringModifiers,
                   let n = Int(ch), (1...9).contains(n) {
                    self.quickPaste(at: n - 1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.hide() }
                    return nil
                }
                return event
            }
        }
    }

    private func buildPanel() -> NSPanel {
        let panel = BottomSheetPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1680, height: 332),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        // Paste 原版实测 layer 24（status bar 级，压过 Dock）
        panel.level = NSWindow.Level(rawValue: 24)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let vm = HistoryViewModel(store: store)
        viewModel = vm
        panel.contentView = NSHostingView(rootView: HistoryView(viewModel: vm))

        // 点击面板外部自动收起
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            guard self?.isVisible == true, panel?.isVisible == true else { return }
            self?.hide()
        }
        return panel
    }
}
