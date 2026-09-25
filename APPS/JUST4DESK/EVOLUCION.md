# EVOLUCIÓN — JUST4DESK (análisis de mercado y siguiente generación)

> Fecha: 2026-09-25 · Autor: sesión de diseño de producto (a petición del usuario)
>
> Punto de partida del usuario: «si el objetivo es tener una aplicación que organice el entorno
> personal y de trabajo, no pienso que un buscador sea la pantalla principal; hay que pensar más
> allá». Este documento analiza el mercado real y propone la evolución.

---

## 1. Dónde está JUST4INDEX hoy

Tres capacidades ya construidas y funcionando con datos reales:

1. **Índice local** (FTS5 + FSEvents): nombre, ruta, subcadena y contenido. Rápido (< 40 ms típico).
2. **Archivado inteligente**: watchers multi-carpeta, análisis local (PDFKit/OCR), IA opcional
   (DeepSeek) con reglas y taxonomía en español, **journal + undo**, «sin clasificar», modo simulación.
3. **Aprendizaje local**: reglas promovidas por observación (≥3 muestras), caché de sugerencias,
   control de tokens/coste.

Es un **motor de organización** con la cara de un **buscador** (por herencia de «Everything»).
El diagnóstico: la pantalla principal cuenta la historia equivocada. La búsqueda es una
*capacidad*, no la identidad del producto.

---

## 2. Mapa del mercado (qué hace cada familia y qué nos enseña)

### A. Búsqueda instantánea — *Everything* (voidtools), HoudahSpot, Find Any File
- **Fuerte**: localizar por nombre al instante, recursos mínimos, resultados en vivo.
- **Débil**: es un **localizador pasivo**: no organiza, no entiende contenido, no recuerda nada.
- **Lección**: la búsqueda es *commodity* (y en macOS Spotlight ya está). Vale como capacidad,
  no como producto. Nosotros además indexamos **contenido** — eso es lo diferencial, no el nombre.

### B. Automatización por reglas — *Hazel* (Noodlesoft), File Juggler, Folder Actions
- **Fuerte**: potencia real (condiciones + acciones: mover, renombrar, etiquetar, subir…), fiabilidad,
  integración sistema (Shortcuts/AppleScript), App Sweep, papelera.
- **Débil**: **el usuario tiene que escribir y mantener las reglas**; pensarlo en condiciones/acciones;
  no entiende contenido; nada se aprende solo.
- **Lección**: el valor está en las reglas, pero exigir reglas al usuario es la barrera.
  JUST4INDEX ya genera reglas **por observación** → «Hazel que se escribe solo» es una historia
  potente si esas reglas se hacen **visibles y editables**.

### C. Launchers / command palettes — *Raycast*, Alfred
- **Fuerte**: una interfaz para todo (teclado primero, acciones contextuales ⌘K, extensiones,
  quicklinks, IA); presencia en **todo el sistema**, no una ventana que hay que abrir.
- **Lección**: el buscador debe ser un **overlay global** (atajo), y los resultados deben traer
  **acciones**, no solo «abrir». Además: menú de barra como presencia permanente.

