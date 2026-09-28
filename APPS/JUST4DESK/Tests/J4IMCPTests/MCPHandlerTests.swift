import XCTest
@testable import J4IMCP
import J4IIndex

/// G7.2 — servidor MCP: handshake, catálogo de herramientas y llamadas.
final class MCPHandlerTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!
    private var server: MCPServer!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        server = MCPServer(service: ArchiveService(index: index))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Raíz con un fichero de texto indexado (nombre + contenido).
    private func seed() async throws -> String {
        let root = tempDir.appendingPathComponent("archivo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("factura-enero.txt")
        try "Factura de la luz de enero. Importe 84,32 euros.".write(to: fileURL, atomically: true, encoding: .utf8)

        let indexRoot = try await index.addRoot(path: root.path)
        _ = try await index.upsertEntries(rootID: indexRoot.id, [
            IndexEntryWrite(url: fileURL, isDirectory: false, sizeBytes: 48, modifiedAt: Date())
        ])
        let maybeID = try await index.entryID(path: fileURL.path)
        if let id = maybeID {
            try await index.setDocumentText(entryID: id, text: "Factura de la luz de enero. Importe 84,32 euros.")
        }
        return fileURL.path
    }

    private func callTool(_ name: String, _ arguments: [String: Any]) async throws -> [String: Any] {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 7,
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments]
        ]
        let maybeResponse = await server.handle(message)
        let response = try XCTUnwrap(maybeResponse)
        return try XCTUnwrap(response["result"] as? [String: Any])
    }

    private func text(of toolResult: [String: Any]) -> String {
        let content = toolResult["content"] as? [[String: Any]]
        return (content?.first?["text"] as? String) ?? ""
    }

    func testInitializeHandshake() async throws {
        let response = await server.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [String: Any]()])
        let result = try XCTUnwrap(response?["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, MCPServer.protocolVersion)
        let info = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(info["name"] as? String, "just4desk-mcp")
        XCTAssertNotNil(result["capabilities"])
    }

    func testInitializedNotificationHasNoResponse() async {
        let response = await server.handle(["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(response)
    }

    func testToolsList() async throws {
        let response = await server.handle(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let result = try XCTUnwrap(response?["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["buscar_archivos", "leer_documento"])
        for tool in tools {
            XCTAssertNotNil(tool["inputSchema"], "cada herramienta declara su esquema")
        }
    }

    func testSearchToolFindsFileByContent() async throws {
        _ = try await seed()
        let result = try await callTool("buscar_archivos", ["consulta": "factura de la luz"])
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertTrue(text(of: result).contains("factura-enero.txt"), text(of: result))
    }

    func testSearchToolRequiresQuery() async throws {
        let response = await server.handle([
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": ["name": "buscar_archivos", "arguments": [String: Any]()]
        ])
        let result = try XCTUnwrap(response?["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    func testReadToolUsesIndexedText() async throws {
        let path = try await seed()
        let result = try await callTool("leer_documento", ["ruta": path])
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertTrue(text(of: result).contains("luz de enero"))
    }

    func testReadToolMissingFile() async throws {
        let result = try await callTool("leer_documento", ["ruta": "/no/existe/xyz.pdf"])
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    func testUnknownMethodAndTool() async throws {
        let response = await server.handle(["jsonrpc": "2.0", "id": 4, "method": "otro/metodo"])
        let error = try XCTUnwrap(response?["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)

        let unknown = await server.handle([
            "jsonrpc": "2.0",
            "id": 5,
            "method": "tools/call",
            "params": ["name": "no_existe", "arguments": [String: Any]()]
        ])
        let unknownError = try XCTUnwrap(unknown?["error"] as? [String: Any])
        XCTAssertEqual(unknownError["code"] as? Int, -32602)
    }
}
