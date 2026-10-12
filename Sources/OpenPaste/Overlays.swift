import SwiftUI
import AppKit

// MARK: - Quick Look 预览浮层（空格键）

struct QuickLookOverlay: View {
    let item: ClipItem
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .onTapGesture { onClose() }
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: iconName)
                    Text(item.previewText.isEmpty ? "预览" : String(item.previewText.prefix(40)))
                        .lineLimit(1)
                    Spacer()
                    Button { onClose() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(12)
                Divider()
                content
                    .frame(maxWidth: 640, maxHeight: 420)
            }
            .frame(width: 660)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 24)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            if let path = item.assetPath, let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            } else {
                Text("图片无法加载").foregroundStyle(.secondary).padding()
            }
        case .text, .url, .rtf:
            ScrollView {
                Text(item.text ?? "")
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
        case .file:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.decodeFilePaths(), id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill").foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text((path as NSString).lastPathComponent).font(.callout.weight(.medium))
                            Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer()
            }
            .padding(16)
        }
    }

    private var iconName: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .rtf: return "doc.richtext"
        }
    }
}

// MARK: - 编辑浮层（⌘E，仅文本类）

struct EditOverlay: View {
    let item: ClipItem
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).onTapGesture { onCancel() }
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "pencil.line")
                    Text("编辑条目").font(.headline)
                    Spacer()
                }
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .focused($focused)
                    .frame(width: 620, height: 260)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary)
                    )
                HStack {
                    Text("⌘Return 保存 · Esc 取消")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                    Button("保存") { onSave(text) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(18)
            .frame(width: 660)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 24)
        }
        .onAppear {
            text = item.text ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onExitCommand { onCancel() } // Esc
    }
}

// MARK: - 重命名浮层（⌘R）

struct RenameOverlay: View {
    let item: ClipItem
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).onTapGesture { onCancel() }
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "tag")
                    Text("重命名条目").font(.headline)
                    Spacer()
                }
                TextField("输入一个好认的名字（留空清除）", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { onSave(name) }
                HStack {
                    Spacer()
                    Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                    Button("保存") { onSave(name) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(18)
            .frame(width: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 24)
        }
        .onAppear {
            name = item.customName ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onExitCommand { onCancel() }
    }
}
