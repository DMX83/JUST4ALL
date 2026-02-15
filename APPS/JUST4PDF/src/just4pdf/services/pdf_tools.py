from __future__ import annotations

from pathlib import Path
from typing import Callable, Optional

import fitz


def merge_pdfs(
    pdf_paths: list[str],
    output_path: str,
    progress_cb: Optional[Callable[[int, int], None]] = None,
    should_cancel: Optional[Callable[[], bool]] = None,
) -> bool:
    paths = [Path(p) for p in pdf_paths]
    paths = [p for p in paths if p.exists()]
    if not paths:
        raise ValueError("No se encontraron PDFs")

    out_doc = fitz.open()
    try:
        total = len(paths)
        for idx, path in enumerate(paths, start=1):
            if should_cancel and should_cancel():
                return True
            doc = fitz.open(path)
            try:
                out_doc.insert_pdf(doc)
            finally:
                doc.close()
            if progress_cb:
                progress_cb(idx, total)
        if should_cancel and should_cancel():
            return True
        out_doc.save(output_path)
    finally:
        out_doc.close()
    return False


def compress_pdf(
    pdf_path: str,
    output_path: str,
    level: str = "medium",
    strategy: str = "pikepdf",
    safe: bool = True,
) -> tuple[bool, int, int]:
    level = level.lower()
    if level not in ("low", "medium", "high"):
        raise ValueError("Nivel inválido")

    strategy = strategy.lower()
    if strategy not in ("fitz", "pikepdf", "auto"):
        raise ValueError("Estrategia inválida")

    if strategy == "auto":
        # Try pikepdf first, then fitz, and keep the smallest.
        import tempfile

        best = None
        for candidate in ("pikepdf", "fitz"):
            with tempfile.TemporaryDirectory() as tmpdir:
                tmp_out = Path(tmpdir) / "cand.pdf"
                saved, original, compressed = compress_pdf(
                    pdf_path,
                    str(tmp_out),
                    level=level,
                    strategy=candidate,
                    safe=False,
                )
                if best is None or compressed < best[1]:
                    best = (candidate, compressed)
        strategy = best[0] if best else "pikepdf"

    if level == "low":
        garbage = 1
        deflate_images = False
        deflate_fonts = False
    elif level == "medium":
        garbage = 2
        deflate_images = True
        deflate_fonts = True
    else:
        garbage = 4
        deflate_images = True
        deflate_fonts = True

    src = Path(pdf_path)
    original_size = src.stat().st_size

    if strategy == "fitz":
        doc = fitz.open(pdf_path)
        try:
            doc.save(
                output_path,
                garbage=garbage,
                deflate=True,
                deflate_images=deflate_images,
                deflate_fonts=deflate_fonts,
            )
        finally:
            doc.close()
    else:
        import pikepdf

        pdf = pikepdf.open(pdf_path)
        try:
            # pikepdf uses qpdf; optimize streams and object compression.
            pdf.save(
                output_path,
                object_stream_mode=pikepdf.ObjectStreamMode.generate,
                compress_streams=True,
                linearize=False,
            )
        finally:
            pdf.close()

    compressed_size = Path(output_path).stat().st_size
    if safe and compressed_size >= original_size:
        Path(output_path).unlink(missing_ok=True)
        return (False, original_size, compressed_size)
    return (True, original_size, compressed_size)
