# G2 (sugerencias proactivas v1) — capturas de validación

- `inicio.png`: tarjeta «Sugerencias» a ancho completo en «Inicio» — capturas sueltas (41 · 82,4 MB)
  y grandes y olvidados (1 · 2,74 GB) pendientes de decisión.

Nota: la sugerencia de **duplicados** no aparece en la captura porque el usuario ya la había
aplicado minutos antes: el log registra «Duplicados: 4 a la Papelera (25,1 MB)» con verificación
por hash previa — la tarjeta se limpia sola cuando la situación se resuelve.

Detectores v1:

- **Duplicados**: siguen en las entradas y coinciden en tamaño con el archivo (≥1 MB); al aplicar,
  hash (misma semántica que la ingesta) → Papelera reversible.
- **Capturas sueltas**: entradas + Escritorio → [Archivar] con journal/undo hacia el destino nuevo
  `13_Multimedia/Capturas`.
- **Grandes y olvidados**: ≥1 GB sin cambios desde hace 180 días → [Revelar] (archivo en frío: G6).

Silencios: «Ahora no» (7 días) / «Nunca más» (`just4desk.suggestions.*`). Ver CHANGELOG/MEMORY
(25-sep, noche).
