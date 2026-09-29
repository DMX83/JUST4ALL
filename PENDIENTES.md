# PENDIENTES — JUST4ALL (revisión 29-sep-2026)

Consolidado a partir de los TODO de cada app, `QA_LOCAL.md` y la memoria de trabajo.

**Leyenda**: 🟠 código/tarea · 🔵 validación manual · ⚪️ opcional/futuro · 🔴 bloqueado (licencia Apple)

---

## 0) Entorno / configuración (esta semana)

- [ ] 🔵 Recargar la ventana de VS Code para aplicar los ajustes de DeepSeek
      (`reasoningEffort` max→**medium**, `maxTokens` 16384, `debugMode` metadata) y verificar en *Manage Models*.
- [ ] 🟠 **«Configure Tools»: bajar de ~90 a ≤64 herramientas** (desactivar Pylance MCP ~25, .NET ~9,
      Containers, Notebook y Browser si no se usan) → menos tokens por petición.
- [ ] ⚪️ Con ≤64 tools: probar `deepseek-copilot.experimental.stabilizeToolList: true` (mejor cache-hit).
- [ ] ⚪️ Si aparece el MCP `tradingview-local` (de Claude Desktop) en la lista de herramientas: desactivarlo.
- [ ] ⚪️ Opcional: `nextEditSuggestions` (consume cupo de Copilot, no de DeepSeek).

## 1) JUST4FOLDERS (v2.3.9 — orden por Tamaño + vista previa fiable)

**Hecho hoy (29-sep)**
- [x] 🟠 **Integración JUST4PICT por CLI**: submenú **JUST4PICT ▸ → «Mejorar con JUST4PICT ▸»** con 5
      presets (Automático · Retrato · Paisaje · Documento · Ecommerce) sobre `just4pict-cli`, en background
      y sin sobrescribir (`Just4PictActions.swift`). Validado e2e: menú → Paisaje → PNG de 3 MB desde un
      JPEG de 267 KB; IDÉNTICO al CLI a mano.
- [x] 🟠 **Vista previa lateral fiable (v2.3.8)**: las imágenes se pintan en local con ImageIO
      (`LocalImagePreview.swift`) en vez de por QuickLook — éste devolvía el icono genérico la primera vez
      que se pedía un fichero recién creado y se quedaba pegado. QuickLook sigue para PDF/vídeo/documentos
      y ahora reintenta (`refreshPreviewItem()` a 0,4/1,6 s); al crear ficheros la vista previa se refresca.
- [x] 🟠 **Orden por Tamaño correcto (v2.3.9)**: ordenaba con `sizeBytes` (nil en carpetas) y la lista se
      rebarajaba en cada recarga; ahora usa el tamaño efectivo + desempate por nombre, pide todos los
      tamaños al pulsar la cabecera y reordena una sola vez al terminar (las desconocidas, al final).
- [x] 🟠 Nit de estado: el aviso «Actualizado (N cambio(s) en disco)» del watcher ya no pisa los mensajes
      de operación (prioridad temporal en el estado del commander).

**Código**
- [ ] 🟠 Integración JUST4PDF **F3** (opcional): progreso en la cola de trabajos, Quick Actions del Finder
      (v0.3 de JUST4PDF) y módulo del Panel Hub (F4). Ref: `APPS/JUST4FOLDERS/JUST4PDF_INTEGRATION.md`.
- [ ] 🟠 Panel Hub — pendientes menores: reglas favoritas por extensión, unificar el diario de Deshacer para
      el drop del módulo DESK (hoy mueve sin diario), selector compacto (la vista previa perdió ~65 pt de
      alto). El módulo del Panel Hub con el pipeline de PICT sigue pendiente.
- [ ] 🟠 Nit conocido: la última columna («Tipo») puede recortar 1 carácter si el ancho queda justo.
- [ ] ⚪️ Drag & drop interno de ficheros entre paneles (histórico) — comprobar y decidir.

**Validación manual** (`QA_LOCAL.md` § «Checklist manual — Panel Hub v2.3.x»)
- [ ] 🔵 Panel Hub completo: selector persistente, buscador DESK, bandeja, POR REVISAR, ACTIVIDAD, drop→propuesta.
- [ ] 🔵 Submenús contextuales: JUST4PICT (3 ítems `sips` + **Mejorar con JUST4PICT ▸** con 5 presets) y
      JUST4PDF ▸ (Comprimir 3 niveles, Exportar páginas, Crear PDF desde imágenes, Abrir con).
- [ ] 🔵 Pestañas: botón derecho en cada estado; «Renombrar» sobre tab no activa sin activarla.
- [ ] 🔵 Monitor: menú del clic derecho (Reiniciar máximos / Abrir Monitor) sin dispararse al soltar;
      batería en verde con cargador; I/O % en reposo y bajo carga.
