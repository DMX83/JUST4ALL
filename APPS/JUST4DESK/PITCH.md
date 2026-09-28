# JUST4DESK — Pitch de producto

> «Tu escritorio inteligente: ordena, encuentra y protege tu documentación — en milisegundos,
> en español y sin que nada salga de tu Mac.»

## Qué es

Cuatro capas en una app nativa de macOS:

1. **Inicio — centro de control**: bandeja de decisiones (revisar, deshacer), actividad, estado,
   **sugerencias proactivas** (duplicados → Papelera, capturas sueltas, grandes y olvidados →
   *archivo en frío* con undo), **colecciones** («organizar sin mover»), **informe semanal** e
   **omnibox ⌘K**.
2. **Búsqueda instantánea y por significado**: índice local (SQLite FTS5 + FSEvents) por nombre,
   ruta, subcadena («net» encuentra *dotnet-sdk* o *Internet…*) y contenido. **Semántica local**
   (sinónimos: «sueldo» → «nómina») y **Chat del archivo** (⇧⌘K): pregunta en lenguaje natural y
   responde citando tus documentos; y un servidor **MCP** para que otros agentes consulten tu archivo.
3. **Organizador automático inteligente**: vigila **varias** carpetas de entrada (p. ej. `~/Descargas`
   y `~/Downloads`), analiza en local (PDFKit + Vision OCR) y archiva en una taxonomía en español
   (`01_Fiscal`, `13_Multimedia/Peliculas`, `12_Software/Redes`…) con IA opcional (DeepSeek),
   *journal* + **undo** y cola «sin clasificar» para lo dudoso.
4. **Inteligencia local que aprende**: cada decisión de la IA y cada corrección tuya se resumen en
   reglas locales, **visibles, editables y exportables** (⌘G). Con el uso, **pregunta cada vez menos**
   y gasta menos tokens (caché de sugerencias + conocimiento local).

## Para quién

Usuarios de macOS que descargan mucho y viven con carpetas caóticas: desarrolladores, técnicos/redes,
traders, creadores… y cualquiera que quiera «Todo + casa ordenada» **sin subir nada a la nube**.

## Ventajas (con evidencia real)

| Ventaja | Evidencia |
|---|---|
| **Resultados desde el día 1** | `~/Descargas` + `~/Downloads`: **28 GB organizados, 0 errores** hacia `~/JUST4DESK`; hoy **3.950 ficheros indexados** en el archivo real del autor |
| **Mantenimiento continuo** | Sugerencias que se pagan solas: 4 duplicados (25 MB) a la Papelera en un clic; capturas sueltas archivadas; «grandes y olvidados» → `90_Archivo` con undo; **informe semanal** exportable |
| **Seguridad radical: nunca borra** | Solo mueve; *journal* + undo (por elemento y por lote), cola «sin clasificar», **modo simulación**; el reindexado ya no pierde textos ni vectores (snapshot + re-vinculado por ruta) |
| **Inteligencia que se abarata** | **27 reglas promovidas** en uso real; clasifican **sin llamar a la IA**; caché de sugerencias; cap diario + **contador exacto de tokens** (165k acumulados) |
| **Buscas como piensas** | **«sueldo» encuentra la nómina** aunque la palabra no exista; **chat del archivo** con citas clicables; el mismo índice disponible para agentes vía **MCP** |
| **Privacidad local-first** | OCR/índice/embeddings 100 % locales; a DeepSeek solo una muestra truncada (≤4.000 caracteres) y solo si activas la IA; nunca scripts (credenciales) |
| **Criterio fino, no genérico** | Carpetas como unidad (no rompe apps portables), la IA decide **entera vs desglosar** cajones, vocabulario en español, extensiones técnicas (`.rsc` → Redes) |
| **Transparencia total** | Cada decisión trazada (fuente `ai`/`rules`/`knowledge`, confianza, motivo) en registro en vivo (⌘L) y en la UI |
| **Rendimiento sólido** | Índice 100k: crawl ~7 s; búsquedas 0,3–38 ms; 3.950 ficheros re-vectorizados en local en ~1 min; pipeline con concurrencia acotada |
| **Interfaz que se vende** | Sistema de diseño propio (marca, chips, tarjetas, estados vacíos) en claro y oscuro; centro de control «Inicio» que enseña el trabajo hecho |
| **Control de coste** | Reutilización sin coste (caché + conocimiento), cap configurable, tokens medidos por llamada |

