# G7 — Búsqueda semántica local + Chat del archivo (evidencias)

**Fecha:** 26-sep-2026. **Suite:** 196 ejecutados (195 ✅ + 1 skip, benchmark opt-in).

## Qué se implementó (v1)

- **Expansión semántica de consultas** con embeddings de palabras en español de Apple (local):
  «sueldo» → «salario/nómina», «alquiler» → «arrendamiento/vivienda». El chip **Semántica** en
  «Buscar» (ON por defecto) añade esos aciertos como extras marcados «por significado» y, si la
  consulta estricta no encuentra nada, reintenta con una expresión OR (términos útiles + sinónimos).
- **Vectores por documento** (`NLContextualEmbedding` latin, 512d; tabla `embeddings`, esquema v4):
  rellenado en segundo plano al arrancar (1.261/1.261 en ~15 s) + lotes cortos tras cada búsqueda.
  Puntúan solo documentos **con texto** (`contentOnly`): en nombres sueltos el coseno era ruido.
- **Chat del archivo** (⇧⌘K o Accesos → Chat): recuperación 100 % local (léxico OR + sinónimos +
  vectores de contenido) → respuesta de DeepSeek con **citas [n]** clicables (revela el fichero en
  el Finder). Respeta interruptor/cap de IA y registra tokens. Privacidad: fragmentos ≤700
  caracteres (≤4.000 en total), nunca ficheros. **El contexto cita solo ficheros**: las carpetas
  se filtran de la recuperación (petición del usuario tras la primera demo).
- **Traspaso al reindexar** (`upsertEntries` carry-over): al recrearse una entrada con id nuevo ya
  no se pierden el texto ni el vector — sana la degradación histórica de la búsqueda por contenido
  (se detectaron 299 `doc_text` huérfanos de reindexados previos; re-extracción = G7.3).

## Capturas

| Archivo | Qué muestra |
|---|---|
| `buscar-sueldo.png` | «sueldo» (sin coincidencia literal) → resultados «por significado» (Salario/Nómina) |
| `chat-respuesta.png` | Chat tras el filtro: «¿Qué recibos de luz o gas tengo guardados?» → 5 citas, **todas ficheros** (Iberdrola Gas, INEM, facturas Cinesoft…) |
| `inicio.png` | Inicio con el acceso **Chat ⇧⌘K** |

## Validación en vivo

1. Backfill: «Semántica lista: 1261/1261 documentos vectorizados (ctx-latin-512)» en ~15 s.
2. Búsqueda: «sueldo» → 3 «Salario…xlsx» + «2026-08-01_PDL_Nomina–Agosto.xlsx» + carpetas «Nominas».
3. Chat: respuesta real citando `2026-07-15_Iberdrola…_Recibo-Iberdrola-Gas-2026-07-15.pdf` (fecha
   y ruta correctas). Primer intento citó carpetas «Recibos» → **corregido y re-verificado**: la
   nueva respuesta cita 5 ficheros y ninguna carpeta.
4. Contabilidad IA: llamada registrada con tokens reales (Ajustes → IA).

## Limitaciones conocidas / siguientes

- Vectores por nombre: ruido (cosenos ~0.93+ sin discriminación) → la expansión léxica es el
  caballo de trabajo; los vectores entran cuando hay texto (**G7.3**: re-extraer los textos
  huérfanos).
- QA: para teclear en campos SwiftUI vía accesibilidad hay que forzar `AXFocused` (los `keystroke`
  no bastan).
- **G7.2** pendiente: MCP para agentes (servidor local que expone búsqueda/lectura del archivo).
