# SKILL_IA — Política del agente de clasificación (propuesta)

> Petición del usuario (2026-09-24): «debe ir dentro de la app cierta configuración de **skill**
> para que manejen al agente de IA como debe ser, para que no haya malas interpretaciones».
>
> **Decisión del usuario (misma sesión, vinculante):** «como el skill es de la misma app,
> **no debe modificarse**, solo debemos afinarla **nosotros** para que haga lo que queremos bien
> siempre». ⇒ La skill es un **artefacto interno y versionado** del binario: sin editor para el
> usuario; la afinamos en el repositorio y cada mala clasificación real se convierte en un
> **caso curado + test de regresión**. Estado: **skill v5 (F10.0 · 2026-09-24) — 17 casos curados**.

## 1. Por qué (evidencia real del 2026-09-24)

- «8 Programas ERP…» (carpeta con un vídeo mkv + su descripción .txt) acabó en `01_Fiscal/Facturas`:
  una mención de «factura» en el texto de **un** documento interno decidió por todo el lote.
  → corregido a mano a `13_Multimedia/Videos`.
- «Documents» (cajón de sastre con PDFs variados) acabó en `01_Fiscal/Nominas` por un PDF que
  mencionaba «nómina». → corregido a mano a `99_SinClasificar`.
- Ya aplicado en F8.3: para **carpetas-unidad** el texto interno NO decide (solo nombre +
  extensión dominante, con desempate vídeo > audio > imagen). Pero las *instrucciones de la IA*
  siguen **en código**: hoy no hay forma de decirle «una película va a Películas», «esto es
  trabajo/empresa/ocio», «si dudas, cuarentena» sin tocar Swift.

## 2. Dos «skills» distintos (no confundir)

1. **Skill del agente de desarrollo** — ya existe: `.github/skills/just4index/SKILL.md`. Gobierna
   cómo el agente de código trabaja en este repo (ciclo, guardrails). No cambia aquí.
2. **Skill/política del agente de clasificación** — lo que falta: cómo decide el archivador
   DENTRO de la app. Es el objeto de este documento.

## 3. Principios de diseño

- **Mecánica ≠ política.** El código garantiza las invariantes (mover/journal/undo, colisiones
  `-1`, nunca borrar, validación); la skill (curada por nosotros) decide «qué va dónde».
- **La skill es un artefacto interno del equipo**, versionada con el binario (`FilingSkill.version`);
  el usuario recibe resultados (y el registro), no knobs que configurar.
- **Antídoto contra malas interpretaciones = capas**, no solo un buen prompt:
  instrucciones claras + ejemplos reales + validación determinista + dudas → cuarentena.
- **La IA nunca decide sola en firme**: propone; `FilingPlanner` valida (categoría ∈ taxonomía,
  confianza ≥ umbral) y todo queda en el journal con la **versión de política** usada.

## 4. La skill (qué contiene) — interna, sin editor

Vive en `Sources/J4ICore/FilingSkill.swift` (código + casos; se revisa por PR como el resto):

| Campo | Para qué |
|---|---|
| `version` | Sube al tocar instrucciones o casos; se registra al arrancar («Skill de clasificación vN») |
| `assistantInstructions` | Criterio curado en español: carpeta≠documento, vocabulario del usuario (audiolibro→Audiolibros; documental→Documentales; película→Peliculas; serie→Series; curso→06_Educacion/Cursos; portable→Herramientas), **familias de extensión** (red: `.rsc`/`.ovpn`/`.pcap`/`.backup`/`.conf`/`.cfg` → `12_Software/Redes`; código: `.py`/`.sh`/`.ps1`/`.sql`/`.js`… → `12_Software/Desarrollo`), **estrategia de carpeta** (`mode`: entera vs desglosar), dudas→99 |
| `curatedCases[]` | Casos **reales** con destino esperado (`nil` = cuarentena): son a la vez **few-shot** para la IA y **tests de regresión** (`FilingSkillCasesTests`) |
| Reglas locales | `RulesFilingClassifier` (nombre → extensión); la skill documenta y fija su comportamiento esperado |
| Umbral | 0.5 en `FilingPlanner` (fijo; moverlo sería decisión de producto, no del usuario) |

Sin archivo de usuario y **sin «editor de reglas»**: lo que se afina se hace en el repo y llega con
la siguiente versión de la app.

## 5. Cómo entra en el prompt (plantilla)

- **Sistema**: `FilingSkill.assistantInstructions` (criterio curado) + reglas duras:
  · una sola categoría permitida (exacta); · dudas → `99_SinClasificar`;
  · **carpeta ≠ documento suelto**: para carpetas pesan el nombre y el tipo dominante; el texto
  interno es señal débil; · no inventar categorías; · no proponer rutas.
