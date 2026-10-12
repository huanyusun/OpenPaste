import SwiftUI
import AppKit

/// 底部卡片流主界面：搜索栏 + Pinboard 页签 + 横向卡片时间线 + 队列条
struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    /// 面板刚打开时自动聚焦搜索框（由 PanelController 控制）
    var focusSearchOnAppear = true

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            headerBar
            if !viewModel.pasteQueue.isEmpty { queueBar }
            cardsStrip
        }
        .padding(.top, 8)
        .background(
            // Paste 实测（浅色主题像素取证）：顶栏 #F2F2F2，内容区 #F2F2F2→#FCFCFC 垂直微渐变，不透明非毛玻璃
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor),
                         Color(red: 0.949, green: 0.949, blue: 0.949),
                         Color(red: 0.972, green: 0.972, blue: 0.972)],
                startPoint: .top, endPoint: .bottom
            )
            .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.12))
            .opacity(0.98)
        )
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { statusHintOverlay }
        .overlay { overlays } // 预览/编辑/重命名浮层
        .onAppear {
            if focusSearchOnAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
            }
        }
        .preferredColorScheme(.light) // Paste 面板恒为浅色主题（夜间模式下面板也是浅色）
    }

    // MARK: 顶部：搜索 + 页签 + 操作按钮

    private var headerBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索剪贴板历史…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // Paste 实测：搜索控件直接放在顶栏灰底上，无独立白底/深底框
            .background(Color.primary.opacity(0.001), in: RoundedRectangle(cornerRadius: 8))
            .frame(width: 380) // Paste 原版：搜索框居中定宽

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    tabButton("历史", icon: "clock", tab: .history)
                    ForEach(viewModel.boards) { board in
                        tabButton("\(board.icon) \(board.name)", icon: nil, tab: .board(board.id))
                            .contextMenu {
                                Button("重命名") { promptRenameBoard(board) }
                                Divider()
                                Button("删除 Pinboard…", role: .destructive) { confirmDeleteBoard(board) }
                            }
                    }
                    Button {
                        promptCreateBoard()
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("新建 Pinboard")
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: 560)

            Menu {
                Button("重命名 (⌘R)") { viewModel.renameSelected() }
                Button("编辑内容 (⌘E)") { viewModel.editSelected() }
                Button("预览 (空格)") { viewModel.quickLookSelected() }
                Divider()
                Button("按纯文本粘贴 (⇧Return)") {
                    viewModel.pasteSelected(plainText: true)
                }
                Button("清空历史（不删固定板）", role: .destructive) { viewModel.clearHistory() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.trailing, 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    // MARK: 队列条（Paste Stack）

    private var queueBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.number")
                .foregroundStyle(.orange)
            Text("队列 \(viewModel.pasteQueue.count) 条")
                .font(.callout.weight(.semibold))
            ForEach(Array(viewModel.pasteQueue.prefix(4).enumerated()), id: \.element.id) { idx, item in
                Text("\(idx + 1). \(item.previewText.isEmpty ? "…" : String(item.previewText.prefix(14)))")
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quinary, in: Capsule())
            }
            if viewModel.pasteQueue.count > 4 {
                Text("…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.pasteNextFromQueue()
            } label: {
                Label("粘贴下一条", systemImage: "arrow.down.to.line.compact")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                viewModel.clearQueue()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("清空队列")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.10))
    }

    // MARK: 状态提示浮层

    @ViewBuilder
    private var statusHintOverlay: some View {
        if let hint = viewModel.statusHint {
            Text(hint)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.95), in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: viewModel.statusHint)
        }
    }

    // MARK: 浮层（预览/编辑/重命名）

    @ViewBuilder
    private var overlays: some View {
        if let item = viewModel.previewItem {
            QuickLookOverlay(item: item) { viewModel.previewItem = nil }
        }
        if let item = viewModel.editingItem {
            EditOverlay(item: item) { newText in
                viewModel.saveEditing(text: newText)
            } onCancel: {
                viewModel.editingItem = nil
            }
        }
        if let item = viewModel.renamingItem {
            RenameOverlay(item: item) { name in
                viewModel.saveRenaming(name: name)
            } onCancel: {
                viewModel.renamingItem = nil
            }
        }
    }

    private func tabButton(_ title: String, icon: String?, tab: HistoryViewModel.Tab) -> some View {
        Button {
            viewModel.currentTab = tab
        } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 12, weight: viewModel.currentTab == tab ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                viewModel.currentTab == tab ? Color.accentColor.opacity(0.22) : Color.clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(viewModel.currentTab == tab ? .primary : .secondary)
    }

    // MARK: Pinboard 管理弹窗（新建/重命名/删除确认）

    /// 通用单行文本输入弹窗（NSApp modal，面板为 nonactivating panel 时也能正常前置）
    @discardableResult
    private func textPrompt(title: String, placeholder: String = "", defaultValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = defaultValue
        input.placeholderString = placeholder
        alert.accessoryView = input
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = input.stringValue.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private func promptCreateBoard() {
        if let name = textPrompt(title: "新建 Pinboard", placeholder: "板名称") {
            viewModel.createBoard(name: name)
        }
    }

    private func promptRenameBoard(_ board: PinBoard) {
        if let name = textPrompt(title: "重命名 Pinboard", defaultValue: board.name) {
            viewModel.renameBoard(board, to: name)
        }
    }

    private func confirmDeleteBoard(_ board: PinBoard) {
        let alert = NSAlert()
        alert.messageText = "删除「\(board.name)」？"
        alert.informativeText = "板上的条目不会被删除，将回到历史流中。此操作不可撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons.last?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.deleteBoard(board)
        }
    }

    // MARK: 卡片流

    private var cardsStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    if viewModel.items.isEmpty {
                        emptyView
                    } else {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            ClipCardView(
                                item: item,
                                index: index,
                                isSelected: index == viewModel.selectedIndex,
                                isInQueue: viewModel.pasteQueue.contains(where: { $0.id == item.id }),
                                boards: viewModel.boards,
                                onPaste: { viewModel.paste(item) },
                                onPastePlain: { viewModel.paste(item, plainText: true) },
                                onCopy: { viewModel.copyOnly(item) },
                                onPin: { boardID in viewModel.pin(item, to: boardID) },
                                onQueue: { viewModel.toggleQueue(item) },
                                onPreview: { viewModel.previewItem = item },
                                onEdit: { viewModel.editingItem = item },
                                onRename: { viewModel.renamingItem = item },
                                onDelete: { viewModel.delete(item) }
                            )
                            .id(item.id)
                            .onHover { hovering in
                                if hovering { viewModel.selectedIndex = index }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                guard newIndex < viewModel.items.count else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(viewModel.items[newIndex].id, anchor: .center)
                }
            }
        }
    }

    private var emptyView: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "doc.on.doc").font(.title2).foregroundStyle(.tertiary)
                Text(viewModel.currentTab == .history ? "复制任意内容后自动出现在这里" : "把历史条目右键固定到此板")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

