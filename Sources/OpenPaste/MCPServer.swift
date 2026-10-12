import Foundation
import Network

// MARK: - OpenPaste MCP Server（Phase 4 最小闭环，对标 Paste MCP 11 工具的前 4 件套）
//
// 架构（Paste 逆向结论）：
// - 本地 HTTP + JSON-RPC 2.0（MCP 规范协议层）
// - Bearer token 鉴权（Paste 是完整 OAuth 2.1，最小闭环先 token；401 在 transport 层拒）
// - 4 工具：search / read_item / list_pinboards / copy_to_clipboard
// - 删除类工具（Paste 有两步确认）暂不开放，待后续加确认协议

/// MCP 工具定义（JSON Schema 形态，tools/list 返回）
struct MCPToolDef {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    var jsonObject: [String: Any] {
        ["name": name, "description": description, "inputSchema": inputSchema]
    }
}

/// 非 MainActor 的 HTTP 服务器骨架；业务回调查询在主队列执行（HistoryStore 串行队列自保护）
final class MCPServer {
    private var listener: NWListener?
    private let token: String
    private let port: UInt16
    /// 业务处理回调（由 AppDelegate 注入，保证与 UI/DB 一致）
    var handler: MCPRequestHandler?
    private let queue = DispatchQueue(label: "openpaste.mcp.server")

    /// 工具调用错误（Result.Failure 需遵循 Error）
    struct ToolError: Error { let message: String }

    init(port: UInt16 = 3789, token: String) {
        self.port = port
        self.token = token
    }

