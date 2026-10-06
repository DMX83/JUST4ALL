# docs/ — el sitio publicado de JUST4ALL

> Esta carpeta **es** el sitio web: GitHub Pages publica `docs/` de la rama `main` (es la única
> carpeta que admite además de la raíz del repositorio). Si renombras la carpeta, el sitio deja de
> desplegarse.

Sitio estático (sin dependencias externas, sin cookies, sin analítica) que se publica en
**https://app.amgprotech.com**. Es la única fuente de verdad de la web: las landings viven aquí.

## Estructura

| Ruta | Qué es |
|---|---|
| `index.html` | Portada de la marca: las seis apps de JUST4ALL, precios y FAQ |
| `just4folders/index.html` | Página de producto de JUST4FOLDERS (la estrella: escritura NTFS) |
| `legal/terminos.html` | Licencia de uso (EULA de familia) |
| `legal/privacidad.html` | Privacidad: sin telemetría, sin cookies, IA opcional |
| `legal/terceros.html` | Avisos y licencias de terceros (fuse-t, ntfs-3g, ffmpeg, Real-ESRGAN, PyMuPDF…) |
| `assets/site.css` · `assets/favicon.svg` | Estilos compartidos y favicon |
| `assets/og.png` · `assets/og-just4folders.png` | Tarjetas 1200×630 para compartir en redes (`og:image`) |
| `CNAME` · `robots.txt` · `sitemap.xml` · `.nojekyll` | Publicación y SEO |

Las cinco páginas declaran `<link rel="canonical">`, `og:url`, `og:image` (1200×630) y
`twitter:card`, siempre con el dominio final `https://app.amgprotech.com`. Las `og:image` son PNG
generados con la paleta de `assets/site.css`; si cambia el mensaje de marca hay que regenerarlas
(1200×630, fondo `#0b0d12`→`#171d2e`, acento `#4c8dff`).

## Ver en local

```bash
python3 -m http.server 8123 -d docs
# http://127.0.0.1:8123/
```

## Publicar con GitHub Pages (recomendado: gratis, HTTPS, sin servidor)

1. **Subir el sitio al repo** (Pages sirve una carpeta del repositorio):

   ```bash
   git add docs && git commit -m "docs: sitio de productos JUST4ALL" && git push origin main
   ```

2. **Activar Pages apuntando a `/docs`** (ya está hecho; solo hace falta si se desactiva), con la API de GitHub:

   ```bash
   gh api -X POST repos/DMX83/JUST4ALL/pages \
     -f 'source[branch]=main' -f 'source[path]=/docs'
   ```

   O a mano: *Settings → Pages → Source: Deploy from a branch → main → `/docs` → Save*.
   Estado actual: `gh api repos/DMX83/JUST4ALL/pages` → `source: /docs`, `status: built`.
   Ojo: como el dominio propio ya está configurado (fichero `CNAME`), la URL
   `https://dmx83.github.io/JUST4ALL/` responde **301 → http://app.amgprotech.com/**, así que para
   ver el sitio hay que arreglar el DNS (paso 3) o usar el servidor local.

3. **Dominio propio**: añadir en **Namecheap → Advanced DNS** un registro

   | Type | Host | Value | TTL |
   |---|---|---|---|
   | CNAME | `app` | `dmx83.github.io` | Automatic |

   No hace falta tocar la web actual de AMG ProTech (`www.amgprotech.com`): solo se añade este
   subdominio. Después, en *Settings → Pages → Custom domain* poner `app.amgprotech.com` (ya está en
   el fichero `CNAME`), esperar al certificado y marcar **Enforce HTTPS**.

   > **Aviso (estado 6-oct):** el registro creado apunta a `www.amgprotech.com.`, que es incorrecto
   > (deja el subdominio sirviendo la web vieja y bloquea el certificado). Debe ser exactamente
   > `dmx83.github.io`. Comprobación: `dig +short app.amgprotech.com` tiene que devolver las IPs de
   > GitHub Pages (`185.199.108.153`, `.109.153`, `.110.153`, `.111.153`) y **no** `185.209.230.42`.

## Alternativas y cuándo conviene cambiar

- **Cloudflare Pages / Netlify**: mismo mecanismo (CNAME), pero además dan **formularios** (lista de
  espera sin backend) y **funciones serverless**: cuando existan licencias, ahí se puede generar y
  validar claves con el webhook de Paddle sin montar un servidor.
- **El hosting actual de amgprotech.com** (openresty) también podría servir el subdominio subiendo
  esta carpeta, si preferís tenerlo todo en el mismo sitio.

## Pendientes antes de anunciarla

- [ ] **Checkout real**: hoy los botones de compra llevan a un correo (`hola@amgprotech.com`).
      Sustituir por los enlaces de Paddle o Lemon Squeezy.
- [ ] **Confirmar el buzón `hola@amgprotech.com`** (el dominio ya tiene *email forwarding* de
      Namecheap configurado: hay que crear/confirmar la regla).
- [ ] **Refrescar los Releases**: el último (`v0.1.4`, 2-oct) es anterior a la versión 2.3.19 de
      JUST4FOLDERS y va **sin firmar ni notarizar**.
- [ ] Versión en **inglés** del sitio. `og:image` y metadatos para compartir: hechos.
- [ ] Revisión legal del EULA antes de cobrar (hoy es un borrador publicado como versión 1.0).

> Nota de seguridad legal: Pages sirve **solo** la carpeta `docs/`, así que el repositorio (que incluye
> un binario `ffmpeg` GPL en `APPS/JUST4CONVERT/…`) **no** queda expuesto como web.
