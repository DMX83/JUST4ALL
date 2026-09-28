# JUST4DESK (macOS)

App nativa macOS en SwiftUI que une dos herramientas:

1. **Buscador instantáneo** tipo "Everything": índice local (SQLite FTS5) actualizado por
   FSEvents sobre carpetas autorizadas. Búsqueda por nombre, ruta y contenido, con latencia
   objetivo < 100 ms.
2. **Organizador inteligente de documentos**: vigila carpetas de entrada (por defecto
   `~/Descargas`), extrae el texto localmente (PDFKit + Vision OCR), clasifica cada documento
   (reglas locales + DeepSeek opcional) y lo archiva en una taxonomía `~/JUST4DESK` con undo
   y cola «sin clasificar».

## Estado actual (2026-09-24)

- **F0 — Fundaciones: completada** (scaffold SPM, gobernanza, documentación base).
- **F1 — Motor de índice: completada** (SQLite FTS5 + crawler + FSEvents; bench 100k: crawl ~7 s).
- **F2 — UI Buscador: completada** (keyboard-first, filtros, progreso, gestión de carpetas).
- **F3.0 — Configuración inicial: completada** (carpeta raíz + carpeta de entrada + taxonomía al primer arranque).
- **F3 — Ingesta y análisis: completada** (watcher con estabilidad, PDFKit/Vision OCR, metadatos, hash).
- **F4 — Clasificación IA: completada** (DeepSeek JSON opcional + reglas locales + planner).
- **F5 — Archivado automático: completada** (taxonomía, journal con undo, cola «sin clasificar», simulación).
- **F6 — Hub + release + QA: completada** (catálogo hub, scripts, workspace, docs).
- **F6.1 — Registro en vivo: completada** (`J4Log`: archivo rotativo + registro unificado + visor «Registro» con ⌘L).
- **F7 — Reconocimiento por nombre/extensión + Explorador + concurrencia: completada** (análisis lite,
  taxonomía Software/Multimedia/Comprimidos, ventana Explorador ⌘E, cola de archivado acotada).
- **F7.1 — Ajustes + menú Ver + explorador con propiedades: completada** (Ajustes ⌘,, atajos visibles
  en el menú Ver, propiedades y selección marcada en el explorador).
- **F7.2–F7.4 — atajos fiables y explorador: completadas** (⌘E/⌘L/⌘A, selección marcada y «Mover a la
  papelera» manual y reversible desde el explorador).
- **F7.5 — Búsqueda por contenido: completada** (toggle «En contenido» + fragmento resaltado en los
  resultados).
- **F7.6 — Revisión de «sin clasificar»: completada** (ventana «Por revisar» ⌘R: sugerencia de destino y
  mover en un clic, con deshacer desde Actividad).
- **F7.7/F7.8 — «Por revisar» 2.0: completada** (orden por extensión con secciones, selección múltiple
  para mover en lote y papelera para la selección).
- **F8.0 — Explorador 2.0: completada** (selección múltiple con «Mover a…» y papelera en lote, orden y
  filtro por carpeta, duplicados visibles y vista previa con la barra espaciadora).
- **F8.1 — Interfaz: completada** (buscador con anillo de foco, chips con iconos, estado inicial con
  tarjetas de atajos, hover en listas y barra de estado más limpia).
- **F8.2 — Explorador con árbol: completada** (panel izquierdo jerárquico, navegación de un clic y
  expandir/contraer todo).
- **F8.3 — Ingesta por unidades: completada** (ficheros **y carpetas completas** de la carpeta de
  entrada se perfilan, clasifican y archivan enteras — sin descomponer ni renombrar; aviso de
  permisos con acceso directo a Ajustes del Sistema y «Reintentar»).
- **F9.0 — Skill interna del clasificador: completada** (instrucciones curadas + 12 casos reales que
  son few-shot para la IA y tests de regresión; sin edición por el usuario — se afina con la app).
- **F7.9 — Búsqueda por subcadena: completada** («net» encuentra «dotnet-sdk» o «Internet…»; los
  prefijos siguen rankeando primero; insensible a acentos).
- **F9.2 — Taxonomía fina: completada** (`Peliculas`, `Series`, `Documentales`, `Audiolibros`,
  `Musica` en multimedia; `Cursos` en educación; nueva `15_Libros` para ebooks).
- **F9.4 — Extensiones técnicas: completada** (`.rsc` de MikroTik y configs de red → nueva
  `12_Software/Redes`; scripts de código → `12_Software/Desarrollo`; skill v4 con 17 casos).
- **F10.0 — Desglose de cajones: completada** (la IA decide si una carpeta se archiva entera — app
  portable, curso, colección — o se desglosa por ficheros — cajón heterogéneo —; acción manual en ⌘R).
