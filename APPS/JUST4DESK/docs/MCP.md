# JUST4DESK — MCP para agentes (`JUST4DESKMCP`)

Servidor **MCP** (Model Context Protocol) local que expone el archivo JUST4DESK en **solo
lectura** para agentes compatibles (Claude Desktop, VS Code/Copilot, etc.). La app **no necesita
estar abierta**: el índice es SQLite en WAL y admite lecturas simultáneas.

## Compilar

```bash
cd APPS/JUST4DESK
swift build -c release --product JUST4DESKMCP
# binario: .build/release/JUST4DESKMCP
```

## Herramientas

| Herramienta | Qué hace |
|---|---|
| `buscar_archivos` | Busca por nombre/ruta/contenido (FTS5 + sinónimos en español; si hay pocos aciertos, reintenta con OR). Nunca devuelve carpetas. Parámetros: `consulta` (obligatorio), `limite` (1–50, def. 12), `incluir_contenido` (def. true). |
| `leer_documento` | Devuelve el texto extraído (hasta `max_caracteres`, def. 6000) desde el índice o, si no lo tiene, extraído al momento (PDFKit/OCR local). Parámetro: `ruta` (admite `~`). |

Variable opcional: `JUST4DESK_INDEX_PATH` para apuntar a otro índice.

## Configuración

### Claude Desktop (`claude_desktop_config.json`)

```json
{
  "mcpServers": {
    "just4desk": {
      "command": "/Users/<tu-usuario>/Repos/JUST4ALL/APPS/JUST4DESK/.build/release/JUST4DESKMCP"
    }
  }
}
```

### VS Code (`.vscode/mcp.json`)

```json
{
  "servers": {
    "just4desk": {
      "type": "stdio",
      "command": "/Users/<tu-usuario>/Repos/JUST4ALL/APPS/JUST4DESK/.build/release/JUST4DESKMCP"
    }
  }
}
```

## Notas

- Protocolo: JSON-RPC 2.0 por stdio (`initialize`, `tools/list`, `tools/call`); `stdout` es el
  canal del protocolo, cualquier traza va al registro de la app (`~/Library/Logs/JUST4DESK/`).
- Privacidad: el servidor es **solo lectura**, no mueve ni modifica nada y no hace red. Lo que el
  agente haga después con el texto ya depende de ese agente.
