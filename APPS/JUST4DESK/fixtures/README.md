# fixtures — JUST4DESK

Muestras locales para tests y QA. Los binarios no se commitean (ver `.gitignore` del repo);
esta carpeta documenta qué muestras se esperan y con qué reglas.

## Previstas (F3/F4)

- `pdf_texto.pdf` — PDF con capa de texto (extracción directa).
- `pdf_escaneado.pdf` — PDF sin capa de texto (requiere OCR local).
- `docx_basico.docx`, `txt_basico.txt`, `rtf_basico.rtf`
- `factura_luz_ES.pdf`, `nomina_ES.pdf`, `poliza_seguro_ES.pdf` — casos de clasificación (F4).

## Reglas

- Máximo ~2 MB por muestra.
- Datos personales anonimizados.
- Si una muestra no está presente, el test correspondiente debe hacer `skip`, nunca fallar.
