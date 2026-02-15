from __future__ import annotations

from PySide6.QtCore import QThread, Signal
from PySide6.QtGui import QImage

from just4pdf.services.reader_render import open_document, render_page
from just4pdf.services.pdf_to_images import export_pdf_to_images
from just4pdf.services.images_to_pdf import images_to_pdf
from just4pdf.services.pdf_tools import merge_pdfs, compress_pdf


class RenderAllWorker(QThread):
    page_rendered = Signal(int, QImage)
    finished_render = Signal()

    def __init__(self, path: str, zoom: float) -> None:
        super().__init__()
        self._path = path
        self._zoom = zoom

    def run(self) -> None:
        doc = open_document(self._path)
        try:
            for i in range(doc.page_count):
                if self.isInterruptionRequested():
                    break
                image = render_page(doc, i, self._zoom)
                self.page_rendered.emit(i, image)
        finally:
            doc.close()
            self.finished_render.emit()


class RenderPagesWorker(QThread):
    page_rendered = Signal(int, QImage)
    finished_render = Signal()

    def __init__(
        self,
        path: str,
        zoom: float,
        page_indices: list[int],
        highlight_page: int | None = None,
        search_text: str | None = None,
    ) -> None:
        super().__init__()
        self._path = path
        self._zoom = zoom
        self._page_indices = page_indices
        self._highlight_page = highlight_page
        self._search_text = search_text

    def run(self) -> None:
        doc = open_document(self._path)
        try:
            for i in self._page_indices:
                if self.isInterruptionRequested():
                    break
                highlights = None
                if self._search_text and self._highlight_page == i:
                    page = doc.load_page(i)
                    highlights = page.search_for(self._search_text)
                image = render_page(doc, i, self._zoom, highlights=highlights)
                self.page_rendered.emit(i, image)
        finally:
            doc.close()
            self.finished_render.emit()


class ThumbnailsWorker(QThread):
    thumb_rendered = Signal(int, QImage)
    finished_render = Signal()

    def __init__(self, path: str, zoom: float = 0.2) -> None:
        super().__init__()
        self._path = path
        self._zoom = zoom

    def run(self) -> None:
        doc = open_document(self._path)
        try:
            for i in range(doc.page_count):
                if self.isInterruptionRequested():
                    break
                image = render_page(doc, i, self._zoom)
                self.thumb_rendered.emit(i, image)
        finally:
            doc.close()
            self.finished_render.emit()


class PdfToImagesWorker(QThread):
    finished_export = Signal(list)
    failed_export = Signal(str)
    progress = Signal(int, int)
    canceled = Signal()

    def __init__(self, pdf_path: str, out_dir: str, zoom: float) -> None:
        super().__init__()
        self._pdf_path = pdf_path
        self._out_dir = out_dir
        self._zoom = zoom

    def run(self) -> None:
        try:
            output_files = export_pdf_to_images(
                self._pdf_path,
                self._out_dir,
                zoom=self._zoom,
                progress_cb=self._on_progress,
                should_cancel=self.isInterruptionRequested,
            )
        except Exception as exc:
            self.failed_export.emit(str(exc))
            return
        if self.isInterruptionRequested():
            self.canceled.emit()
            return
        self.finished_export.emit(output_files)

    def _on_progress(self, current: int, total: int) -> None:
        self.progress.emit(current, total)


class ImagesToPdfWorker(QThread):
    finished_convert = Signal(str)
    failed_convert = Signal(str)

    def __init__(self, images: list[str], out_path: str, mode: str) -> None:
        super().__init__()
        self._images = images
        self._out_path = out_path
        self._mode = mode

    def run(self) -> None:
        try:
            images_to_pdf(self._images, self._out_path, mode=self._mode)
        except Exception as exc:
            self.failed_convert.emit(str(exc))
            return
        self.finished_convert.emit(self._out_path)


class PdfMergeWorker(QThread):
    finished_merge = Signal(str)
    failed_merge = Signal(str)
    progress = Signal(int, int)
    canceled = Signal()

    def __init__(self, pdfs: list[str], out_path: str) -> None:
        super().__init__()
        self._pdfs = pdfs
        self._out_path = out_path

    def run(self) -> None:
        try:
            canceled = merge_pdfs(
                self._pdfs,
                self._out_path,
                progress_cb=self._on_progress,
                should_cancel=self.isInterruptionRequested,
            )
        except Exception as exc:
            self.failed_merge.emit(str(exc))
            return
        if canceled or self.isInterruptionRequested():
            self.canceled.emit()
            return
        self.finished_merge.emit(self._out_path)

    def _on_progress(self, current: int, total: int) -> None:
        self.progress.emit(current, total)


class PdfCompressWorker(QThread):
    finished_compress = Signal(str, int, int)
    not_saved = Signal(int, int)
    failed_compress = Signal(str)
    canceled = Signal()

    def __init__(self, pdf_path: str, out_path: str, level: str, strategy: str) -> None:
        super().__init__()
        self._pdf_path = pdf_path
        self._out_path = out_path
        self._level = level
        self._strategy = strategy

    def run(self) -> None:
        try:
            if self.isInterruptionRequested():
                self.canceled.emit()
                return
            saved, original, compressed = compress_pdf(
                self._pdf_path,
                self._out_path,
                self._level,
                strategy=self._strategy,
                safe=True,
            )
        except Exception as exc:
            self.failed_compress.emit(str(exc))
            return
        if not saved:
            self.not_saved.emit(original, compressed)
            return
        self.finished_compress.emit(self._out_path, original, compressed)


class PdfCompressPreviewWorker(QThread):
    finished_preview = Signal(int, int)
    failed_preview = Signal(str)

    def __init__(self, pdf_path: str, level: str, strategy: str) -> None:
        super().__init__()
        self._pdf_path = pdf_path
        self._level = level
        self._strategy = strategy

    def run(self) -> None:
        from pathlib import Path
        import tempfile

        try:
            src = Path(self._pdf_path)
            if not src.exists():
                self.failed_preview.emit("PDF no encontrado")
                return
            original_size = src.stat().st_size
            with tempfile.TemporaryDirectory() as tmpdir:
                out = Path(tmpdir) / "preview.pdf"
                compress_pdf(
                    str(src),
                    str(out),
                    self._level,
                    strategy=self._strategy,
                    safe=False,
                )
                compressed_size = out.stat().st_size
        except Exception as exc:
            self.failed_preview.emit(str(exc))
            return
        self.finished_preview.emit(original_size, compressed_size)
