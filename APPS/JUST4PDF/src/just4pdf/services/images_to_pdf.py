from __future__ import annotations

from pathlib import Path
import tempfile

import img2pdf
from PIL import Image, ImageOps


def images_to_pdf(image_paths: list[str], output_path: str, mode: str = "png") -> None:
    paths = [Path(p) for p in image_paths]
    paths = [p for p in paths if p.exists()]
    if not paths:
        raise ValueError("No se encontraron imágenes")

    # Normalize orientation using Pillow, then pass temp files to img2pdf
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_paths: list[str] = []
        for idx, path in enumerate(paths, start=1):
            with Image.open(path) as img:
                img = ImageOps.exif_transpose(img)
                if img.mode not in ("RGB", "L"):
                    img = img.convert("RGB")
                if mode == "jpeg85":
                    tmp_path = Path(tmpdir) / f"norm-{idx:04d}.jpg"
                    img.save(tmp_path, format="JPEG", quality=85, optimize=True)
                else:
                    tmp_path = Path(tmpdir) / f"norm-{idx:04d}.png"
                    img.save(tmp_path, format="PNG")
                tmp_paths.append(str(tmp_path))

        pdf_bytes = img2pdf.convert(tmp_paths)
        Path(output_path).write_bytes(pdf_bytes)