## Limitaciones (honestas)

- **Solo macOS 14+**; pensada para uso personal (no multi-usuario/equipos).
- **Distribución en pañales**: aún sin DMG firmado/notarizado (hoy corre como binario de desarrollo);
  sin sandbox.
- **La IA requiere clave propia de DeepSeek** (coste externo + cap diario) y conexión. Sin ella
  funciona con reglas + conocimiento local — y toda la búsqueda (incluida la semántica) es local.
- **La cola «sin clasificar» requiere tu ojo**: lotes grandes dejan dudosos para revisar (⌘R) —
  por diseño, la última palabra es tuya.
- **Cobertura documental**: xlsx pendiente, docx vía unzip del sistema; OCR variable en escaneos
  malos; los vectores semánticos puntúan documentos **con** texto (el resto va por nombre/sinónimos).
- **Taxonomía en español** (17 nodos seed, ampliable) y aprendizaje conservador (≥ 3 coincidencias):
  las primeras veces sigue preguntando.
- **Pendientes del roadmap**: etiquetas Finder nativas (decisión abierta), DMG firmado + Quick
  Action de Finder, icono propio, accesibilidad fina y CI.
- **Riesgo de mala clasificación existe** — mitigado (umbral, cola «sin clasificar», undo), no eliminado.

## Comparativa

| Producto | Lo que hace | Lo que NO hace |
|---|---|---|
| Finder / Smart Folders | Búsqueda y carpetas inteligentes | Lento, sin organización automática real |
| Hazel | Reglas para ordenar | Sin IA, reglas a mano, no busca |
| Everything (Windows) | Búsqueda instantánea | Solo Windows; nada de ordenar |
| Apps «IA para archivos» en la nube | Clasifican subiendo tus archivos | Tu contenido sale del equipo |

## Cierre de demo

*«Ayer llegué con 28 GB de descargas mezcladas: hoy son 3.950 ficheros ordenados —cero errores,
cero pérdidas, todo reversible—. Escribo «sueldo» y aparece la nómina; pregunto por un recibo y me
cita el documento exacto; y si reindexo, no se pierde nada. Todo lo hace tu Mac.»*

## Versión corta (para el catálogo del hub JUST4ALL)

**JUST4DESK — Tu escritorio inteligente: busca, ordena y pregunta** (macOS 14+)

- Encuentra cualquier archivo en milisegundos — por nombre, ruta, contenido y **significado**
  («sueldo» → «nómina») — con **chat del archivo** que responde citando tus documentos.
- Deja que ordene tus descargas solo: clasifica por contenido, decide carpeta entera o desglosada,
  archiva con undo y cola «sin clasificar» revisable, y mantiene el orden (sugerencias + archivo en frío).
- Aprende de la IA y de tus correcciones con reglas visibles y exportables; expón tu archivo a otros
  agentes vía **MCP**. Todo en tu Mac.

## Estado (2026-09-28)

- Fases F0–F15 y **G1–G7 completadas** (Inicio, sugerencias, reglas, presencia, colecciones,
  archivo en frío, informe semanal, búsqueda semántica, chat y MCP); **suite 211** (210 en verde + 1 skip).
- Run real: `~/Descargas` + `~/Downloads` organizadas (28 GB, 0 errores); **3.950 ficheros**
  indexados, 344 textos recuperados, 3.997 vectores locales, 27+ reglas aprendidas.
