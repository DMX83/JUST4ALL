# Auditoría de DMGs y artefactos — 2-oct-2026

Punto de partida: «esos .dmg no tienen las últimas versiones». Revisado todo el tren de
empaquetado (hub + 6 subapps): scripts, versiones grabadas en cada artefacto, lo que hay en
disco y lo que está publicado en GitHub Releases (que es de donde descarga el hub).

## 1) Lo que se encontró

### 1.1 El DMG se construía desde un `.app` viejo (el fallo grande)

Los cuatro scripts que usan `xcodebuild` (`JUST4FOLDERS`, `JUST4DESK`, `JUST4PICT`,
`JUST4CONVERT`) hacían:

```sh
APP_PATH=$(find "$DERIVED_DIR" -name "$APP_NAME.app" -type d | head -n 1)
if [ -z "$APP_PATH" ]; then   # sólo si NO había ningún .app
   ... montar el bundle desde el binario recién compilado ...
fi
```

`xcodebuild` sobre un paquete SwiftPM deja el **binario**, no el `.app`. Así que en cuanto
quedaba un `.app` de una compilación anterior, el script lo daba por bueno y empaquetaba
**ése**. Y como justo después le ponía el sello de fecha de hoy, el resultado era peor que un
DMG viejo: un DMG que **decía** ser de hoy.

Evidencia recogida (mtime del bundle frente a la fecha del sello):

| App | `.app` empaquetado | sello grabado |
|---|---|---|
| JUST4FOLDERS | 9-mar-2026 | hoy |
| JUST4DESK | 28-sep-2026 | hoy |

**Arreglado**: los cuatro scripts rehacen el bundle siempre desde el binario recién
compilado (`rm -rf` del bundle y `cp` del binario que acaba de producir la compilación).
`LIFEOS` ya lo hacía bien (usa `swift build` + `codesign`), y el hub también (`swift build`).

### 1.2 La versión no la tenía cada app, la tenía el hub

Todas las apps cargan `scripts/app_env.sh`, que leía `MARKETING_VERSION` **del `project.yml`
del hub**. Resultado: **todo** se empaquetaba como `0.1.0`, incluida la `v2.3.15` de
JUST4FOLDERS, que hasta hoy sólo existía en la prosa del README/TODO/QA. Consecuencia de
fondo: el hub compara «instalada vs publicada» para ofrecer **Actualizar**, y con `0.1.0` en
ambos lados nunca podía ofrecer nada.

**Arreglado**: existe `APPS/<App>/VERSION` y manda sobre la del hub (`app_env.sh` deduce la
app de `PROJECT_ROOT`, así que no hay que tocar los 6 scripts). `JUST4FOLDERS` se sella ya
como **2.3.15**.

### 1.3 `sync_local_dmgs.sh` se olvidaba de JUST4FOLDERS y mentía en los nombres

- No incluía JUST4FOLDERS: era imposible preparar su asset.
- Ponia `$SUITE_VERSION` (la del hub) a las seis: los assets se llamaban igual que hace meses.
- No generaba `SHA256SUMS.txt`, y sin ese fichero **el hub no descarga** (verifica el hash
  antes de abrir).

**Arreglado**: incluye las 6 apps, nombra cada asset con la versión real de su app
(`JUST4FOLDERS-2.3.15.dmg`) y genera `SHA256SUMS.txt`.

### 1.4 El canal de descarga del hub está roto desde marzo

Lo publicado en GitHub Releases:

| Release | Fecha | Assets |
|---|---|---|
| `v0.1.0` | 15-feb | `JUST4CONVERT-0.1.0.dmg` (349 KB), `JUST4PDF-0.1.0.dmg` (80 MB), `JUST4PICT-0.1.0.dmg` (386 KB), `SHA256SUMS.txt` |
| `v0.1.1` | 16-feb | `JUST4ALL.dmg`, `JUST4CONVERT.dmg`, `JUST4PDF.dmg` (sin versión en el nombre) |
| `v0.1.2` | 16-feb | `JUST4CONVERT.dmg` |
| `v0.1.3` | 22-mar | `JUST4CONVERT-0.1.0.dmg`, `JUST4PDF-0.1.0.dmg`, `JUST4PICT-0.1.0.dmg`, `SHA256SUMS.txt` |