- **N4 — Segunda carpeta de entrada: completada** (varias entradas por Ajustes — `~/Descargas` +
  `~/Downloads` en este equipo —; un watcher por carpeta y una sola pipeline de archivado).
- **F12.0 — Tokens reales + conocimiento local: completada** (contador de tokens por llamada en
  Ajustes → IA; la app aprende de la IA y de tus correcciones —extensiones y palabras de carpeta— y
  clasifica sin gastar tokens lo ya aprendido).
- Pendiente: QA manual del usuario (DMG real + flujo end-to-end con documentos reales).

Sigue el avance en `TODO.md`; las decisiones y el histórico viven en `MEMORY.md`.
Resumen comercial y análisis de producto (con ventajas y limitaciones): `PITCH.md`.

## Requisitos

- macOS 14+
- Xcode 15+
- Opcional (funciones IA): `DEEPSEEK_API_KEY` en entorno o `.env.secrets`

## Ejecutar

```bash
swift run
```

O bien `./scripts/run.sh`: compila si hace falta, relanza la app **desacoplada de la terminal**
(sobrevive al cierre del terminal) y deja la salida en `/tmp/j4i-app-stdio.log`.

## Primeros pasos

1. Primer arranque: la app pide **carpeta raíz** (sugerencia `~/JUST4DESK`; se crea el árbol de
taxonomía: `01_Fiscal`, `02_Banca`, … `99_SinClasificar`) y **carpeta de entrada** a vigilar
(sugerencia `~/Descargas`).
2. A partir de ahí, cada documento que llegue a la carpeta de entrada —ficheros sueltos **y carpetas
completas**— se analiza y archiva automáticamente (con undo desde el panel de Actividad y cola «sin clasificar»
para lo dudoso — revísala con **⌘R**, ventana «Por revisar»). La carpeta de organización se indexa
para el buscador.
3. Para ver qué está haciendo la app en cada momento: menú **Carpetas → Ver registro…** (⌘L) —visión
en vivo con filtros— o desde terminal `./scripts/log_watch.sh`. El log se guarda en
`~/Library/Logs/JUST4DESK/just4desk.log`.
4. Para navegar por lo organizado: **Explorador** (menú Ver → Abrir explorador, **⌘E**): árbol de
carpetas expandible a la izquierda (un clic navega y sus ficheros aparecen en el centro), selección
múltiple (⌘/mayús-clic) con orden y filtro, propiedades a la derecha (con duplicados detectados).
Acciones: **Mover a…** (con buscador de destino —puedes crear categorías al momento— y undo en Actividad) y **Mover a la papelera** (reversible; el archivado
automático nunca borra). Con ficheros seleccionados, la **barra espaciadora** abre la vista previa.
5. **Ajustes** (⌘A o ⌘,): carpetas de organización/entrada, modo simulación, pausa, indexado y diagnóstico.

## Build DMG

```bash
./scripts/build_dmg.sh
```

Genera `dist/JUST4DESK-<version>+<buildStamp>.dmg` (con alias `JUST4DESK.dmg` y
`JUST4DESK-latest.dmg`).

## Configuración IA (DeepSeek)

Orden de resolución de la key:

1. Variable de entorno `DEEPSEEK_API_KEY`
2. Archivo `.env.secrets` en la raíz del repo (o carpetas padre)

Sin key, la app funciona en modo "solo reglas locales" (sin llamadas de red).

## Privacidad

- Los archivos **nunca** salen del equipo: solo se envía a DeepSeek una muestra de texto
  truncada y metadatos mínimos, y solo si la IA está activa.
- Todo el análisis pesado (OCR, extracción, índice) es local.
- Detalles en `PRIVACY.md`.

## Documentación

- Tareas activas: `TODO.md`
- Cambios por versión: `CHANGELOG.md`
- Memoria maestra (decisiones, hitos, lecciones): `MEMORY.md`
- Arquitectura viva: `ARCHITECTURE.md`
- Privacidad: `PRIVACY.md`
- MCP para agentes (Claude, VS Code…): `docs/MCP.md`
- Skill de agente para VS Code: `.github/skills/just4desk/SKILL.md`

## MCP para agentes (opcional)

El ejecutable `JUST4DESKMCP` expone el archivo como **servidor MCP local** (solo lectura:
`buscar_archivos` y `leer_documento`). Compílalo con
`swift build -c release --product JUST4DESKMCP` y configúralo en tu agente — instrucciones
completas en `docs/MCP.md`. La app no necesita estar abierta (índice en WAL).

## Hub JUST4ALL

JUST4DESK es una subapp del ecosistema JUST4ALL:

- Carpeta `APPS/JUST4DESK`, ejecutable/esquema `JUST4DESK`, bundle `com.dmx83.just4desk`.
- Distribución: DMG `JUST4DESK-<semver>.dmg` + `SHA256SUMS.txt` en GitHub Releases.
