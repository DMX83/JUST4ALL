# JUST4INDEX — Pitch de producto

> «El buscador instantáneo que además ordena tu caos: encuentra cualquier archivo en milisegundos
> y organiza tus descargas solo, en español, sin que nada salga de tu Mac.»

## Qué es

Tres capas en una app nativa de macOS:

1. **Búsqueda instantánea** estilo «Everything»: índice local (SQLite FTS5 + FSEvents) sobre las
   carpetas autorizadas. Por nombre, ruta, subcadena («net» encuentra *dotnet-sdk* o *Internet…*) y
   contenido (opt-in). Objetivo < 100 ms; benchmark real: 0,3–38 ms en consultas típicas.
2. **Organizador automático inteligente**: vigila **varias** carpetas de entrada (p. ej. `~/Descargas`
   y `~/Downloads`), analiza en local (PDFKit + Vision OCR) y archiva en una taxonomía en español
   (`01_Fiscal`, `13_Multimedia/Peliculas`, `12_Software/Redes`…) con IA opcional (DeepSeek),
   *journal* + **undo** y **cuarentena** para lo dudoso.
3. **Inteligencia local que aprende**: cada decisión de la IA y cada corrección tuya se resumen en
   reglas locales (extensiones y palabras de carpeta). Con el uso, **pregunta cada vez menos** y gasta
   cada vez menos tokens (caché de sugerencias + conocimiento local).

## Para quién

Usuarios de macOS que descargan mucho y viven con carpetas caóticas: desarrolladores, técnicos/redes,
traders, creadores… y cualquiera que quiera «Todo + casa ordenada» **sin subir nada a la nube**.

## Ventajas (con evidencia real)

| Ventaja | Evidencia |
|---|---|
| **Resultados desde el día 1** | `~/Descargas` + `~/Downloads`: **28 GB → 15 MB** organizados hacia `~/JUST4INDEX` (32 GB), **0 errores** |
| **Seguridad radical: nunca borra** | Solo mueve; *journal* + undo (por elemento y por lote), cuarentena para dudas, **modo simulación**, duplicados que se quedan en origen |
| **Inteligencia que se abarata** | **11 reglas aprendidas en horas** de uso real; las promociones clasifican **sin llamar a la IA**; caché de sugerencias; cap diario + **contador exacto de tokens** |
| **Privacidad local-first** | OCR/índice 100 % locales; solo una muestra truncada viaja a DeepSeek, y solo si activas la IA; sin extraer texto de scripts (credenciales) |
| **Criterio fino, no genérico** | Carpetas como unidad (no rompe apps portables), la IA decide **entera vs desglosar** cajones, vocabulario en español, extensiones técnicas (`.rsc` → Redes) |
| **Transparencia total** | Cada decisión trazada (fuente `ai`/`rules`/`knowledge`, confianza, motivo) en registro en vivo (⌘L) y en la UI |
| **Rendimiento sólido** | Índice 100k: crawl ~7 s; búsquedas 0,3–38 ms; pipeline con concurrencia acotada |
| **Interfaz que se vende** | Sistema de diseño propio (marca, chips, tarjetas, estados vacíos) cuidado en claro y oscuro; títulos limpios, sin jerga de build |
| **Control de coste** | Reutilización sin coste (caché + conocimiento), cap configurable, tokens medidos por llamada |

## Limitaciones (honestas)

- **Solo macOS 14+**; pensada para uso personal (no multi-usuario/equipos).
- **Distribución en pañales**: aún sin DMG firmado/notarizado (hoy corre como binario de desarrollo);
  sin sandbox.
- **La IA requiere clave propia de DeepSeek** (coste externo + cap diario; techo orientativo
  ~400k tokens/día) y conexión. Sin ella funciona, con menos aciertos (reglas + conocimiento).
- **La cuarentena requiere tu ojo**: lotes grandes dejan decenas de dudosos para revisión (⌘R) —
  por diseño, la decisión final es tuya.
- **Cobertura documental incompleta**: docx vía unzip del sistema, **xlsx pendiente**; OCR variable
  en escaneos malos.
- **Taxonomía fija en español** (16 categorías, afinables solo por código) y aprendizaje conservador
  (≥ 3 coincidencias): las primeras veces sigue preguntando.
- **Reglas aprendidas sin editor aún**: se corrigen volviendo a mover (eso las reescribe al instante).
- **Pendientes del roadmap**: MenuBar/atajo global, DMG firmado, panel de estadísticas, CI.
- **Riesgo de mala clasificación existe** — mitigado (umbral, cuarentena, undo), no eliminado.

## Comparativa

| Producto | Lo que hace | Lo que NO hace |
|---|---|---|
| Finder / Smart Folders | Búsqueda y carpetas inteligentes | Lento, sin organización automática real |
| Hazel | Reglas para ordenar | Sin IA, reglas a mano, no busca |
| Everything (Windows) | Búsqueda instantánea | Solo Windows; nada de ordenar |
| Apps «IA para archivos» en la nube | Clasifican subiendo tus archivos | Tu contenido sale del equipo |

## Cierre de demo

*«Ayer llegué con 28 GB de descargas mezcladas: hoy las tienes clasificadas en 32 GB de biblioteca
ordenada —cero errores, cero archivos perdidos, todo reversible— y cada corrección que haces hace a
la app más lista para la próxima. Y lo mejor: es tu Mac quien lo hace.»*

## Versión corta (para el catálogo del hub JUST4ALL)

**JUST4INDEX — Buscador instantáneo y organizador inteligente de documentos** (macOS 14+)

- Encuentra cualquier archivo en milisegundos (índice local, subcadena y contenido).
- Deja que ordene tus descargas solo: clasifica por contenido, decide carpeta entera o desglosada y
  archiva con undo y cuarentena revisable.
- Aprende de la IA y de tus correcciones: clasifica sin gastar tokens lo ya aprendido. Todo en tu Mac.

## Estado (2026-09-25)

- Fases F0–F12.0 completadas; **132 tests** (131 en verde + 1 skip).
- Run real: `~/Descargas` + `~/Downloads` organizadas (28 GB movidos, 0 errores), cuarentena en
  revisión asistida, 11 reglas aprendidas.
