# Privacidad — JUST4DESK

Resumen: JUST4DESK procesa todo localmente. La red solo se usa, de forma **opcional**, para
consultar la API de DeepSeek cuando la clasificación IA está activada.

## Qué sale del equipo (solo con IA activa)

Se envía a `https://api.deepseek.com` (modelo `deepseek-flash`):

- una muestra de texto **truncada** del documento (≤ 4000 caracteres por defecto),
- nombre del archivo, extensión y tamaño,
- la lista de categorías de tu taxonomía.

Si el documento no tiene texto extraíble (instaladores, vídeo, comprimidos…), solo se envían el
nombre, la extensión y el tamaño: nunca contenido.

**No** se envían: el archivo en sí, imágenes renderizadas, rutas completas, ni otros datos del sistema.

## Qué queda siempre en local

- Todos los archivos y el árbol `~/JUST4DESK`.
- OCR (Vision) y extracción de texto (PDFKit).
- El índice de búsqueda (SQLite en `~/Library/Application Support/JUST4DESK/`).
- Historial, journal de operaciones y cache de análisis (por hash de contenido).
- El registro de actividad (local): `~/Library/Logs/JUST4DESK/just4desk.log` y el registro unificado de
  macOS. Nunca se envía a ningún servidor.

## Claves

- `DEEPSEEK_API_KEY` se lee del entorno o de `.env.secrets` (raíz del repo). No se persiste en la app.

## Control del usuario

- Desactivar IA → 100 % local (solo reglas).
- Modo simulación → no se mueve nada; solo se registran propuestas.
- Undo por lote/item en el historial.

## Retención

- Cache de análisis y journal: locales y borrables desde Ajustes (F5+).