/// 单张剪贴板卡片
struct ClipCardView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    var isInQueue: Bool = false
    let boards: [PinBoard]
    let onPaste: () -> Void
    let onPastePlain: () -> Void
    let onCopy: () -> Void
    let onPin: (Int64?) -> Void
    let onQueue: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 4))
                }
                kindIcon
                if let badge = item.category?.badge, !item.previewText.isEmpty {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(item.category?.isSensitive == true ? Color.orange : Color.secondary)
                        .help(item.category?.displayName ?? "")
                }
                if isInQueue {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            contentPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 4) {
                Image(systemName: "app.dashed")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(item.sourceAppName ?? "未知来源")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 300, height: 236) // Paste 原版实测：大预览卡，几乎占满面板高度
        .background(
            RoundedRectangle(cornerRadius: 14)
                // Paste 实测：卡片为不透明纯白（浅色主题），选中态用细描边 + 极轻阴影
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isInQueue ? Color.orange : (isSelected ? Color.accentColor.opacity(0.55) : Color.clear),
                            lineWidth: isInQueue ? 2 : 1
                        )
                )
                .shadow(color: .black.opacity(isSelected ? 0.08 : 0.05), radius: 3, y: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(count: 2) { onPaste() }
        .contextMenu {
            Button("粘贴") { onPaste() }.keyboardShortcut(.return, modifiers: [])
            Button("按纯文本粘贴") { onPastePlain() }.keyboardShortcut(.return, modifiers: .shift)
            Button("仅复制到剪贴板") { onCopy() }
            Divider()
            Button(isInQueue ? "移出粘贴队列" : "加入粘贴队列") { onQueue() }
            Divider()
            Button("预览 (空格)") { onPreview() }
            Button("编辑 (⌘E)") { onEdit() }
            Button("重命名 (⌘R)") { onRename() }
            Divider()
            Menu("固定到 Pinboard") {
                ForEach(boards) { board in
                    Button("\(board.icon) \(board.name)") { onPin(board.id) }
                }
                Divider()
                Button("取消固定") { onPin(nil) }
            }
            Button("删除", role: .destructive) { onDelete() }
        }
    }

    private var kindIcon: some View {
        let name: String
        switch item.kind {
        case .text: name = "text.alignleft"
        case .image: name = "photo"
        case .file: name = "doc"
        case .url: name = "link"
        case .rtf: name = "doc.richtext"
        }
        return Image(systemName: name).font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.kind {
        case .text, .url, .rtf:
            VStack(alignment: .leading, spacing: 4) {
                if let customName = item.customName, !customName.isEmpty {
                    Text(customName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text(rawPreview)
                    .font(item.kind == .url ? .callout : .system(size: 12))
                    .foregroundStyle(item.kind == .url ? Color.accentColor : .secondary)
                    .lineLimit(item.customName == nil ? 9 : 6)
                    .truncationMode(.tail)
            }
        case .image:
            if let path = item.assetPath, let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text("图片已丢失").foregroundStyle(.tertiary)
            }
        case .file:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(item.decodeFilePaths().prefix(6), id: \.self) { path in
                    HStack(spacing: 4) {
                        Image(systemName: "doc").font(.caption2)
                        Text((path as NSString).lastPathComponent)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }
                if item.decodeFilePaths().count > 6 {
                    Text("…共 \(item.decodeFilePaths().count) 个").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var rawPreview: String {
        (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }
}

/// （已移除深色毛玻璃背景：Paste 面板实测为不透明浅色渐变，见 HistoryView.body）
