from __future__ import annotations

from typing import Tuple, Iterable

import fitz
from PySide6.QtGui import QImage, QPainter, QColor


def open_document(path: str) -> fitz.Document:
    return fitz.open(path)


def render_page(
    doc: fitz.Document,
    page_index: int,
    zoom: float = 1.0,
    highlights: Iterable[fitz.Rect] | None = None,
) -> QImage:
    page = doc.load_page(page_index)
    mat = fitz.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=mat, alpha=False)
    image = _pixmap_to_qimage(pix)
    if highlights:
        _paint_highlights(image, highlights, zoom)
    return image


def page_size_points(doc: fitz.Document, page_index: int) -> Tuple[float, float]:
    page = doc.load_page(page_index)
    rect = page.rect
    return rect.width, rect.height


def _pixmap_to_qimage(pix: fitz.Pixmap) -> QImage:
    mode = QImage.Format_RGB888
    return QImage(pix.samples, pix.width, pix.height, pix.stride, mode).copy()


def _paint_highlights(image: QImage, highlights: Iterable[fitz.Rect], zoom: float) -> None:
    painter = QPainter(image)
    painter.setPen(QColor(255, 200, 0, 120))
    painter.setBrush(QColor(255, 255, 0, 80))
    for rect in highlights:
        x0 = rect.x0 * zoom
        y0 = rect.y0 * zoom
        w = rect.width * zoom
        h = rect.height * zoom
        painter.drawRect(int(x0), int(y0), int(w), int(h))
    painter.end()
