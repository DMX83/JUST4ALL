import Foundation

/// G7.2 — Servidor MCP mínimo (Model Context Protocol) sobre `ArchiveService`.
///
/// JSON-RPC 2.0 por stdio con las piezas esenciales: `initialize`, `tools/list` y `tools/call`.
/// La lógica es pura (dict ↔ dict) para poder probarla sin tocar stdin/stdout.
public struct MCPServer {
    public static let protocolVersion = "2024-11-05"
    public static let serverName = "just4desk-mcp"
    public static let serverVersion = "0.1.0"

    private let service: ArchiveService

    public init(service: ArchiveService) {
        self.service = service
    }

    /// Procesa un mensaje y devuelve la respuesta (`nil` para notificaciones).
    public func handle(_ message: [String: Any]) async -> [String: Any]? {
        guard let method = message["method"] as? String else {
            return errorResponse(id: message["id"], code: -32600, message: "Mensaje JSON-RPC sin «method».")
        }
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return success(id: id, result: [
                "protocolVersion": Self.protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": Self.serverName, "version": Self.serverVersion]
            ])
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return success(id: id, result: [String: Any]())
        case "tools/list":
            return success(id: id, result: ["tools": Self.toolDefinitions])
        case "tools/call":
            return await handleToolCall(id: id, params: params)
        default:
            return errorResponse(id: id, code: -32601, message: "Método no soportado: \(method)")
        }
    }

    // MARK: - Herramientas

    static var toolDefinitions: [[String: Any]] {
        [
            [
                "name": "buscar_archivos",
                "description": "Busca en el archivo local de JUST4DESK (índice FTS5 + sinónimos en español). Devuelve ficheros con su ruta, tamaño y un fragmento cuando coincide por contenido.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "consulta": [
                            "type": "string",
                            "description": "Texto a buscar (nombre, ruta o contenido). Admite lenguaje natural."
                        ],
                        "limite": [
                            "type": "integer",
                            "description": "Máximo de resultados (1–50). Por defecto 12."
                        ],
                        "incluir_contenido": [
                            "type": "boolean",
                            "description": "Buscar también dentro del texto extraído de los documentos. Por defecto true."
                        ]
                    ],
                    "required": ["consulta"]
                ]
            ],
            [
                "name": "leer_documento",
                "description": "Devuelve el texto extraído de un documento del archivo (usa el índice; si no lo tiene, extrae al momento con PDFKit/OCR local). Admite «~» en la ruta.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "ruta": [
                            "type": "string",
                            "description": "Ruta del fichero (p. ej. ~/JUST4DESK/01_Fiscal/…) o del índice."
                        ],
                        "max_caracteres": [
                            "type": "integer",
                            "description": "Tope de caracteres devueltos (por defecto 6000)."
                        ]
                    ],
                    "required": ["ruta"]
                ]
            ]
        ]
    }

    private func handleToolCall(id: Any?, params: [String: Any]) async -> [String: Any] {
        guard let name = params["name"] as? String else {
            return errorResponse(id: id, code: -32602, message: "Falta «name» en tools/call.")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        switch name {
        case "buscar_archivos":
            guard let consulta = arguments["consulta"] as? String,
                  !consulta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return toolError(id: id, text: "Falta el parámetro «consulta».")
            }
            let limit = (arguments["limite"] as? Int) ?? 12
            let includeContent = (arguments["incluir_contenido"] as? Bool) ?? true
            let results = await service.search(consulta, limit: limit, includeContent: includeContent)
            if results.isEmpty {
                return toolResult(id: id, text: "Sin resultados para «\(consulta)».")
            }
            return toolResult(id: id, text: Self.render(results))

        case "leer_documento":
            guard let ruta = arguments["ruta"] as? String, !ruta.isEmpty else {
                return toolError(id: id, text: "Falta el parámetro «ruta».")
            }
            let maxCharacters = (arguments["max_caracteres"] as? Int) ?? 6000
            guard let document = await service.read(path: ruta, maxCharacters: maxCharacters) else {
                return toolError(id: id, text: "No se pudo leer «\(ruta)»: no está en el índice o no tiene texto extraíble.")
            }
            let origin = document.fromIndex ? "texto del índice" : "texto extraído al momento"
            return toolResult(id: id, text: "«\(document.name)» (\(origin), \(document.text.count) caracteres):\n\n\(document.text)")

        default:
            return errorResponse(id: id, code: -32602, message: "Herramienta desconocida: \(name)")
        }
    }

    static func render(_ results: [ArchiveSearchResult]) -> String {
        var lines = ["\(results.count) resultado(s):"]
        for (index, result) in results.enumerated() {
            let path = (result.path as NSString).abbreviatingWithTildeInPath
            let size = ByteCountFormatter.string(fromByteCount: result.sizeBytes, countStyle: .file)
            var line = "[\(index + 1)] \(result.name) — \(path) (\(size))"
            if result.matchedContent {
                line += " · coincide en contenido"
            }
            lines.append(line)
            if let snippet = result.snippet, !snippet.isEmpty {
                lines.append("    \(snippet)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON-RPC

    private func success(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func toolResult(id: Any?, text: String) -> [String: Any] {
        success(id: id, result: ["content": [["type": "text", "text": text]], "isError": false])
    }

    private func toolError(id: Any?, text: String) -> [String: Any] {
        success(id: id, result: ["content": [["type": "text", "text": text]], "isError": true])
    }
}
