import AppKit
import SwiftUI

/// MCP 业务回调：走同一份 HistoryStore（串行队列自保护），UI 无关
final class AppMCPHandler: MCPRequestHandler {
    private let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store
    }

    func search(query: String) -> [ClipItem] {
        store.fetchHistory(boardID: nil, search: query.isEmpty ? nil : query, limit: 20)
    }

    func item(id: Int64) -> ClipItem? {
        store.item(id: id)
    }

    func boards() -> [PinBoard] {
        store.boards()
    }

    func copyToClipboard(_ item: ClipItem) -> Bool {
        store.writeToSystemClipboard(item, pasteIntoFrontmost: false)
        return true
    }
}

/// 应用生命周期：菜单栏、全局快捷键、监听服务、面板管理
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipboardMonitor: ClipboardMonitor!
    private var historyStore: HistoryStore!
    private var panelController: PanelController!
    private var hotKeyCenter: HotKeyCenter!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var mcpServer: MCPServer?
    private var mcpHandler: AppMCPHandler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // 菜单栏应用，不占 Dock

        historyStore = HistoryStore()
        ClassificationCoordinator.shared.attach(store: historyStore)
        clipboardMonitor = ClipboardMonitor(store: historyStore)
        panelController = PanelController(store: historyStore)

        clipboardMonitor.start()
        setupMenuBar()
        startMCPServerIfNeeded()

        hotKeyCenter = HotKeyCenter()
        hotKeyCenter.register(handler: { [weak self] in
            self?.panelController.toggle()
        })
        // 注：⌘1-9 快速粘贴不再注册为全局热键（会劫持浏览器切标签等系统行为），
        // 改为面板可见时的本地键盘监听，见 PanelController.installKeyMonitor()

        // URL scheme: openpaste://toggle 等（供自动化验证/外部集成；合成键盘事件触不到 RegisterEventHotKey）
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlStr = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
        guard let url = URLComponents(string: urlStr) else { return }
        switch url.host ?? url.path {
        case "toggle", "show":
            panelController.toggle()
        case "hide":
            panelController.hide()
        default:
            NSLog("[OpenPaste] unknown url action: \(urlStr)")
        }
    }

    /// MCP 服务器：偏好开关（默认开），token 持久化在 Keychain 级UserDefaults（本机 loopback 风险可控）
    private func startMCPServerIfNeeded() {
        guard UserDefaults.standard.object(forKey: "mcpEnabled") == nil
            || UserDefaults.standard.bool(forKey: "mcpEnabled") else { return }
        let token = UserDefaults.standard.string(forKey: "mcpToken") ?? Self.generateToken()
        UserDefaults.standard.set(token, forKey: "mcpToken")
        let handler = AppMCPHandler(store: historyStore)
        let server = MCPServer(port: 3789, token: token)
        server.handler = handler
        mcpHandler = handler
        mcpServer = server
        do {
            try server.start()
        } catch {
            NSLog("[OpenPasteMCP] start failed: \(error)")
        }
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: "OpenPaste")

        let menu = NSMenu()
        menu.addItem(withTitle: "打开剪贴板历史  ⇧⌘V", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "暂停捕获", action: #selector(toggleCapture), keyEquivalent: "").representedObject = "toggle"
        menu.addItem(.separator())
        menu.addItem(withTitle: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 OpenPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func togglePanel() { panelController.toggle() }

    @objc private func toggleCapture(_ sender: NSMenuItem) {
        clipboardMonitor.isPaused.toggle()
        sender.title = clipboardMonitor.isPaused ? "恢复捕获" : "暂停捕获"
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.titlebarAppearsTransparent = true
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.representedObject as? String == "toggle" {
            item.title = clipboardMonitor?.isPaused == true ? "恢复捕获" : "暂停捕获"
        }
    }
}
