# G6 — Archivo en frío + informe semanal (evidencias)

**Fecha:** 25-sep-2026 (noche). **Suite:** 177 tests (176 ✅ + 1 skip, benchmark opt-in).

## Qué se implementó

### Archivo en frío (`90_Archivo`)
- La sugerencia **«Grandes y sin cambios en 6+ meses»** pasa de [Revelar] a **[Archivar en frío]**.
- Al confirmar, `FilingCoordinator.archiveCold` mueve cada fichero a
  `90_Archivo/<ruta relativa al root>` (estructura intacta) con:
  - journal `action=cold` y undo desde **Actividad** (el botón «Deshacer»);
  - la caché de análisis reapuntada al destino (`repointCachedFiledPath`) y el **texto
    extraído viaja con la entrada** → la búsqueda por contenido sigue funcionando en frío;
  - nunca borra; colisiones resueltas con sufijo `-1`.
- `DefaultTaxonomy.coldArchiveRelativePath = "90_Archivo"` (la carpeta se crea al arrancar).
- Los detectores (duplicados y «grandes») **excluyen** `90_Archivo` y `99_SinClasificar`.

### Informe semanal
- Botón **[Informe]** en la tarjeta Actividad de «Inicio» → hoja con el informe de 7 días
  (`WeeklyReport.build`): archivados, GB ordenados, deshechos, por revisar, top categorías,
  reglas promovidas y **tokens ahorrados** por conocimiento local.
- **Copiar** al portapapeles y **Exportar…** a Markdown (`just4desk-informe-YYYY-MM-dd.md`).

## Capturas

| Archivo | Qué muestra |
|---|---|
| `inicio.png` | «Inicio» con la sugerencia «Grandes y sin cambios» y su botón **[Archivar en frío]** |
| `confirmacion.png` | Diálogo de confirmación: «Se moverán 1 elemento(s) (2,74 GB) a «90_Archivo/…» conservando su ruta. Deshacible desde Actividad.» |
| `informe.png` | Hoja **Informe semanal** (captura de la ventana) con datos reales: 466 archivados · 17,62 GB · 27 reglas · ~4.825 tokens ahorrados |
| `informe-pantalla-completa.png` | La hoja Informe en contexto (pantalla completa) |

## Validación en vivo (sin simulación)

1. **Aplicar**: con el instalador real `Microsoft_Microsoft-365-Office-Installer.pkg` (2,74 GB) el
   flujo completo funcionó: journal `cold` → `applied`, fichero en
   `~/JUST4DESK/90_Archivo/12_Software/Instaladores/` (la subcarpeta relativa se recreó bajo
   `90_Archivo`).
2. **Deshacer**: desde «Actividad» → journal → `undone` y fichero **restaurado** en
   `~/JUST4DESK/12_Software/Instaladores/`.
3. **Informe**: hoja abierta y verificada con datos reales (periodo 18→25 sept).

> Nota QA: los botones SwiftUI **no exponen `title`** a System Events — se identifican por
> **`help` (AXDescription)** y se pulsan con `entire contents of window 1` + `click`. Durante la
> validación en vivo (usuario delante del Mac) los diálogos abiertos por la automatización fueron
> confirmados por el propio usuario ~3 s después: el ciclo humano real
> (abrir → confirmar → aplicar → deshacer) quedó así probado dos veces, con el fichero siempre
> restaurado al final.
