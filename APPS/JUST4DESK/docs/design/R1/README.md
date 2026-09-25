# R1 (limpieza) — capturas de validación

Evidencia del renombrado de la carpeta de datos a `~/JUST4DESK` (25-sep, noche):

- `inicio.png`: «Inicio» con **Destino ~/JUST4DESK**, bandeja **«Nada por revisar»** (el
  `.DS_Store` ya no cuenta como pendiente) y **1.632 entradas** (sin el root fantasma del
  esqueleto accidental).
- `por-revisar.png`: ventana «Por revisar» vacía con `Sin clasificar: ~/JUST4DESK/99_SinClasificar`.

Contexto: el contador de la bandeja y la lista de «Por revisar» comparten ahora
`QuarantineListing` (J4ICore), y el índice perdió el root fantasma `~/JUST4DESK`
(57 entradas) que quedó del esqueleto creado por error antes del `mv` real.
Ver CHANGELOG/MEMORY (25-sep, noche).