- El hub pide el tag **fijado** `v0.1.0` (el más viejo) con nombre `<APP>-0.1.0.dmg`.
- **Nunca se publicaron JUST4FOLDERS, JUST4DESK ni LIFEOS** → su botón «Descargar» sale
  deshabilitado (`currentDownloadAsset` devuelve nil si no hay asset).
- Los nombres sin versión de `v0.1.1`/`v0.1.2` los ignora `ReleaseStore` (exige
  `<PREFIX>-<semver>.dmg`), así que lo mejor que encuentra para CONVERT es el de `v0.1.0`.
- Ese `JUST4CONVERT-0.1.0.dmg` de 349 KB es sospechoso (el real pesa 25 MB): apunta a un
  artefacto vacío o de prueba.

### 1.5 Artefactos sueltos y obsoletos en `dist/`

`dist/JUST4PDF.dmg` (9-mar), `dist/JUST4CONVERT.dmg` (16-feb) y `dist/JUST4FOLDERS.dmg`
(9-mar) eran copias viejas de apps cuyo sitio natural es `APPS/<app>/dist/`. **Apartados** a
`dist/_obsoletos-20261002/` (nada borrado).

## 2) Lo que se reconstruyó (todo hoy, 2-oct-2026)

Verificado **montando cada DMG** y leyendo su `Info.plist` y la fecha del binario de dentro:

| App | DMG | Versión en el bundle | Binario dentro |
|---|---|---|---|
| JUST4FOLDERS | `APPS/JUST4FOLDERS/dist/JUST4FOLDERS.dmg` (1,6 MB) | **2.3.15** (antes 0.1.0) | hoy |
| JUST4DESK | `APPS/JUST4DESK/dist/JUST4DESK-0.1.0+<sello>.dmg` | 0.1.0 + sello de hoy | hoy |
| JUST4PICT | `APPS/JUST4PICT/dist/JUST4PICT-0.1.0+<sello>.dmg` | 0.1.0 + sello de hoy | hoy |
| JUST4CONVERT | `APPS/JUST4CONVERT/dist/JUST4CONVERT.dmg` (25 MB) | 0.1.0 | hoy |
| LIFEOS | `APPS/LIFEOS/dist/LIFEOS-0.1.0+<sello>.dmg` | 0.1.0 + sello de hoy | hoy (firmada) |
| JUST4PDF | `APPS/JUST4PDF/dist/JUST4PDF.dmg` (93,5 MB) | 0.1.0 | hoy |
| JUST4ALL (hub) | `dist/JUST4ALL.dmg` (4,0 MB) | 0.1.0 | hoy |

Y `scripts/sync_local_dmgs.sh` deja los seis assets + `SHA256SUMS.txt` en
`dist/release-assets/`, listos para publicar.

## 3) Lo que queda (necesita decisión)

1. ✅ **Publicado (2-oct-2026)**: release `v0.1.4` con los seis assets + `SHA256SUMS.txt`
   (`gh release create v0.1.4 dist/release-assets/*`, y antes `git push origin main`, que estaba
   4 commits adelante). Pendiente menor: decidir si se borran los assets enganosos de `v0.1.0`/`v0.1.3`.
2. **Numeración propia** para DESK, PICT, PDF, CONVERT y LIFEOS: hoy siguen en `0.1.0` y sólo
   se distinguen por el sello de fecha. Con `APPS/<App>/VERSION` ya es una línea por app.
3. **Firma y notarización** (`🔴` en `PENDIENTES.md` §5): sigue bloqueado por la licencia de
   Apple; los DMG locales se generan y validan igual.
4. **`JUST4CONVERT-0.1.0.dmg` (349 KB) de `v0.1.0`**: decidir si se borra del release viejo
   para que nadie se descargue un artefacto que no es la app.
5. El `scripts/run_debug_app.sh` del hub usa el mismo patrón `find | head -1`; en Debug sólo
   afecta a pruebas locales, pero conviene alinearlo.