    var url: String { "http://127.0.0.1:\(port)/mcp" }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // 安全边界：只绑 loopback（Paste 的 MCP 服务器同样是本机语义）
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                NSLog("[OpenPasteMCP] listener failed: \(err)")
                self?.listener = nil
            }
        }
        listener.start(queue: queue)
        NSLog("[OpenPasteMCP] listening on \(self.url)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - 连接处理

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: buf[..<range.lowerBound], encoding: .utf8) ?? ""
                let bodyStart = buf.index(range.upperBound, offsetBy: 0)
                var body = Data(buf[bodyStart...])
                // Content-Length 解析：不够就继续收
                let contentLength = Self.headerValue(head, "Content-Length").flatMap(Int.init) ?? 0
                if body.count < contentLength {
                    self.receive(connection, buffer: buf)
                    return
                }
                body = body.prefix(contentLength)
                let response = self.route(head: head, body: body)
                // HTTP/1.1 短连接（MCP Streamable HTTP 客户端每次独立 POST）
                let headResponse = "HTTP/1.1 \(response.0)\r\nContent-Type: application/json\r\nContent-Length: \(response.1.count)\r\nConnection: close\r\n\r\n"
                var out = Data(headResponse.utf8)
                out.append(response.1)
                connection.send(content: out, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else if error == nil && !isComplete {
                self.receive(connection, buffer: buf)
            } else {
                connection.cancel()
            }
        }
    }

    private static func headerValue(_ head: String, _ name: String) -> String? {
        for line in head.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - 路由与鉴权

    private func route(head: String, body: Data) -> (String, Data) {
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        guard requestLine.contains("POST") else {
            return ("405 Method Not Allowed", Self.jsonData(["error": "POST only"]))
        }
        // Bearer token 鉴权（未授权在 transport 层直接 401，Paste 同款）
        guard let auth = Self.headerValue(head, "Authorization"),
              auth == "Bearer \(token)" else {
            return ("401 Unauthorized", Self.rpcError(id: NSNull(), code: -32001,
                message: "Unauthorized: missing or invalid bearer token"))
        }
        guard let request = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = request["method"] as? String else {
            return ("400 Bad Request", Self.rpcError(id: NSNull(), code: -32700, message: "Parse error"))
        }
        let id = request["id"] ?? NSNull()
        let params = request["params"] as? [String: Any] ?? [:]

        let result: Result<Any, ToolError>
        switch method {
        case "initialize":
            result = .success([
                "protocolVersion": "2025-03-26",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "openpaste", "version": "0.3.1"]
            ])
        case "notifications/initialized":
            return ("202 Accepted", Data()) // 通知无需响应体
        case "tools/list":
            result = .success(["tools": Self.tools.map { $0.jsonObject }])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            result = Self.callTool(name, args, handler: handler)
        case "ping":
            result = .success([:])
        default:
            return ("200 OK", Self.rpcError(id: id, code: -32601, message: "Method not found: \(method)"))
        }

        switch result {
        case .success(let value):
            return ("200 OK", Self.rpcResult(id: id, value))
        case .failure(let err):
            return ("200 OK", Self.rpcError(id: id, code: -32000, message: err.message))
        }
    }

    /// JSON-RPC 响应构造：显式装箱为 Foundation 原生类型（NSNumber/NSDictionary），
    /// 规避 [String: Any] 混装 Swift Int/Struct 桥接后 JSONSerialization 判 invalid 的问题
    private static func boxed(_ value: Any) -> AnyObject {
        switch value {
        case let v as String: return v as NSString
        case let n as NSNumber:
            // NSNumber 桥接陷阱：`as Bool`/`as Int` 对任意 NSNumber 都成立（JSON-RPC id=1 会变 true）。
            // 用 objCType 区分：c=Bool，d=Double，其余按整数原样保留
            switch String(cString: n.objCType) {
            case "c": return NSNumber(value: n.boolValue)
            default: return n
            }
        case is NSNull: return NSNull()
        case let v as [Any]: return v.map(boxed) as NSArray
        case let v as [String: Any]:
            let d = NSMutableDictionary()
            for (k, val) in v { d[k] = boxed(val) }
            return d
        default: return String(describing: value) as NSString // 兜底：绝不让非法类型进序列化器
        }
    }

    private static func rpcResult(id: Any, _ value: Any) -> Data {
        let d = NSMutableDictionary()
        d["jsonrpc"] = "2.0"
        d["id"] = boxed(id)
        d["result"] = boxed(value)
        return (try? JSONSerialization.data(withJSONObject: d)) ?? Data("{}".utf8)
    }

    private static func rpcError(id: Any, code: Int, message: String) -> Data {
        let d = NSMutableDictionary()
        d["jsonrpc"] = "2.0"
        d["id"] = boxed(id)
        d["error"] = boxed(["code": code, "message": message])
        return (try? JSONSerialization.data(withJSONObject: d)) ?? Data("{}".utf8)
    }

    // MARK: - 工具面（Paste 11 工具的前 4 件套）

    static let tools: [MCPToolDef] = [
        MCPToolDef(
            name: "search",
            description: "Search clipboard history by keyword. Returns id, kind, preview and timestamp.",
            inputSchema: [
                "type": "object",
                "properties": ["query": ["type": "string", "description": "Search keyword"]],
                "required": ["query"]
            ]
        ),
        MCPToolDef(
            name: "read_item",
            description: "Read full content of one clipboard item by id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "integer", "description": "Item id from search"]],
                "required": ["id"]
            ]
        ),
        MCPToolDef(
            name: "list_pinboards",
            description: "List all pinboards (pinned collections).",
            inputSchema: ["type": "object", "properties": [:]]
        ),
        MCPToolDef(
            name: "copy_to_clipboard",
            description: "Write a clipboard item back to the system clipboard (does not paste).",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "integer", "description": "Item id"]],
                "required": ["id"]
            ]
        ),
    ]

    private static func callTool(_ name: String, _ args: [String: Any], handler: MCPRequestHandler?) -> Result<Any, ToolError> {
        guard let handler else { return .failure(ToolError(message: "Server not ready")) }
        switch name {
        case "search":
            let query = args["query"] as? String ?? ""
            let items = handler.search(query: query)
            let payload = items.map { item -> [String: Any] in
                var d: [String: Any] = [
                    "id": Int(item.id),
                    "kind": String(describing: item.kind),
                    "preview": item.previewText,
                    "createdAt": ISO8601DateFormatter().string(from: item.createdAt),
                ]
                if let cat = item.category { d["category"] = cat.rawValue }
                return d
            }
            return .success(["content": [["type": "text", "text": Self.pretty(payload)]]])
        case "read_item":
            guard let id = args["id"] as? Int64 ?? (args["id"] as? Int).map(Int64.init),
                  let item = handler.item(id: id) else {
                return .failure(ToolError(message: "Item not found"))
            }
            return .success(["content": [["type": "text", "text": item.text ?? item.previewText]]])
        case "list_pinboards":
            let boards = handler.boards()
            let payload: [[String: Any]] = boards.map {
                ["id": Int($0.id), "name": $0.name, "icon": $0.icon]
            }
            return .success(["content": [["type": "text", "text": Self.pretty(payload)]]])
        case "copy_to_clipboard":
            guard let id = args["id"] as? Int64 ?? (args["id"] as? Int).map(Int64.init),
                  let item = handler.item(id: id) else {
                return .failure(ToolError(message: "Item not found"))
            }
            let ok = handler.copyToClipboard(item)
            return .success(["content": [["type": "text", "text": ok ? "Copied to clipboard" : "Copy failed"]]])
        default:
            return .failure(ToolError(message: "Unknown tool: \(name)"))
        }
    }

    private static func pretty(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    /// 安全序列化：先校验（ObjC 异常 try? 接不住，必须前置检查），非法时打印逐 key 类型定位
    private static func jsonData(_ obj: [String: Any]) -> Data {
        if JSONSerialization.isValidJSONObject(obj) {
            return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        }
        for (k, v) in obj {
            let typeName = "\(type(of: v))"
            let valid = v is String || v is NSNumber || v is NSNull || v is Bool || v is Int || v is Int64
                || v is [Any] || v is [String: Any] || v is Double
            NSLog("[OpenPasteMCP] invalid JSON value: key=\(k) type=\(typeName) validGuess=\(valid)")
            if let dict = v as? [String: Any] {
                for (k2, v2) in dict {
                    NSLog("[OpenPasteMCP]   nested: key=\(k2) type=\(type(of: v2))")
                }
            }
            if let arr = v as? [Any] {
                for (i, el) in arr.enumerated() {
                    NSLog("[OpenPasteMCP]   array[\(i)] type=\(type(of: el))")
                }
            }
        }
        return Data("{\"error\":\"serialization\"}".utf8)
    }
}

/// 业务回调协议（AppDelegate / ViewModel 侧实现；均需回主队列或经 HistoryStore 串行队列）
protocol MCPRequestHandler: AnyObject {
    func search(query: String) -> [ClipItem]
    func item(id: Int64) -> ClipItem?
    func boards() -> [PinBoard]
    func copyToClipboard(_ item: ClipItem) -> Bool
}
