# TODO JUST4ALL

## Fase 0 - Fundaciones (completado)

- [x] Renombrar FluxPDF a JUST4PDF (codigo, assets y referencias).
- [x] UI inicial de JUST4ALL con seleccion y panel de detalles.
- [x] Crear carpetas de recursos para logos y screenshots.
- [x] Scripts basicos para generar Xcode project.
- [x] Script DMG para JUST4ALL (build y layout).

## Fase 1 - UX, contenido y marca

- [ ] Reemplazar icono placeholder de JUST4ALL y validar tamanos (icns).
- [ ] Completar logos y screenshots reales en Sources/JUST4ALL/Resources/Assets.
- [ ] Ajustar textos, links y requisitos reales por subapp.
- [ ] Validar accesibilidad basica (contraste, tamanos de fuente, focus).
- [ ] Revisar copy de panel de detalle y estados (abrir/descargar).

## Fase 2 - Distribucion local y empaquetado

- [x] Crear carpeta de DMGs en Sources/JUST4ALL/Resources/Downloads.
- [x] Publicar DMGs de JUST4PDF y JUST4CONVERT dentro de esa carpeta.
- [x] Ajustar botones de descarga para usar DMGs locales y URLs reales cuando existan.
- [x] Verificar que JUST4ALL pueda abrir los DMG locales desde Resources/Downloads (sin depender de enlaces).
- [ ] Build reproducible por subapp (versionado, release notes, checksum).
- [ ] Empaquetado final por subapp (DMG, icono, info.plist, firma).

## Fase 3 - Migracion JUST4CONVERT (desde file_conversor)

- [x] Mapear funcionalidades clave del CLI de file_conversor para audio, video e imagen.
- [x] Definir pipeline de conversion por tipo (audio, video, imagenes).
- [x] Implementar MVP nativo: importar archivo y convertir 1 formato por categoria.
- [x] Agregar presets basicos (bitrate audio, resolucion/fps video, calidad imagen).
- [x] Agregar progreso basico en UI durante conversion.
- [x] Agregar soporte batch (cola multi-archivo).
- [ ] Agregar historial de conversion y ultima salida.
- [ ] Alinear bundle id, nombre de app y recursos con JUST4ALL.
- [x] Empaquetar DMG para JUST4CONVERT.

## Fase 3.1 - JUST4CONVERT mejoras (roadmap MVP+)

- [x] Expandir formatos de salida en imagen (JPG/PNG/HEIC/HEIF/TIFF/BMP/GIF).
- [x] Expandir formatos de salida en audio (MP3/AAC).
- [ ] Soporte real FLAC (encoder dedicado o AudioToolbox).
- [x] Expandir formatos de salida en video (MP4/H.264).
- [x] Expandir formato de salida en imagen (WEBP).
- [x] Presets por item en la cola (override por archivo sin afectar el preset global).
- [x] Progreso real + ETA por item (usar AVAssetExportSession y estimaciones basadas en tamanio/duracion).
- [x] Nombres de salida inteligentes (plantillas con fecha, sufijos, y manejo de colisiones).
- [x] Agregar carpetas desde selector (expandir contenido a la cola, respetar filtros de formato).
- [x] Drag & drop de carpetas (expandir contenido a la cola, respetar filtros de formato).
- [x] Diagnostico basico de errores por item (mensaje visible).
- [x] Reintento rapido por item fallido.
- [x] Opcion de aceleracion/codec (H.264 vs HEVC, bitrate objetivo, resolucion/fps).
- [ ] Bitrate efectivo en export (pipeline AVAssetReader/Writer).
- [x] Panel de historial (ultimos outputs con abrir/revelar en Finder).
- [x] Entrada mixta por item (auto-detectar tipo y elegir formato de salida por item).
- [ ] MKV real (requiere encoder externo, evaluar ffmpeg).

### Detalles de implementacion sugeridos

- [ ] Formatos: mapear cada formato a presets AVFoundation/ImageIO y validar compatibilidad por extension.
- [ ] Presets por item: almacenar presets en modelo de cola y permitir editar desde la lista.
- [ ] Progreso: mostrar barra por item + estado global y evitar bloquear UI.
- [ ] Nombres: reglas simples (ej: nombre_original + preset + fecha) y opcion de auto-incremento.
- [ ] Carpetas: lectura recursiva con limite de profundidad configurable.
- [ ] Errores: conservar causa y stack compacto; boton "Copiar error".
- [ ] Aceleracion: exponer toggle y advertir compatibilidad segun el formato.
- [ ] Historial: persistir en UserDefaults con limite configurable.

## Fase 4 - Experiencia de hub

- [x] Detectar si la subapp esta instalada y mostrar estado.
- [x] Boton de descarga/instalacion si no existe.
- [x] Vista de version y changelog por subapp.
- [x] Historial de instalaciones y ultimo uso por subapp.
- [ ] Manejo de errores de apertura con mensajes accionables.

## Fase 5 - Publicacion

- [ ] Firma y notarizacion (cuando haya cuenta de desarrollador).
- [ ] Pipeline de releases (CI, etiquetas, assets, changelog).
- [ ] QA final en macOS 13/14/15 (Intel y Apple Silicon).