### D. Gestores de conocimiento / documentos — *DEVONthink 4*, *Eagle*, Keep It, Paperless-ngx
- **DEVONthink 4**: bases de datos locales, grupos/etiquetas/**smart groups**, enlaces cruzados,
  **chat de IA sobre tus documentos**, smart rules con IA, MCP, versionado, local-first con sync.
- **Eagle**: gestor de recursos visuales: carpetas + etiquetas + **carpetas inteligentes**,
  acciones IA (etiquetar/renombrar), **duplicados**, preview al pasar el ratón, plugins, pago único.
- **Paperless-ngx** (servidor): carpeta de consumo → OCR → **metadatos** (corresponsal, tipo, etiquetas)
  con sugerencias ML; archivo inmutable; self-hosted.
- **Lección**: los «pro» esperan (a) **colecciones/vistas inteligentes** — organizar sin depender de
  dónde está el archivo; (b) **IA conversacional** sobre el propio archivo; (c) metadatos ricos;
  (d) todo local y con exportación. Nuestra taxonomía en disco es *durable* (ventaja), pero nos falta
  la capa de **vistas** y el **chat**.

### E. La ola nueva: «AI file organizers» — *Floxtop* ($19,99 único), TidyDesk, TidyFiles,
FilesMagicAI, Foldora, Declutter, renamer.ai, Sortio, VaultSort…
- **Común**: IA **on-device**, «limpia tus carpetas en un clic», entiende contenido (texto/imagen),
  **renombra** con nombres útiles, revisar-antes-de-mover, pago único barato, macOS 15+/M-Series.
- **Fuerte**: foco brutal en una tarea («Downloads sucios»), marketing claro, precio bajo.
- **Débil** (nuestra oportunidad):
  - Son **operaciones puntuales**: no hay índice persistente, ni búsqueda posterior, ni una
    taxonomía que evolucione contigo; ni memoria entre sesiones.
  - El undo es básico (un paso); no hay **journal completo** ni **«sin clasificar»** ni «nunca borrar».
  - No hay **bandeja de revisión** con aprendizaje; no hay reglas que se promocionan solas.
  - Un solo idioma de taxonomía fija (o descripciones de carpetas manuales).
- **Lección**: el mercado está validando «organización con IA local y revisable» **a 20 $**.
  JUST4INDEX ya tiene una versión **más profunda y más segura** de eso, pero con peor narración.

### F. Memoria ambiental — *screenpipe*, Limitless/Rewind
- **Fuerte**: «tu historial como contexto para la IA», agentes que actúan; todo local-first.
- **Lección**: la dirección «asistente que conoce tu entorno» es tendencia fuerte; el consumidor
  ya tolera esto si es local y controlable. Para nosotros: **no capturar pantalla** (fuera de foco),
  pero sí la idea de «**contexto que trabaja para ti**»: detectar, proponer, ejecutar con permiso.

### G. Limpieza / espacio — CleanMyMac, Gemini, DaisyDisk, czkawka
- **Lección**: «liberar X GB» y «eliminar duplicados» son **resultados que se pagan** y son
  perfectos como *sugerencias proactivas* (con reversibilidad absoluta: nosotros nunca borramos,
  movemos a «sin clasificar» o a una papelera propia con undo).

---

## 3. La evolución propuesta: de «buscador con extras» a «centro de control que ordena»

### 3.1 La nueva pantalla principal: **Inicio — «Tu Mac, en orden»**

```
┌──────────────────────────────────────────────────────────────────────────┐
│  J4I      ⌘K  Buscar o pedir una acción…                    🔔   ⏸  ⚙   │
├───────────────────────────────┬──────────────────────────────────────────┤
│  BANDEJA (lo que necesita     │  SUGERENCIAS (el mayordomo)              │
│  una decisión tuya)           │                                          │
│  • 7 en «sin clasificar»   Revisar  │  • 34 capturas sueltas en el Escritorio  │
│  • 12 duplicados (8,2 GB)     │    → 13_Multimedia/Capturas  [Aplicar]   │
│    Revisar/Reclamar           │  • «trading-2024» sin tocar desde enero  │
│  • 3 conflictos de nombre     │    → Proponer archivo en frío [Ver]      │
├───────────────────────────────┼──────────────────────────────────────────┤
│  ACTIVIDAD (lo que hizo la    │  ESPACIOS (organizar sin mover)          │
│  app — siempre con deshacer)  │  • Trading (128) · Fiscal 2026 (41) ·    │
│  hoy: 34 archivados · 1,2 GB  │    Trabajo (76)   [+ Nuevo espacio]      │
│  · 2 reglas nuevas   [↩︎]     │                                          │
└───────────────────────────────┴──────────────────────────────────────────┘
```

- El **omnibox (⌘K)** sustituye al «campo gigante»: busca *y* ofrece acciones («Archivar…»,
  «Mover a…», «Etiquetar», «Ver actividad», «Abrir «sin clasificar»»). El buscador «de verdad» (la vista
  actual con filtros y contenido) sigue existiendo: se abre desde el omnibox o con un atajo.
- La app **arranca mostrando estado y decisiones**, no un cursor vacío. En 5 segundos se entiende
  qué hace JUST4INDEX aunque nunca lo hayas usado.

> **Implementado (25-sep, G1)**: «Inicio» es la ventana principal (`HomeView`) con bandeja,
> actividad, estado y accesos; el omnibox ⌘K busca al instante (resultados bajo el campo, Enter
> abre el primero) y la búsqueda completa vive en la ventana «Buscar» (⌘F), compartiendo un único
> `SearchViewModel` con arranque idempotente.

### 3.2 Las cuatro capas nuevas (y por qué encajan con lo ya construido)

1. **Bandeja de decisiones** *(reusa: «sin clasificar» ⌘R, journal, reclassify)*
   Todo lo que pide intervención humana en un solo sitio: revisar, aceptar sugerencias en bloque,
   resolver conflictos. Es el corazón del modelo «apruebo → la app ejecuta → queda deshacible».

2. **Sugerencias proactivas** *(nuevo motor; reusa: SHA-256, perfilador, índice, journal)*
   Detectores baratos y explicables que se ejecutan en segundo plano (de madrugada o al cargar):
   - **Duplicados reales** por hash (ya calculamos SHA-256 al archivar) → agrupar y proponer quedarse
     con uno; mover el resto a «sin clasificar»/papelera propia (nunca borrar).
   - **Escritorio/Descargas sucios**: capturas, PDFs sueltos, instaladores ya usados.
   - **Candidatos a archivo «en frío»**: proyectos/carpetas sin tocar en N meses → proponer
     `90_Archivo/…` conservando estructura.
   - **Cajones mezclados** (ya sabemos perfilar un cajón) → proponer desglose.
   - **Grandes y olvidados** («>1 GB y sin abrir 6 meses») → candidato a external/archivo.
   Cada tarjeta: *explicación + vista previa + [Aplicar] [Ahora no] [Nunca más]*.
   Aceptar = opera con journal + undo (y enseña al conocimiento local).

3. **Reglas visibles y portables** *(reusa: LocalKnowledgeStore, FilingSkill)*
   Pantalla de primera clase «Reglas»: las aprendidas (extensión/token → categoría, con confianza
   y muestras), editables, creables a mano, borrables, y **exportables/importables** (portabilidad
   entre Macs). Esto convierte el aprendizaje invisible en **confianza vendible** («tu app aprende
   y tú lo ves»). Es el «Hazel sin escribir reglas» + el control del usuario.

4. **Espacios y colecciones** *(reusa: índice FTS; añade etiquetas)*
   Organizar **sin mover**: colecciones guardadas («Trading», «Fiscal 2026», «Trabajo») definidas
   por reglas/búsquedas/etiquetas. Enriquecimiento con **etiquetas Finder nativas** (opcional)
   para que sean visibles fuera de JUST4INDEX; nada de lock-in. El omnibox y Inicio las muestran.
   *(Fase posterior: búsqueda semántica local para «busca como…» y chat sobre el archivo.)*

### 3.3 Presencia en el sistema (del «todo está en una ventana» al «está donde lo necesitas»)

- **Menú de barra (N5 ya en el mapa)**: estado (archivando/pausado), contador de bandeja, acciones
  rápidas (pausar, abrir Inicio, revisar).
- **Atajo global** (⌥Espacio): omnibox flotante desde cualquier app.
- **Quick Action de Finder / arrastrar-y-soltar** sobre el icono o la ventana: «Enviar a JUST4INDEX».
- **Notificación discreta al terminar** un lote grande: «34 archivados · 8 dudosos → Revisar».
- **Informe semanal** (local, exportable): archivados, GB ordenados, reglas aprendidas, tokens
  ahorrados por conocimiento local. Refuerza valor percibido y da temas de conversación (marketing).

---

## 4. Roadmap propuesto (fases G — incrementales, sin romper lo actual)

| Fase | Qué | Por qué primero | Esfuerzo |
|------|-----|------------------|----------|
| **G1** ✅ | **Inicio / Centro de control** + omnibox (⌘K) + buscador como vista/overlay | Cambia la historia del producto sin añadir motores nuevos (todo existe ya) | Medio |
| **G2** | **Sugerencias proactivas v1**: duplicados (hash), capturas/Escritorio, grandes y olvidados | «Resultados que se pagan» (+ GB) con riesgo cero (undo) | Medio |
| **G3** | **Reglas visibles** (pantalla + export/import) | Confianza y control; explota lo ya aprendido (27 reglas reales ya) | Bajo-Medio |
| **G4** | **N5: menú de barra + atajo global + Quick Action Finder** | La app pasa de «ventana» a «presencia» (lo pide el mercado) | Bajo-Medio |
| **G5** | **Espacios/colecciones** (+ etiquetas Finder opcionales) | «Organizar sin mover»; encaja con Inicio y omnibox | Medio-Alto |
| **G6** | **Archivo en frío + informe semanal** | Consolida «mantenimiento continuo» del entorno | Bajo |
| **G7** | **Búsqueda semántica local + chat del archivo (MCP para agentes)** | Diferencial avanzado (DEVONthink 4/Eagle ya lo venden) | Alto |

**Recomendación de secuencia**: G1 → G3 → G2 → G4 → G5 → G6 → G7.
(G3 antes que G2 porque es más barato y multiplica la confianza en las sugerencias de G2.)

---

## 5. Posicionamiento y precio (lo que enseña la competencia)

- La ola «AI organizer» juega a **10–20 $ pago único**, one-trick (ordenar/renombrar).
- JUST4INDEX es un **sistema**: índice + archivado seguro + aprendizaje + revisión. Posicionamiento:
  **«el sistema operativo de tus archivos: ordena, recuerda y nunca borra»** — 39–49 € pago único
  (o 29 € lanzamiento), con la seguridad y el aprendizaje como ejes del mensaje.
- Diferenciadores que la competencia **no** tiene juntos:
  1. **Journal + undo real + «sin clasificar»** («nunca borra», reversible por lote).
  2. **Aprendizaje persistente y visible** (reglas que se promocionan solas).
  3. **Multi-entrada** (varias carpetas vigiladas, un solo destino organizado).
  4. **Buscador por contenido** integrado (no solo organiza: encuentras después).
  5. **Español de serie** y taxonomía editable; local-first de verdad (sin subir archivos).
  6. Control de coste (cap, tokens medidos) — transparencia que nadie más da.

---

## 6. Riesgos y guardrails de esta evolución

- **No diluir**: nada de notas, calendarios o correo. El foco es *archivos y su organización*.
- Las sugerencias proactivas deben ser **baratas** (hash incremental, límites por escaneo) y
  **explicables** («por qué te propongo esto»); jamás ejecutarse sin aprobación la primera vez.
- Mantener los guardrails actuales: nunca borrar, simulación, pausa, undo por lote.
- La portada no puede ralentizar el arranque: el índice ya está en marcha; Inicio lee de él.

## 7. Decisiones abiertas (para el usuario)

1. ¿Inicio como **ventana principal** (recomendado) o como **pestaña** dentro del buscador actual?
2. Sugerencias proactivas: ¿**aprobar-para-ejecutar** (recomendado) o ejecutar con undo inmediato?
3. Espacios/colecciones con **etiquetas Finder nativas**: ¿sí (visibles en Finder, sin lock-in) o
   solo internas?
4. Precio/posicionamiento: ¿39–49 € único (sistema) o tier gratis + Pro (sugerencias/colecciones)?

---

## 8. Renombrado (25-sep) — «INDEX» ya no cuenta la historia

La app ha crecido más allá del índice: el nombre `JUST4INDEX` ancla la identidad al buscador
(el problema original de percepción). La familia JUST4ALL usa `JUST4` + una palabra que dice
lo que el producto *es o hace*: `JUST4CONVERT`, `JUST4FOLDERS`, `JUST4PDF`, `JUST4PICT`.

### Criterios
- Una sola palabra tras `JUST4`, corta (4–6 letras), pronunciable en español e inglés.
- Que cuente la nueva historia: **ordena tu entorno · recuerda · nunca borra**.
- Sin choque con `FOLDERS` (motor de operaciones) ni con `ALL` (hub); evitar «Index/Buscar/Search».
- Verificado por **RDAP de Verisign** (25-sep): `just4all.com` ya registrado (hub); los candidatos
  `just4order.com`, `just4desk.com`, `just4keep.com`, `just4nest.com`, `just4casa.com`,
  `just4butler.com`, `just4sort.com`, `just4tidy.com` están **libres** (404). También `just4pdf.com`.
  *(Pendiente antes de decidir: comprobación de marca en OEPM/USPTO, no hecha.)*

### Candidatos

| Nombre | Idea | A favor | En contra |
|--------|------|---------|-----------|
| **JUST4ORDER** | «el orden» | Cuenta exactamente la historia nueva; serio; coloquial («just for order»); «orden» funciona en ES/EN | 5 letras; «order» también evoca pedidos |
| **JUST4DESK** | «tu escritorio» | Muy corto e icónico; desk/escritorio encaja con «tu Mac en orden» | Puede sonar a accesorio de escritorio |
| **JUST4KEEP** | «guarda y encuentra» | Refuerza el diferencial (memoria + nunca borra); keeper de tu archivo | Pasivo: no dice «organizar» |
| **JUST4NEST** | «cada cosa en su nido» | Con encanto, memorable, neutro | «just for nest» menos natural |
| **JUST4CASA** | «la casa de tus archivos» | Sabor español del mercado objetivo | Mezcla de idiomas en la marca |
| **JUST4BUTLER** | «el mayordomo digital» | Encarna la evolución proactiva (sugerencias) | Más largo; suena a servicio |

Descartados: `JUST4SORT` (estrecho; olor a Sortio), `JUST4TIDY` (colisiona con TidyDesk/TidyFiles),
`JUST4HOME` (smart home), `JUST4VAULT` (seguridad), `JUST4SPACE` (Spaces de macOS), `JUST4HUB` (=ALL).

**Decisión del usuario (25-sep)**: **JUST4DESK** — «veo este proyecto como un escritorio
inteligente: gestionar tu documentación de forma más inteligente, rápida y segura». Convención
aplicada: **JUST4DESK** = nombre público **y** identificador técnico (un solo token: carpeta,
binario, dominio de preferencias, App Support, logs) · **J4DESK** = marca corta informal
(coherente con el sello «J4» del repo). Dominios (RDAP 25-sep): `just4desk.com` **libre** ✅,
`j4desk.com` **libre** ✅ (`j4d.com` ocupado ❌).

### Plan de migración (medido en el repo)

- **Impacto**: 53 ficheros mencionan `JUST4INDEX` (la mayoría dentro de `APPS/JUST4INDEX`).
  Fuera: `agent.md`, `README.md`, `scripts/{release,sync_local_dmgs,clean_artifacts}.sh`,
  `.github/skills/just4index/`, `Sources/JUST4ALL/SubAppModel.swift` (catálogo del hub),
  `APPS/JUST4FOLDERS/Package.swift` (comentario).
- **Datos del usuario a migrar** (irrenunciable):
  - UserDefaults dominio `JUST4INDEX` → nuevo dominio (claves `just4index.filing.*` y `just4index.ai.*`;
    incl. contadores reales y cap 400).
  - `~/Library/Application Support/JUST4INDEX/` → `…/<NOMBRE>/` (`index.sqlite`, `knowledge.json`
    con 27 reglas, `ai-suggestions.json`) — **movimiento con copia de seguridad**.
  - `~/Library/Logs/JUST4INDEX` → nuevo (arrancar limpio; se conserva el histórico).
  - **Carpeta destino `~/JUST4INDEX`** (~32 GB ya organizados): renombrada a `~/JUST4DESK`
    (25-sep, noche) en sitio — sin copiar datos — con reemplazo de prefijo en preferencias,
    índice (`roots`/`entries`/`entries_fts`), journal y caché.
- **Plan A (recomendado) — renombrar en sitio**: carpeta `APPS/JUST4INDEX` → `APPS/<NOMBRE>`,
  textos de UI/About/hub/scripts/skill, + **shim de primera ejecución** que copia UserDefaults y mueve
  Application Support (idempotente y con backup). Los módulos internos (`J4ICore`, `J4IIndex`…)
  **conservan su nombre** en esta fase (invisible al usuario) para reducir riesgo; su renombrado,
  si se quiere, va en una fase aparte. Esfuerzo: mecánico + 1–2 h de shim + suite (141) en verde.
- **Plan B — proyecto nuevo**: `APPS/<NOMBRE>` desde cero copiando `Sources/`/`Tests/` con versión
  1.0 limpia. Más churn (workspace, Package, run scripts, historial) y la migración de datos es
  **idéntica**. Solo si se quiere reset total de identidad/versionado.
- **Orden sugerido**: primero el renombrado **de cara al público** (UI, hub, docs, DMG) — barato y
  visible; después el **técnico** (carpeta, dominio, rutas) con migración probada.
- **Estado (25-sep)**: **ejecutado** (Plan A) con `RenameMigration` no destructiva y suite 144 en
  verde. Incidencia del despliegue resuelta: el asistente de primer arranque apareció (config
  cacheada antes de migrar) y se completó por error creando un esqueleto **vacío** en
  `~/JUST4DESK`; **0 ficheros afectados** — esqueleto a la Papelera, configuración restaurada y
  arranque corregido con relectura. **Carpeta de datos**: renombrada a `~/JUST4DESK` (25-sep,
  noche) y limpiados los restos: root fantasma del esqueleto eliminado del índice (57 entradas),
  contador de Inicio alineado con «Por revisar» (ocultos omitidos) y entitlements renombrados.

