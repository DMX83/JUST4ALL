import Foundation
import J4IMCP
import J4IIndex

// JUST4DESKMCP — servidor MCP local (stdio) del archivo JUST4DESK para agentes (G7.2).
//
// Uso: configúralo como servidor MCP (ver docs/MCP.md). La app NO necesita estar abierta:
// el índice es SQLite en WAL y admite lecturas simultáneas. Variable opcional
// JUST4DESK_INDEX_PATH para apuntar a otro índice.

let environment = ProcessInfo.processInfo.environment
let databasePath = environment["JUST4DESK_INDEX_PATH"]
    ?? (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/JUST4DESK/index.sqlite")

let index = SearchIndex(databaseURL: URL(fileURLWithPath: databasePath))
let server = MCPServer(service: ArchiveService(index: index))
await MCPStdio.run(server: server)