- [ ] 🔵 Atrás/Adelante del toolbar: el menú de historial por clic derecho.
- [ ] 🔵 `Operaciones ▸ Exportar diagnóstico…` y paleta ⌘K generan el zip.

**Artefactos**
- [ ] ⚪️ `dist/JUST4FOLDERS.dmg` y `build/Build/Products/Release/*.app` están **atrasados** (el .app es de
      marzo, v0.1.0 = «instancia fantasma»): regenerar antes de distribuir o hacer demos.

## 2) JUST4PICT

- [x] 🟠 **CLI mínimo `just4pict-cli`** (lote sin UI) — HECHO (29-sep): ver `APPS/JUST4PICT/README.md`.
- [x] 🟠 **Integración del CLI en FOLDERS** — HECHO (29-sep): «Mejorar con JUST4PICT ▸» (5 presets) en el
      clic derecho de JUST4FOLDERS; validado e2e. Queda como opcional un «Editar con JUST4PICT» (abrir la app
      con la imagen) cuando la app declare tipos de documento.
- [ ] 🔵 Validación visual final de retrato (ojos/cejas en muestras reales adicionales).
- [ ] 🟠 Telemetría local por build (JSON por corrida: preset, tiempo, memoria, fallos) para comparar regresiones.
- [ ] 🟠 Snapshot de receta efectiva por ítem (incluido fallback IA) para reproducibilidad exacta.
- [ ] 🟠 Matriz QA por escena (muestras fijas con «expected windows» en archivo dedicado).
- [ ] 🟠 Afinar criterios de `AUTO` (documento vs ecommerce con branding ligero).
- [ ] 🟠 Consolidar reportes QA en una salida única por corrida.
- [ ] ⚪️ Copy de estado IA más corto/consistente; preset rápido para web/marketplaces.
- [ ] 🔴 Firma y notarización.

## 3) JUST4PDF

- [ ] 🔵 Checklist manual del `README` (navegación/zoom, PDFs medianos, «Open With», PDF→imágenes,
      imágenes→PDF, unir, compresión 3 niveles + modo seguro).
- [ ] ⚪️ Quick Actions del Finder + progreso en FOLDERS (v0.3) — ligado a FOLDERS F3.
- [ ] 🔴 Firma y notarización.

## 4) JUST4DESK

- [ ] 🔵 Validación visual manual (`swift run`: añadir carpeta real y probar búsqueda/filtros/acciones).
- [ ] 🔵 QA manual: DMG real (`./scripts/build_dmg.sh`) y flujo end-to-end con documentos reales.
- [ ] 🟠 **N6** — Empaquetado real (DMG + sandbox + Quick Action de Finder; las notificaciones ya están).

## 5) JUST4ALL (hub) y global

- [ ] 🟠 Icono placeholder → icono real (icns) y validar tamaños.
- [ ] 🟠 Logos y screenshots reales en `Sources/JUST4ALL/Resources/Assets`.
- [ ] 🟠 Textos, links y requisitos reales por subapp; copy del panel de detalle; accesibilidad básica.
- [ ] 🟠 Build reproducible por subapp (versionado, release notes, checksum) y empaquetado final.
- [ ] 🔴 Firma/notarización, App Store Connect/TestFlight y publicación v1.0.0 — **bloqueado por la licencia
      de Apple** (los DMG locales sí se generan y validan).

## 6) JUST4CONVERT (la subapp más atrasada)

- [ ] 🟠 FLAC real (encoder dedicado o AudioToolbox); bitrate efectivo en export (AVAssetReader/Writer);
      MKV real (evaluar ffmpeg).
- [ ] 🟠 Presets por ítem en la cola; límite de workers (80 % núcleos) como preferencia; toggle de
      aceleración con aviso según formato.
- [ ] 🟠 Errores de apertura con mensajes accionables; pipeline de releases; QA en macOS 13/14/15 (Intel y AS).

---

### Orden sugerido

1. **Hoy/mañana (10 min)**: validación manual rápida de lo de hoy (pestañas, monitor, Atrás/Adelante)
   mientras está fresco → tachar en `QA_LOCAL.md`.
2. **5 min, ahorro continuo**: recargar ventana + «Configure Tools» ≤64.
3. **JUST4PICT CLI** (`just4pict-cli`): desbloquea la integración completa con FOLDERS.
4. **FOLDERS**: JUST4PDF F3 o Panel Hub menores (elegir según uso).
5. **Hub/global**: icono + assets reales cuando se acerque una demo/distribución.
