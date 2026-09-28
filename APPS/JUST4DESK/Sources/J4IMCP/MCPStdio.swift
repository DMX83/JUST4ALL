import Foundation

/// Bucle stdio del servidor MCP: lee mensajes JSON-RPC por líneas de stdin y responde por stdout.
///
/// Importante: stdout es el canal del protocolo — cualquier traza debe ir a stderr o al fichero
/// de registro (J4Log escribe a `~/Library/Logs/JUST4DESK/`), nunca con `print`.
public enum MCPStdio {
    public static func run(server: MCPServer) async {
        let input = FileHandle.standardInput
        var buffer = Data()
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break } // EOF
            buffer.append(chunk)
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                guard !lineData.isEmpty else { continue }
                await process(lineData, server: server)
            }
        }
    }

    static func process(_ lineData: Data, server: MCPServer) async {
        guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            write([
                "jsonrpc": "2.0",
                "id": NSNull(),
                "error": ["code": -32700, "message": "JSON no válido."]
            ])
            return
        }
        if let response = await server.handle(object) {
            write(response)
        }
    }

    static func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        var line = data
        line.append(0x0A)
        FileHandle.standardOutput.write(line)
    }
}
