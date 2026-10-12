import Foundation
import SwiftUI
import AppKit

/// 历史流视图模型：驱动卡片流、搜索、Pinboard、粘贴动作
@MainActor
final class HistoryViewModel: ObservableObject {
    enum Tab: Hashable { case history, board(Int64) }

    @Published var items: [ClipItem] = []
    @Published var boards: [PinBoard] = []
    @Published var searchText = "" { didSet { reload() } }
    @Published var currentTab: Tab = .history { didSet { reload() } }
    @Published var selectedIndex: Int = 0
    @Published var statusHint: String?
    /// Paste Stack 粘贴队列（按入队顺序依次粘贴）
    @Published var pasteQueue: [ClipItem] = []
    /// 预览/编辑/重命名浮层状态
    @Published var previewItem: ClipItem?
    @Published var editingItem: ClipItem?
    @Published var renamingItem: ClipItem?

    private var store: HistoryStore
    private var monitor: ClipboardMonitor?
    private var observer: NSObjectProtocol?

    init(store: HistoryStore) {
        self.store = store
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: .openPasteHistoryChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.reload() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func attach(monitor: ClipboardMonitor) { self.monitor = monitor }

    func reload() {
        switch currentTab {
        case .history:
            items = store.fetchHistory(boardID: nil, search: searchOrEmpty)
        case .board(let id):
            items = store.fetchHistory(boardID: id, search: searchOrEmpty)
        }
        boards = store.boards()
        if selectedIndex >= items.count { selectedIndex = max(0, items.count - 1) }
    }

    private var searchOrEmpty: String? {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : searchText
    }

    // MARK: - 动作

    func paste(_ item: ClipItem, plainText: Bool = false) {
        if plainText {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(item.text ?? "", forType: .string)
        } else {
            store.writeToSystemClipboard(item, pasteIntoFrontmost: true)
        }
        if currentTab == .history {
            store.touch(itemID: item.id)
            store.incrementPasteCount(itemID: item.id) // 频次信号：搜索排序用
        }
        statusHint = plainText ? "已按纯文本粘贴" : "已粘贴"
        // 队列激活时不自动清空提示（用户可能继续逐条粘贴）
        if pasteQueue.isEmpty { hideSoon() }
    }

    func quickPaste(at index: Int) {
        guard index < items.count else { return }
        paste(items[index])
    }

    /// 粘贴当前选中卡片（键盘 Return 触发）
    func pasteSelected(plainText: Bool = false) {
        guard selectedIndex < items.count else { return }
        paste(items[selectedIndex], plainText: plainText)
    }

    /// 只复制回剪贴板，不触发粘贴
    func copyOnly(_ item: ClipItem) {
        store.writeToSystemClipboard(item, pasteIntoFrontmost: false)
        statusHint = "已复制到剪贴板"
    }

    func pin(_ item: ClipItem, to boardID: Int64?) {
        store.pin(itemID: item.id, to: boardID)
        reload()
    }

    func delete(_ item: ClipItem) {
        store.delete(itemID: item.id)
        reload()
    }

    func createBoard(name: String) {
        _ = store.createBoard(name: name, icon: "📌")
        reload()
    }

    /// 删除 Pinboard：板上条目解绑回历史流。正在看该板时回退到历史页签
    func deleteBoard(_ board: PinBoard) {
        store.deleteBoard(id: board.id)
        if case .board(let id) = currentTab, id == board.id {
            currentTab = .history
        } else {
            reload()
        }
    }

    /// 重命名 Pinboard
    func renameBoard(_ board: PinBoard, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.renameBoard(id: board.id, name: trimmed)
        reload()
    }

    func clearHistory() {
        store.clearHistory()
        reload()
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(0, selectedIndex + delta), items.count - 1)
    }

    // MARK: - Paste Stack 队列

    /// 加入/移出队列（队列激活时面板保持打开，依序粘贴）
    func toggleQueue(_ item: ClipItem) {
        if let idx = pasteQueue.firstIndex(where: { $0.id == item.id }) {
            pasteQueue.remove(at: idx)
        } else {
            pasteQueue.append(item)
        }
        statusHint = pasteQueue.isEmpty ? "队列已清空" : "队列中 \(pasteQueue.count) 条，逐条粘贴时用「粘贴下一条」"
    }

    /// 粘贴队首并弹出；队列空了自动恢复自动收起
    @discardableResult
    func pasteNextFromQueue() -> Bool {
        guard !pasteQueue.isEmpty else { return false }
        let item = pasteQueue.removeFirst()
        store.writeToSystemClipboard(item, pasteIntoFrontmost: true)
        store.touch(itemID: item.id)
        store.incrementPasteCount(itemID: item.id)
        statusHint = pasteQueue.isEmpty ? "队列完成 ✓" : "已粘贴 1 条，剩 \(pasteQueue.count) 条"
        reload()
        return true
    }

    func clearQueue() {
        pasteQueue.removeAll()
        statusHint = "队列已清空"
    }

    // MARK: - 预览 / 编辑 / 重命名

    func quickLookSelected() {
        guard selectedIndex < items.count else { return }
        previewItem = items[selectedIndex]
    }

    func editSelected() {
        guard selectedIndex < items.count, [.text, .url, .rtf].contains(items[selectedIndex].kind) else { return }
        editingItem = items[selectedIndex]
    }

    func renameSelected() {
        guard selectedIndex < items.count else { return }
        renamingItem = items[selectedIndex]
    }

    func saveEditing(text: String) {
        guard let item = editingItem else { return }
        store.updateText(itemID: item.id, newText: text)
        // 内容变了，重新分类
        ClassificationCoordinator.shared.classifyAndStore(itemID: item.id, text: text)
        editingItem = nil
        reload()
        statusHint = "已保存修改"
    }

    func saveRenaming(name: String) {
        guard let item = renamingItem else { return }
        store.rename(itemID: item.id, name: name.isEmpty ? nil : name)
        renamingItem = nil
        reload()
        statusHint = name.isEmpty ? "已清除自定义名称" : "已重命名"
    }

    private func hideSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.statusHint = nil
        }
    }
}
