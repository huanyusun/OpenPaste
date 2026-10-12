import Foundation
import AppKit
import CoreGraphics

/// 剪贴板监听：轮询 NSPasteboard.changeCount，解析新增内容并入库
final class ClipboardMonitor {
    private let store: HistoryStore
    private var timer: Timer?
    var isPaused = false
    private var lastChangeCount = NSPasteboard.general.changeCount

    /// 排除的应用（密码管理器等）bundle id 黑名单
    var excludedApps: Set<String> = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.agilebits.onepassword-osx",
    ]

    init(store: HistoryStore) {
        self.store = store
    }

    func start(interval: TimeInterval = 0.4) {
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func check() {
        guard !isPaused else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        capture(from: pb)
    }

    private func capture(from pb: NSPasteboard) {
        // 来源应用
        let frontApp = NSWorkspace.shared.frontmostApplication
        if let bundleID = frontApp?.bundleIdentifier, excludedApps.contains(bundleID) { return }

        var newItem = NewClipItem(
            kind: .text, text: nil, assetPath: nil,
            sourceApp: frontApp?.bundleIdentifier,
            sourceAppName: frontApp?.localizedName
        )

        // 1) 文件 URL
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            newItem.kind = .file
            if let data = try? JSONEncoder().encode(urls.map { $0.path }) {
                newItem.text = String(data: data, encoding: .utf8)
            }
        }
        // 2) 图片
        else if let image = NSImage(pasteboard: pb) {
            newItem.kind = .image
            let fileName = "img_\(Int(Date().timeIntervalSince1970 * 1000)).png"
            let dest = HistoryStore.assetsDir.appendingPathComponent(fileName)
            if savePNG(image, to: dest) {
                newItem.assetPath = dest.path
            } else {
                return
            }
        }
        // 3) RTF 富文本
        else if let rtfData = pb.data(forType: .rtf),
                let attr = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            newItem.kind = .rtf
            newItem.text = attr.string
            let fileName = "rtf_\(Int(Date().timeIntervalSince1970 * 1000)).rtf"
            let dest = HistoryStore.assetsDir.appendingPathComponent(fileName)
            try? rtfData.write(to: dest)
            newItem.assetPath = dest.path
        }
        // 4) 纯文本 / URL 字符串
        else if let str = pb.string(forType: .string), !str.isEmpty {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 8192 && (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) && !trimmed.contains("\n") {
                newItem.kind = .url
            } else {
                newItem.kind = .text
            }
            newItem.text = str
        } else {
            return // 不支持/空内容
        }

        if let rowid = store.insert(item: &newItem) {
            // 智能分类：启发式同步写入，LLM 可用时异步复核（不阻塞捕获）
            // Timer 在主线程 RunLoop 触发，MainActor hop 无实际切换成本
            let text = newItem.text
            Task { @MainActor in
                ClassificationCoordinator.shared.classifyAndStore(itemID: rowid, text: text)
            }
        }
        NotificationCenter.default.post(name: .openPasteHistoryChanged, object: nil)
    }

    private func savePNG(_ image: NSImage, to url: URL) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        try? FileManager.default.removeItem(at: url)
        do {
            try png.write(to: url)
            return true
        } catch { return false }
    }
}

extension Notification.Name {
    static let openPasteHistoryChanged = Notification.Name("openPasteHistoryChanged")
}

/// 模拟 ⌘V 按键（需要辅助功能权限）
enum SimulatedKeystrokes {
    static func pasteCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) // V
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }
}
