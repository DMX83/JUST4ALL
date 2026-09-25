# Arquitectura — JUST4INDEX

Estado vivo del diseño. Leyenda: ✅ hecho · 🚧 en curso · ⬜ pendiente.

## Visión

Dos pipelines que comparten el mismo índice local.

**Pipeline A — Búsqueda (Everything-like)**

✅ FSEvents (roots autorizados) → ✅ ingesta incremental (batch + debounce) → ✅ índice SQLite FTS5 →
✅ query async (prefix AND, bm25, filtros) → ✅ UI resultados keyboard-first (F2).

**Pipeline B — Organización inteligente**

✅ watcher origen (estabilidad de fichero + backlog) → ✅ análisis local (PDFKit / Vision OCR / regex;
«lite» si no hay texto) → ✅ clasificación (IA → reglas nombre/texto → extensión) →
✅ FilingPlanner (validación + clamps) → ✅ cola acotada (`FilingPipeline`, 4) →
✅ ejecución en taxonomía (executor con colisiones) → ✅ journal/undo + cuarentena.

## Módulos

| Módulo | Responsabilidad | Estado |
|---|---|---|
| `J4ICore` | Modelos y dominio: `Taxonomy`, `FilingProposal`, plantilla/saneado de nombres, `FilingPlanner`, reglas locales | ✅ F3/F4 |
| `J4IIndex` | Índice SQLite FTS5 (schema v2: cache + journal), crawler cooperativo, ingesta FSEvents, query API | ✅ F1 (+cache/journal) |
| `J4IDocs` | Ingesta: watcher con estabilidad, PDFKit, Vision OCR, txt/rtf/docx, hash, regex de metadatos | ✅ F3 |
| `J4IAI` | `DeepSeekClient` (JSON mode), `DeepSeekFilingAdvisor`, resolución de key | ✅ F4 (cap diario pendiente) |
| `J4IFiling` | `FilingExecutor` (mkdirs+move, colisiones, undo), `FilingCoordinator` (pipeline + journal), `FilingPipeline` (concurrencia acotada) | ✅ F5/F7 |
| `JUST4INDEX` | App SwiftUI: configuración inicial, buscador, actividad, cuarentena, registro (⌘L), explorador (⌘E), Ajustes (⌘A/⌘,) | ✅ F2/F3.0/F5/F6.1/F7/F7.1 |

## Esquema del índice (v2 — implementado)

- `roots(id, path, bookmark, last_event_id, crawl_state, progress)`
- `entries(id, root_id, path UNIQUE, parent_path, name, ext, is_dir, size, created_ts, modified_ts)`
- `entries_fts(name, path)` — tokenizer unicode61, `remove_diacritics 2`
- `doc_text(entry_id, text)` + `doc_text_fts(text)` — búsqueda por contenido (toggle)
- `analysis_cache(hash PK, profile_json, proposal_json, filed_path, updated_ts)` — cache de análisis y duplicados
- `ops_journal(id, ts, batch_id, src_path, dst_path, category_path, action, state, undone_ts)` — journal con undo

Reglas: WAL, transacciones por lotes, `optimize` periódico, completitud por root y reconciliación
tras `MustScanSubDirs`. La query se trocea en sub-tokens alfanuméricos (`token* AND token*`) para
no exponer sintaxis FTS5; el matching es insensible a acentos (`remove_diacritics 2`).

## Taxonomía seed

```text
~/JUST4INDEX/
├─ 01_Fiscal/{Facturas,Nominas,Impuestos,Recibos}
├─ 02_Banca/{Extractos,Inversiones,Prestamos}
├─ 03_Seguros/{Polizas,Recibos,Siniestros}
├─ 04_Salud/{Informes,Recetas}
├─ 05_Trabajo/{Contratos,Nominas,Formacion}
├─ 06_Educacion/{Cursos}
├─ 07_Vivienda/{Contratos,Suministros,Comunidad}
├─ 08_Vehiculos/{Documentacion,Seguros,Mantenimiento}
├─ 09_Identidad/{Documentos,Certificados}
├─ 10_Viajes/{Reservas,Billetes}
├─ 11_Hogar/{Manuales,Garantias}
├─ 12_Software/{Instaladores,Herramientas,Desarrollo,Redes}
├─ 13_Multimedia/{Fotos,Videos,Peliculas,Series,Documentales,Audio,Audiolibros,Musica}
├─ 14_Comprimidos/
├─ 15_Libros/
└─ 99_SinClasificar/
```

Las carpetas se crean durante la **configuración inicial** (primer arranque, esqueleto completo e idempotente);
el archivado crea subcarpetas adicionales solo si la taxonomía crece. Al arrancar, la app **sincroniza
categorías nuevas** en instalaciones existentes (p. ej. `12_Software/Redes` en F9.4).

## Contratos de producto

- La búsqueda nunca enumera el árbol: solo índice.
- La ingesta FSEvents mapea rutas con prefijo `/private` a la forma del root y procesa un borrado
  aunque la carpeta padre venga también en el lote.
- El archivado nunca borra: solo mueve; undo por lote e item.
- La IA no bloquea: sin key o sin red → reglas por nombre/texto → extensión (último recurso) → cuarentena si hay duda.
- El archivado es automático (decisión del usuario) con redes de seguridad: undo, cuarentena, pausa y modo simulación.
- La privacidad manda: solo texto truncado a DeepSeek (≤ 4000 chars), nunca archivos.

## Pipeline IA (patrón JUST4PICT adaptado)

```text
DocumentAnalyzer (local: hash + extracción + metadatos) → DocumentProfile
    ↓ (cache por hash en analysis_cache)
DeepSeekFilingAdvisor (JSON mode; opcional; por nombre si no hay texto) → FilingProposal cruda
    ↓ (o RulesFilingClassifier si IA off/error)
FilingPlanner.resolve() → FilingPlan validado (categoría ∈ taxonomía, nombre saneado, ≥0.5 o cuarentena)
    ↓
FilingExecutor (mkdirs + move, colisiones -1) + journal (undo) + doc_text al índice
```

## Dependencias

- Local: `APPS/JUST4FOLDERS` (productos `J4FFileSystem`, `J4FOps`) vía `.package(path:)`.
  Los library products se añadieron en su `Package.swift` (F0).
- Red (opcional): DeepSeek API (`https://api.deepseek.com`, `deepseek-flash`).
