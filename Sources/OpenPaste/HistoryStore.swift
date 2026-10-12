import Foundation
import AppKit
import SQLite3

/// SQLite 历史存储 + 资产文件管理（图片等二进制落盘，库中只存路径）
final class HistoryStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "openpaste.store", qos: .userInitiated)

    static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenPaste", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static let assetsDir: URL = {
        let dir = appSupportDir.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        let dbPath = Self.appSupportDir.appendingPathComponent("history.sqlite3").path
        sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        migrate()
    }

    deinit { sqlite3_close(db) }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind INTEGER NOT NULL,
            text TEXT,
            asset_path TEXT,
            source_app TEXT,
            source_app_name TEXT,
            source_device TEXT NOT NULL DEFAULT 'Mac',
            board_id INTEGER,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_items_board ON items(board_id);
        CREATE TABLE IF NOT EXISTS boards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            icon TEXT NOT NULL DEFAULT '📌',
            created_at REAL NOT NULL
        );
        """)
        // v0.1.2 迁移：新增 custom_name 列（旧库平滑升级）
        exec("ALTER TABLE items ADD COLUMN custom_name TEXT;")
        // v0.3.0 迁移：CRC32 去重指纹 + 粘贴计数（搜索排序用）+ 智能分类类别
        exec("""
        ALTER TABLE items ADD COLUMN checksum INTEGER;
        ALTER TABLE items ADD COLUMN paste_count INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE items ADD COLUMN category TEXT;
        """)
        // 为存量条目回填 checksum（一次性，NULL 才补）
        backfillChecksums()
        // 首启动种默认 Pinboard（Paste 原版行为：自带素材板，用户可改名/删除）
        seedDefaultBoardsIfEmpty()
    }

    /// boards 表为空时创建默认板，仅启动时调用一次
    private func seedDefaultBoardsIfEmpty() {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM boards", -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) } // 勿手动重复 finalize，会 SIGSEGV
            var count = 0
            if sqlite3_step(stmt) == SQLITE_ROW { count = Int(sqlite3_column_int64(stmt, 0)) }
            guard count == 0 else { return }

            let defaults: [(String, String)] = [("常用", "📌"), ("代码", "💻")]
            for (name, icon) in defaults {
                var ins: OpaquePointer?
                sqlite3_prepare_v2(db, "INSERT INTO boards (name, icon, created_at) VALUES (?, ?, ?)", -1, &ins, nil)
                sqlite3_bind_text(ins, 1, name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(ins, 2, icon, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(ins, 3, Date().timeIntervalSince1970)
                if sqlite3_step(ins) == SQLITE_DONE {
                    NSLog("[OpenPaste] seeded default pinboard: \(name)")
                }
                sqlite3_finalize(ins)
            }
        }
    }

    /// 为旧条目补算 checksum（仅 text/asset 非空的行）
    private func backfillChecksums() {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT id, text, asset_path FROM items WHERE checksum IS NULL", -1, &stmt, nil)
            var updates: [(Int64, UInt32)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let text = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                let asset = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let data: Data
                if let text {
                    data = Data(text.utf8)
                } else if let asset {
                    data = (try? Data(contentsOf: URL(fileURLWithPath: asset))) ?? Data()
                } else {
                    continue
                }
                guard !data.isEmpty else { continue }
                updates.append((id, CRC32.checksum(data)))
            }
            sqlite3_finalize(stmt)
            for (id, crc) in updates {
                exec("UPDATE items SET checksum = \(crc) WHERE id = \(id)")
            }
        }
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - 写入

    /// 保存一条新捕获；与最近一条内容指纹相同时跳过（CRC32 去重，Paste 同款）
    func insert(item: inout NewClipItem) -> Int64? {
        queue.sync {
            // 计算内容指纹（文本取 UTF-8，二进制取文件内容）
            let data: Data
            if let text = item.text { data = Data(text.utf8) }
            else if let path = item.assetPath { data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data() }
            else { data = Data() }
            let crc = CRC32.checksum(data)
            item.checksum = crc

            // 去重：与最近一条同类型且指纹相同 → 只刷新时间不重复入库
            if let last = lastItemRaw(), last.kind == item.kind.rawValue, last.checksum == Int64(crc) {
                exec("UPDATE items SET created_at = \(Date().timeIntervalSince1970) WHERE id = \(last.id)")
                return nil
            }
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                INSERT INTO items (kind, text, asset_path, source_app, source_app_name, created_at, checksum, category)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, -1, &stmt, nil)
            sqlite3_bind_int(stmt, 1, item.kind.rawValue)
            bindText(stmt, 2, item.text)
            bindText(stmt, 3, item.assetPath)
            bindText(stmt, 4, item.sourceApp)
            bindText(stmt, 5, item.sourceAppName)
            sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 7, Int64(crc))
            bindText(stmt, 8, item.category?.rawValue)
            let ok = sqlite3_step(stmt) == SQLITE_DONE
            let rowid = ok ? sqlite3_last_insert_rowid(db) : nil
            sqlite3_finalize(stmt)
            return rowid
        }
    }

    private struct LastRaw { let id: Int64; let kind: Int32; let checksum: Int64? }

    private func lastItemRaw() -> LastRaw? {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT id, kind, checksum FROM items ORDER BY id DESC LIMIT 1", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return LastRaw(
            id: sqlite3_column_int64(stmt, 0),
            kind: sqlite3_column_int(stmt, 1),
            checksum: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : Int64(sqlite3_column_int64(stmt, 2))
        )
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ text: String?) {
        if let text { sqlite3_bind_text(stmt, idx, text, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    // MARK: - 查询

    /// 拉取历史（boardID 为 nil 取未固定的历史流；search 非空时 LIKE 取候选集 + 候选评分排序）
    func fetchHistory(boardID: Int64? = nil, search: String? = nil, limit: Int = 200) -> [ClipItem] {
        queue.sync {
            var sql = "SELECT id, kind, text, asset_path, source_app, source_app_name, source_device, board_id, custom_name, created_at, paste_count, category FROM items"
            var conditions: [String] = []
            if let boardID { conditions.append("board_id = \(boardID)") } else { conditions.append("board_id IS NULL") }
            if let search, !search.isEmpty {
                let esc = search.replacingOccurrences(of: "'", with: "''")
                conditions.append("(text LIKE '%\(esc)%' OR custom_name LIKE '%\(esc)%' OR source_app_name LIKE '%\(esc)%')")
            }
            sql += " WHERE " + conditions.joined(separator: " AND ")
            sql += " ORDER BY created_at DESC LIMIT \(max(limit * 3, 300))" // 候选集扩大 3 倍供评分

            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            var candidates: [(item: ClipItem, score: Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let item = ClipItem(
                    id: sqlite3_column_int64(stmt, 0),
                    kind: ItemKind(rawValue: sqlite3_column_int(stmt, 1)) ?? .text,
                    text: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                    assetPath: sqlite3_column_text(stmt, 3).map { String(cString: $0) },
                    sourceApp: sqlite3_column_text(stmt, 4).map { String(cString: $0) },
                    sourceAppName: sqlite3_column_text(stmt, 5).map { String(cString: $0) },
                    sourceDevice: sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "Mac",
                    pinnedBoardID: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7),
                    customName: sqlite3_column_text(stmt, 8).map { String(cString: $0) },
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
                    pasteCount: Int(sqlite3_column_int64(stmt, 10)),
                    category: ItemCategory(rawValue: sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? "")
                )
                candidates.append((item, Self.score(item, query: search)))
            }
            // finalize 由 defer 统一处理（勿手动重复 finalize，会 SIGSEGV）

            // 无搜索 = 纯时间序；有搜索 = 候选评分排序（Paste candidate{score:Double} 同思路）
            if let search, !search.isEmpty {
                return candidates.sorted { $0.score > $1.score }.prefix(limit).map { $0.item }
            }
            return candidates.prefix(limit).map { $0.item }
        }
    }

    /// 候选评分：匹配位置（前缀 > 词首 > 正文）+ log 频次 + 时间衰减（72h 半衰）
    static func score(_ item: ClipItem, query: String?) -> Double {
        var s = 0.0
        if let q = query?.lowercased(), !q.isEmpty {
            let hay = (item.customName ?? item.text ?? "").lowercased()
            if hay.hasPrefix(q) {
                s += 60
            } else if let r = hay.range(of: q),
                      r.lowerBound == hay.startIndex || hay[hay.index(before: r.lowerBound)] == " " {
                s += 35
            } else if hay.contains(q) {
                s += 15
            }
        }
        s += 12 * log2(1 + Double(item.pasteCount))
        let age = Date().timeIntervalSince(item.createdAt)
        s *= exp(-age / (72 * 3600))
        return s
    }

    func boards() -> [PinBoard] {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT id, name, icon, created_at FROM boards ORDER BY created_at", -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            var result: [PinBoard] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(PinBoard(
                    id: sqlite3_column_int64(stmt, 0),
                    name: sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
                    icon: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "📌",
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                ))
            }
            return result
        }
    }

    @discardableResult
    func createBoard(name: String, icon: String) -> Int64? {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO boards (name, icon, created_at) VALUES (?, ?, ?)", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, icon, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            let ok = sqlite3_step(stmt) == SQLITE_DONE
            let rowid = ok ? sqlite3_last_insert_rowid(db) : nil
            sqlite3_finalize(stmt)
            return rowid
        }
    }

    /// 重命名 Pinboard
    func renameBoard(id: Int64, name: String) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "UPDATE boards SET name = ? WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// 删除 Pinboard：板上条目解绑回历史流（不删数据，Paste 同款语义）
    func deleteBoard(id: Int64) {
        queue.sync {
            exec("UPDATE items SET board_id = NULL WHERE board_id = \(id)")
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM boards WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func pin(itemID: Int64, to boardID: Int64?) {
        queue.sync {
            var stmt: OpaquePointer?
            if let boardID {
                sqlite3_prepare_v2(db, "UPDATE items SET board_id = ? WHERE id = ?", -1, &stmt, nil)
                sqlite3_bind_int64(stmt, 1, boardID)
            } else {
                sqlite3_prepare_v2(db, "UPDATE items SET board_id = NULL WHERE id = ?", -1, &stmt, nil)
            }
            sqlite3_bind_int64(stmt, 2, itemID)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// 移动到历史最前（重新复制旧条目的效果）
    func touch(itemID: Int64) {
        queue.sync {
            exec("UPDATE items SET created_at = \(Date().timeIntervalSince1970) WHERE id = \(itemID)")
        }
    }

    /// 重命名条目（nil/空串 = 清除自定义名）
    func rename(itemID: Int64, name: String?) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "UPDATE items SET custom_name = ? WHERE id = ?", -1, &stmt, nil)
            if let name, !name.isEmpty { sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT) }
            else { sqlite3_bind_null(stmt, 1) }
            sqlite3_bind_int64(stmt, 2, itemID)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// 更新智能分类类别（LLM 异步分类回写）
    func updateCategory(itemID: Int64, category: ItemCategory) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "UPDATE items SET category = ? WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, category.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, itemID)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// 取单条（MCP read_item 用；历史流 + Pinboard 全范围）
    func item(id: Int64) -> ClipItem? {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                SELECT id, kind, text, asset_path, source_app, source_app_name, source_device, board_id, custom_name, created_at, paste_count, category
                FROM items WHERE id = ?
                """, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, id)
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return ClipItem(
                id: sqlite3_column_int64(stmt, 0),
                kind: ItemKind(rawValue: sqlite3_column_int(stmt, 1)) ?? .text,
                text: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                assetPath: sqlite3_column_text(stmt, 3).map { String(cString: $0) },
                sourceApp: sqlite3_column_text(stmt, 4).map { String(cString: $0) },
                sourceAppName: sqlite3_column_text(stmt, 5).map { String(cString: $0) },
                sourceDevice: sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "Mac",
                pinnedBoardID: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7),
                customName: sqlite3_column_text(stmt, 8).map { String(cString: $0) },
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
                pasteCount: Int(sqlite3_column_int64(stmt, 10)),
                category: ItemCategory(rawValue: sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? "")
            )
        }
    }

    /// 粘贴计数 +1（搜索排序的频次信号）
    func incrementPasteCount(itemID: Int64) {
        queue.sync {
            exec("UPDATE items SET paste_count = paste_count + 1 WHERE id = \(itemID)")
        }
    }

    /// 编辑文本内容（仅文本类条目）
    func updateText(itemID: Int64, newText: String) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "UPDATE items SET text = ? WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, newText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, itemID)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func delete(itemID: Int64) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM items WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, itemID)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func clearHistory(pinnedToo: Bool = false) {
        queue.sync {
            exec(pinnedToo ? "DELETE FROM items" : "DELETE FROM items WHERE board_id IS NULL")
        }
    }

    /// 按保留天数清理（0 = 不限制）
    func prune(olderThanDays days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        queue.sync {
            exec("DELETE FROM items WHERE board_id IS NULL AND created_at < \(cutoff)")
        }
    }

    // MARK: - 系统剪贴板写入

    /// 把条目写回系统剪贴板（paste=true 时同时模拟粘贴到前台应用）
    func writeToSystemClipboard(_ item: ClipItem, pasteIntoFrontmost: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text, .url:
            pb.setString(item.text ?? "", forType: .string)
        case .rtf:
            // 优先回写 RTF 原始数据（保留格式），纯文本兜底
            if let path = item.assetPath,
               let rtfData = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                pb.setData(rtfData, forType: .rtf)
            }
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            if let path = item.assetPath, let img = NSImage(contentsOfFile: path) {
                pb.writeObjects([img])
            }
        case .file:
            let files = item.decodeFilePaths()
            if !files.isEmpty {
                pb.writeObjects(files.map { NSURL(fileURLWithPath: $0) })
            }
        }
        if pasteIntoFrontmost {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                SimulatedKeystrokes.pasteCommandV()
            }
        }
    }
}

/// 新条目（入库前的中间结构）
struct NewClipItem {
    var kind: ItemKind
    var text: String?
    var assetPath: String?
    var sourceApp: String?
    var sourceAppName: String?
    var checksum: UInt32?
    var category: ItemCategory?
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
