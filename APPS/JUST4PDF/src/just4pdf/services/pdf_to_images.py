from __future__ import annotations

from pathlib import Path
from typing import Callable, Optional

import fitz


def export_pdf_to_images(
    pdf_path: str,
    out_dir: str,
    zoom: float = 2.0,
    progress_cb: Optional[Callable[[int, int], None]] = None,
    should_cancel: Optional[Callable[[], bool]] = None,
) -> list[str]:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    doc = fitz.open(pdf_path)
    output_files: list[str] = []
    try:
        total = doc.page_count
        for i in range(total):
            if should_cancel and should_cancel():
                break
            page = doc.load_page(i)
            pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=False)
            filename = f"page-{i + 1:04d}.png"
            out_path = out / filename
            pix.save(str(out_path))
            output_files.append(str(out_path))
            if progress_cb:
                progress_cb(i + 1, total)
    finally:
        doc.close()

    return output_files
