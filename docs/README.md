# docs/ — el sitio publicado de JUST4ALL

> Esta carpeta **es** el sitio web y vive en el **repositorio privado** (`DMX83/JUST4ALL-SRC`).
> Se publica con [`scripts/publish_site.sh`](../scripts/publish_site.sh), que copia `docs/` al
> **repositorio público de distribución** (`DMX83/JUST4ALL`), donde GitHub Pages sirve `docs/` de la
> rama `main` (es la única carpeta que admite además de la raíz). Si renombras la carpeta, el sitio
> deja de desplegarse.

Sitio estático (sin dependencias externas, sin cookies, sin analítica) que se publica en
**https://app.amgprotech.com**. Es la única fuente de verdad de la web: las landings viven aquí.

## Dos repositorios (importante)

| Repositorio | Visibilidad | Contenido |
|---|---|---|
| `DMX83/JUST4ALL-SRC` | **privado** | Todo el código fuente (`APPS/`, `Sources/`, `PACKAGES/`, `docs/`, scripts) |
| `DMX83/JUST4ALL` | **público** | Solo `docs/` (la web) y los Releases con los DMG + `SHA256SUMS.txt` |

- El repositorio público **no contiene código**: se reescribió su `main` con un commit de distribución
  (`README.md` + `docs/`) y las etiquetas antiguas que apuntaban a commits con código se eliminaron.
  Las etiquetas `v0.1.4`, `v0.1.5` y `v0.1.6` apuntan al commit de distribución, y cada una lleva sus
  DMGs publicados como assets del release.
- La app hub descarga de `DMX83/JUST4ALL` (nombre sin cambios), así que **no hay que recompilarla** al
  publicar versiones nuevas: basta con subir los DMG al release.
- Si en algún momento se necesita purgar los objetos antiguos que GitHub conserva sin referencia,
  hay que pedir a *GitHub Support* un `git gc` del repositorio.

## Estructura

| Ruta | Qué es |
|---|---|
| `index.html` | Portada de la marca: las seis apps de JUST4ALL, precios y FAQ |
| `just4folders/index.html` | Página de producto de JUST4FOLDERS (la estrella: escritura NTFS) |
| `legal/terminos.html` | Licencia de uso (EULA de familia) |
| `legal/privacidad.html` | Privacidad: sin telemetría, sin cookies, IA opcional |
| `legal/terceros.html` | Avisos y licencias de terceros (fuse-t, ntfs-3g, ffmpeg, Real-ESRGAN, PyMuPDF…) |
| `assets/site.css` · `assets/favicon.svg` | Estilos compartidos y favicon |
| `assets/logo.svg` · `assets/wordmark.svg` | Lockup y logotipo en color fijo, para usar con `<img>` |
| `assets/og.png` · `assets/og-just4folders.png` | Tarjetas 1200×630 para compartir en redes (`og:image`) |
| `assets/brand/` | Maestros SVG de la marca y lámina de los cinco estilos (ver [`BRAND.md`](../BRAND.md)) |
| `CNAME` · `robots.txt` · `sitemap.xml` · `.nojekyll` | Publicación y SEO |

Las cinco páginas declaran `<link rel="canonical">`, `og:url`, `og:image` (1200×630) y
`twitter:card`, siempre con el dominio final `https://app.amgprotech.com`. Las `og:image` son PNG y el favicon,
el logotipo y el lockup salen de los maestros SVG: todo se regenera de una vez con
`python3 scripts/make_brand_assets.py` (1200×630, fondo `#0b0d12`→`#171d2e`, acento `#4c8dff`). Los
maestros y las reglas están en [`BRAND.md`](../BRAND.md).

## Ver en local

```bash
python3 -m http.server 8123 -d docs
# http://127.0.0.1:8123/
```

## Publicar con GitHub Pages (recomendado: gratis, HTTPS, sin servidor)

1. **Publicar la web** (desde el repositorio privado, sin tocar `origin`):

   ```bash
   ./scripts/publish_site.sh          # copia docs/ al repo público y hace commit + push
   ```

   El script clona el repositorio público en una carpeta temporal, reemplaza `docs/` y hace `push` a
   `main`. Como el repositorio público no tiene la historia del privado, **nunca hagas
   `git push` del repo privado al público**: solo el script publica allí.

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

   > **Resuelto (7-oct):** con el DNS ya correcto el certificado seguía sin emitirse
   > (`https_certificate: null`). El remedy que funcionó fue **retirar y volver a poner el dominio**
   > para forzar la emisión:
   >
   > ```bash
   > gh api -X PUT repos/DMX83/JUST4ALL/pages -f cname=""          # quitar
   > gh api -X PUT repos/DMX83/JUST4ALL/pages -f cname="app.amgprotech.com"
   > gh api -X PUT repos/DMX83/JUST4ALL/pages -F https_enforced=true
   > ```
   >
   > Queda aprobado hasta 2027-01-04, con **Enforce HTTPS** activo (HTTP responde 301 al HTTPS). Si
   > algún día vuelve a caducar o a quedarse en `null`, repetir estos tres comandos antes de abrir
   > incidencia: los CAA del dominio permiten digicert/letsencrypt/sectigo, así que no hay nada que
   > bloquee la emisión.

## Alternativas y cuándo conviene cambiar

- **Cloudflare Pages / Netlify**: mismo mecanismo (CNAME), pero además dan **formularios** (lista de
  espera sin backend) y **funciones serverless**: cuando existan licencias, ahí se puede generar y
  validar claves con el webhook de Paddle sin montar un servidor.
- **El hosting actual de amgprotech.com** (openresty) también podría servir el subdominio subiendo
  esta carpeta, si preferís tenerlo todo en el mismo sitio.

## Pendientes antes de anunciarla

- [ ] **Cuenta de donativos**: hoy el botón «Invítame a un café» apunta a `https://ko-fi.com/amgprotech`
      (marcador). Crear la cuenta en Ko-fi (o Buy Me a Coffee / GitHub Sponsors) y sustituir la URL en
      `index.html` (`sección #apoyar`) y en `legal/privacidad.html` si cambia de plataforma.
- [ ] **Checkout y precios**: hoy la web **no muestra precios ni botones de compra** (decisión 6-oct:
      nada que no se pueda cobrar). Cuando existan cuenta de cobro y licencia comercial del driver NTFS,
      volver a poner los precios y los enlaces de Paddle/Lemon Squeezy donde estuvo la sección
      `#apoyar`.
- [ ] **Confirmar el buzón `hola@amgprotech.com`** (el dominio ya tiene *email forwarding* de
      Namecheap configurado: hay que crear/confirmar la regla).
- [x] **Refrescar los Releases** (8-oct-2026): el último es `v0.1.6` y lleva las siete apps al día
      (JUST4FOLDERS 2.4.0, JUST4PDF 0.3.0, JUST4DESK/JUST4PICT/JUST4CONVERT 0.2.0, JUST4LIFE 1.0.0 y
      el lanzador 0.1.6) + `SHA256SUMS.txt`. Sigue **sin firmar ni notarizar** mientras no haya
      licencia de Apple.
- [ ] Versión en **inglés** del sitio. `og:image` y metadatos para compartir: hechos.
- [ ] Revisión legal del EULA antes de cobrar (hoy es un borrador publicado como versión 1.0).

> Nota de seguridad legal: Pages sirve **solo** la carpeta `docs/`, así que el repositorio (que incluye
> un binario `ffmpeg` GPL en `APPS/JUST4CONVERT/…`) **no** queda expuesto como web.
