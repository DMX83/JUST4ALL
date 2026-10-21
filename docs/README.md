# docs/ — web pública de Just4Folders

Sitio estático (GitHub Pages) con la landing de Just4Folders y las páginas legales.

| Fichero | Contenido |
|---|---|
| `index.html` | Landing de Just4Folders |
| `legal/terminos.html` | Licencia de uso |
| `legal/privacidad.html` | Privacidad |
| `legal/terceros.html` | Licencias de terceros |
| `assets/` | CSS, marca e imágenes |
| `CNAME` | Dominio (`app.amgprotech.com`) |

## Publicar

El sitio se publica desde la rama `main` (carpeta `/docs`) con GitHub Pages.

```bash
git add docs && git commit -m "docs: sitio Just4Folders" && git push
```

Variables de GitHub Pages: `source: /docs`, CNAME `app.amgprotech.com`, HTTPS forzado.

## Reglas

- Sin enlaces de compra o donación dentro de la app; la web sí puede enlazar Ko-fi.
- Sin promesas de funciones que el sandbox no permite (NTFS, Terminal).
- Las capturas y textos deben corresponder a la versión publicada.
