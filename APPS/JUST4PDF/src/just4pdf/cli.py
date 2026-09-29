"""CLI de JUST4PDF para automatizaciones (Quick Actions del Finder e integración con JUST4FOLDERS).

Uso:
    just4pdf-cli merge    -o salida.pdf a.pdf b.pdf …
    just4pdf-cli compress --level low|medium|high [--strategy auto] [-o salida.pdf] entrada.pdf
    just4pdf-cli pdf2img  [--zoom 2.0] [--out-dir D] entrada.pdf
    just4pdf-cli img2pdf  -o salida.pdf img1 img2 …

- Usa los MISMOS servicios que la app (sin Qt): CLI y GUI no divergen.
- Códigos de salida: 0 OK · 2 uso · 3 error de operación (mensaje en stderr).
- La ruta del resultado se escribe en stdout (una línea; en `pdf2img`, una por página;
  en `compress`, `ruta<TAB>antes<TAB>después` o `sin-ganancia` si no se pudo reducir).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .services.images_to_pdf import images_to_pdf
from .services.pdf_to_images import export_pdf_to_images
from .services.pdf_tools import compress_pdf, merge_pdfs


def _fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 3


def _cmd_merge(args: argparse.Namespace) -> int:
    pdfs = [p for p in args.inputs if p.lower().endswith(".pdf")]
    if len(pdfs) < 2:
        return _fail("merge necesita al menos 2 PDFs")
    output = args.output
    if output is None:
        base = Path(pdfs[0]).with_suffix("")
        output = str(base) + "-unido.pdf"
    try:
        cancelled = merge_pdfs(pdfs, output)
    except Exception as exc:  # noqa: BLE001 - el mensaje va al usuario final
        return _fail(str(exc))
    if cancelled:
        return _fail("operación cancelada")
    print(output)
    return 0


def _cmd_compress(args: argparse.Namespace) -> int:
    source = args.input
    output = args.output
    if output is None:
        p = Path(source)
        output = str(p.with_name(p.stem + "-comprimido" + p.suffix))
    try:
        saved, before, after = compress_pdf(source, output, level=args.level, strategy=args.strategy)
    except Exception as exc:  # noqa: BLE001
        return _fail(str(exc))
    if not saved:
        # safe=True: no se pudo reducir, el servicio retiró la salida y queda el original.
        print("sin-ganancia")
        return 0
    print(f"{output}\t{before}\t{after}")
    return 0


def _cmd_pdf2img(args: argparse.Namespace) -> int:
    source = args.input
    out_dir = args.out_dir
    if out_dir is None:
        p = Path(source)
        out_dir = str(p.with_name(p.stem + " Paginas"))
    try:
        files = export_pdf_to_images(source, out_dir, zoom=args.zoom)
    except Exception as exc:  # noqa: BLE001
        return _fail(str(exc))
    print("\n".join(files))
    return 0


def _cmd_img2pdf(args: argparse.Namespace) -> int:
    if not args.inputs:
        return _fail("img2pdf necesita al menos 1 imagen")
    output = args.output
    if output is None:
        output = str(Path(args.inputs[0]).with_suffix(".pdf"))
    try:
        images_to_pdf(args.inputs, output, mode=args.mode)
    except Exception as exc:  # noqa: BLE001
        return _fail(str(exc))
    print(output)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="just4pdf-cli",
        description="JUST4PDF en modo consola (sin interfaz): unir, comprimir y convertir PDFs.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    merge = sub.add_parser("merge", help="Une varios PDFs en uno (en el orden dado)")
    merge.add_argument("-o", "--output", help="PDF de salida (por defecto «<primero>-unido.pdf»)")
    merge.add_argument("inputs", nargs="+", help="PDFs de entrada")
    merge.set_defaults(func=_cmd_merge)

    compress = sub.add_parser("compress", help="Comprime un PDF (3 niveles; no conserva la salida si no reduce)")
    compress.add_argument("--level", choices=("low", "medium", "high"), default="medium")
    compress.add_argument("--strategy", choices=("fitz", "pikepdf", "auto"), default="auto")
    compress.add_argument("-o", "--output", help="PDF de salida (por defecto «<nombre>-comprimido.pdf»)")
    compress.add_argument("input", help="PDF de entrada")
    compress.set_defaults(func=_cmd_compress)

    pdf2img = sub.add_parser("pdf2img", help="Exporta las páginas del PDF a PNG (page-0001.png…)")
    pdf2img.add_argument("--zoom", type=float, default=2.0, help="Escala de render (2.0 = 144 dpi)")
    pdf2img.add_argument("--out-dir", help="Carpeta de salida (por defecto «<nombre> Paginas/»)")
    pdf2img.add_argument("input", help="PDF de entrada")
    pdf2img.set_defaults(func=_cmd_pdf2img)

    img2pdf = sub.add_parser("img2pdf", help="Crea un PDF multipágina con imágenes (orden dado)")
    img2pdf.add_argument("-o", "--output", help="PDF de salida (por defecto «<primera>.pdf»)")
    img2pdf.add_argument("--mode", default="png", choices=("png", "jpg", "jpeg"), help="Modo de incrustación")
    img2pdf.add_argument("inputs", nargs="+", help="Imágenes de entrada")
    img2pdf.set_defaults(func=_cmd_img2pdf)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