- **Contexto**: taxonomía permitida + `examples` (correcciones) + la unidad (kind: file|folder,
  nombre, tamaño, tipos, muestras, texto truncado según `privacy`).
- **Salida**: JSON con schema FIJO (en código, no editable): el parser no se negocia.

## 6. Arquitectura (implementada)

- `J4ICore`: **`FilingSkill`** — `version`, `assistantInstructions` y `curatedCases`
  (con `fewShotLines` para el prompt); junto a `RulesFilingClassifier`/`FilingPlanner` (intactos).
- `J4IAI`: `DeepSeekFilingAdvisor.systemPrompt` se compone desde la skill + contrato JSON fijo;
  `userPrompt` añade los casos curados como few-shot y distingue carpeta («unidad completa») de fichero.
- `JUST4INDEX`: al configurar el coordinador se registra «Skill de clasificación vN — N caso(s) curado(s)».

## 7. Afinado continuo (nuestro proceso, no UI del usuario)

1. Fuente de verdad de errores: el registro + journal (movimientos manuales ⌘R/Explorador y undos).
2. Cada mala clasificación real se revisa y se convierte en: regla (si es determinista) y/o
   **caso curado** en `FilingSkill` + test de regresión — nunca vuelve a fallar sin avisar.
3. Los cambios suben `FilingSkill.version` y se documentan (CHANGELOG/MEMORY): la skill viaja
   versionada con el binario.

## 8. Fases

- **F9.0 — Skill interna versionada — ✅ implementada (2026-09-24)**: `FilingSkill` (instrucciones +
  12 casos curados) · prompt del asesor construido desde la skill (+ few-shot) · versión registrada
  al arrancar · tests de regresión sobre los casos curados.
- **F9.1 — Ampliación continua**: cada hallazgo real añade casos/reglas y sube la versión.
  *Criterio*: un caso nuevo rojo ⇒ se arregla y queda verde para siempre.
- **F9.2 — Taxonomía fina — ✅ implementada (2026-09-24)**: `Peliculas`, `Series`, `Documentales`,
  `Audiolibros`, `Musica`, `06_Educacion/Cursos`, `15_Libros`; skill v2 con 14 casos curados.
  Los contextos trabajo/empresa/ocio quedan para la capa IA (pendiente 2).
- **F9.3 — Reevaluación asistida — ✅ implementada (2026-09-24, N2)**: «Reevaluar con IA» en ⌘R
  sobre la cuarentena (ficheros y carpetas).
- **F9.4 — Catálogo de extensiones técnicas — ✅ implementada (2026-09-24)**: pregunta del usuario
  («¿puede la IA clasificar por extensión?», caso `.rsc` de MikroTik); skill v4 con familias de
  extensión (red/código) + espejo en reglas locales + 3 casos curados; nueva `12_Software/Redes`.
  Sin extraer texto de scripts (credenciales).
- **F10.0 — Desglose de carpetas-cajón — ✅ implementada (2026-09-24)**: campo `mode`
  («folder»/«split») en el contrato; la IA decide entera (nombres relacionados, portable, curso,
  serie, álbum) o desglosada (cajón heterogéneo); pipeline automático con barandillas (confianza
  ≥0,6 · ≤500 ficheros · profundidad ≤4 · lote único de undo) + acción manual en «Por revisar».
- **F12.0 — Conocimiento local — ✅ implementada (2026-09-25)**: la app resume cada decisión de la
  IA y cada corrección del usuario en observaciones por característica (extensión de fichero;
  palabras del nombre de carpeta) y promueve reglas locales (≥3 · ≥75 % · conf media ≥0,7) que
  clasifican **sin llamar a la IA** — la skill marca el criterio; el conocimiento aprende del uso.

## 9. Alternativas descartadas

- **Prompt solo en código** (hoy): el usuario no puede corregir interpretaciones sin un desarrollo.
- **Agente con herramientas** (leer archivos, navegar): potencia innecesaria y más riesgo; la unidad
  ya se resume en local (`FolderProfiler`).
- **YAML/frontmatter**: dependencia extra; JSON + campos de texto cubre el caso.

## 10. Decisiones resueltas (2026-09-24)

1. **Sin archivo de usuario**: la skill es código interno versionado (decisión del usuario).
2. **La IA solo elige entre categorías existentes**; proponer categorías nuevas implicaría cambiar
   la taxonomía (decisión de producto, fuera de la IA).
3. Privacidad: se mantiene el envío de **texto truncado (≤4000 chars)** solo si hay clave; la skill
   nunca envía rutas completas.

## Referencias

- Mapa de mejoras: `MEJORAS.md` (bloque «Objetivo maestro» y punto «Reglas aprendidas»).
- Evidencia/correcciones de hoy: `MEMORY.md` (hito F8.3) · `CHANGELOG.md` (F8.3).
