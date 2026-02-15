from collections import OrderedDict
from pathlib import Path

from PySide6.QtCore import QTimer, QUrl
from PySide6.QtGui import QDesktopServices, QPixmap
from PySide6.QtWidgets import (
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QTabWidget,
    QLabel,
    QFileDialog,
    QTextEdit,
    QPushButton,
)

from just4pdf.ui_reader import ReaderWidget
from just4pdf.ui_convert import PdfToImagesWidget, ImagesToPdfWidget, PdfToolsWidget
from just4pdf.preferences import PreferencesWidget
from just4pdf.services.reader_render import open_document, page_size_points
from just4pdf.workers import (
    RenderPagesWorker,
    ThumbnailsWorker,
    PdfToImagesWorker,
    ImagesToPdfWorker,
    PdfMergeWorker,
    PdfCompressWorker,
    PdfCompressPreviewWorker,
)
from just4pdf.config import add_recent_file, get_recent_files


class MainWindow(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("JUST4PDF")
        self.resize(1100, 800)

        self._doc = None
        self._doc_path = None
        self._page_count = 0
        self._page_width_points = 0.0
        self._page_sizes = []
        self._current_page = 0
        self._zoom = 1.0
        self._search_text = None
        self._search_page = None
        self._render_worker = None
        self._thumb_worker = None
        self._rendering_pages = set()
        self._cache = OrderedDict()
        self._cache_limit = 12
        self._export_worker = None
        self._convert_worker = None
        self._merge_worker = None
        self._compress_worker = None
        self._compress_preview_worker = None

        layout = QVBoxLayout(self)
        self.tabs = QTabWidget(self)

        header = QHBoxLayout()
        self.app_icon = QLabel()
        self.app_icon.setFixedSize(28, 28)
        self.app_icon.setScaledContents(True)
        icon_path = Path(__file__).resolve().parents[2] / "images" / "logo_just4pdf.png"
        if icon_path.exists():
            self.app_icon.setPixmap(QPixmap(str(icon_path)))
        header.addWidget(self.app_icon)
        header.addWidget(QLabel("JUST4PDF"))
        header.addStretch(1)
        layout.addLayout(header)

        self.reader = ReaderWidget()
        self.reader.open_requested.connect(self._open_pdf)
        self.reader.prev_requested.connect(self._prev_page)
        self.reader.next_requested.connect(self._next_page)
        self.reader.page_requested.connect(self._goto_page)
        self.reader.zoom_in_requested.connect(self._zoom_in)
        self.reader.zoom_out_requested.connect(self._zoom_out)
        self.reader.fit_width_requested.connect(self._fit_width)
        self.reader.search_next_requested.connect(self._search_next)
        self.reader.search_prev_requested.connect(self._search_prev)
        self.reader.recent_selected.connect(self._open_recent)

        self.pdf_to_images = PdfToImagesWidget()
        self.pdf_to_images.export_requested.connect(self._export_pdf_images)
        self.pdf_to_images.cancel_requested.connect(self._cancel_export)

        self.images_to_pdf = ImagesToPdfWidget()
        self.images_to_pdf.convert_requested.connect(self._convert_images_pdf)

        self.preferences = PreferencesWidget()
        self.pdf_tools = PdfToolsWidget()
        self.pdf_tools.merge_requested.connect(self._merge_pdfs)
        self.pdf_tools.compress_requested.connect(self._compress_pdf)
        self.pdf_tools.merge_cancel_requested.connect(self._cancel_merge)
        self.pdf_tools.compress_cancel_requested.connect(self._cancel_compress)

        self.tabs.addTab(self.reader, "Reader")
        self.tabs.addTab(self.pdf_to_images, "PDF → Imágenes")
        self.tabs.addTab(self.images_to_pdf, "Imágenes → PDF")
        self.tabs.addTab(self.pdf_tools, "PDF Tools")
        self.tabs.addTab(self.preferences, "Preferencias")

        layout.addWidget(self.tabs)

        log_row = QHBoxLayout()
        log_row.addWidget(QLabel("Log:"))
        self.clear_log_btn = QPushButton("Limpiar")
        log_row.addStretch(1)
        log_row.addWidget(self.clear_log_btn)
        layout.addLayout(log_row)

        self.log = QTextEdit()
        self.log.setReadOnly(True)
        self.log.setMinimumHeight(140)
        layout.addWidget(self.log)

        self.reader.set_controls_enabled(False)
        self.reader.show_status("Sin documento")
        self.reader.set_recent_files(get_recent_files())
        self.clear_log_btn.clicked.connect(self.log.clear)
        self._log("App iniciada")

        self._visible_timer = QTimer(self)
        self._visible_timer.setSingleShot(True)
        self._visible_timer.timeout.connect(self._render_visible_pages)
        self.reader.scroll_area.verticalScrollBar().valueChanged.connect(self._schedule_visible_render)
        self.reader.scroll_area.horizontalScrollBar().valueChanged.connect(self._schedule_visible_render)

    def _open_pdf(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Open PDF", "", "PDF Files (*.pdf)")
        if not path:
            return
        self.open_path(path)

    def open_path(self, path: str) -> None:
        try:
            self._doc = open_document(path)
        except Exception as exc:
            self.reader.show_status(f"Error al abrir: {exc}")
            self._log(f"Error al abrir PDF: {exc}")
            return
        self._doc_path = path
        add_recent_file(path)
        self.reader.set_recent_files(get_recent_files())
        self._page_count = self._doc.page_count
        self._page_sizes = []
        if self._page_count > 0:
            for i in range(self._page_count):
                width, height = page_size_points(self._doc, i)
                self._page_sizes.append((width, height))
            self._page_width_points = self._page_sizes[0][0]
        self._current_page = 0
        self._zoom = 1.0
        self._reset_cache()
        self._setup_placeholders()
        self._start_thumbnails()
        self._schedule_visible_render()
        self._sync_page_ui()
        self.reader.set_controls_enabled(self._page_count > 0)
        self.reader.show_status(f"Abierto: {path}")
        self._log(f"Abrir PDF: {path} ({self._page_count} páginas)")
        self._doc.close()
        self._doc = None

    def _open_recent(self, path: str) -> None:
        self.open_path(path)

    def _reset_cache(self) -> None:
        self._cache.clear()
        self._rendering_pages.clear()

    def _setup_placeholders(self) -> None:
        if not self._page_sizes:
            self.reader.clear_pages()
            return
        sizes = [
            (int(w * self._zoom), int(h * self._zoom)) for (w, h) in self._page_sizes
        ]
        self.reader.set_placeholders(sizes)

    def _schedule_visible_render(self) -> None:
        if not self._doc_path:
            return
        if self._visible_timer.isActive():
            self._visible_timer.stop()
        self._visible_timer.start(120)

    def _render_visible_pages(self) -> None:
        if not self._doc_path or self._page_count == 0:
            return
        if self._render_worker and self._render_worker.isRunning():
            self._render_worker.requestInterruption()
            self._render_worker.wait(2000)

        viewport = self.reader.scroll_area.viewport()
        y0 = self.reader.scroll_area.verticalScrollBar().value()
        y1 = y0 + viewport.height()
        buffer = viewport.height()

        to_render: list[int] = []
        for i, label in enumerate(self.reader.page_labels):
            geom = label.geometry()
            if geom.bottom() >= y0 - buffer and geom.top() <= y1 + buffer:
                if i not in self._cache and i not in self._rendering_pages:
                    to_render.append(i)

        if not to_render:
            return

        self.reader.show_status("Renderizando…")
        self._log(f"Render visible: {len(to_render)} páginas")
        self._rendering_pages.update(to_render)
        self._render_worker = RenderPagesWorker(
            self._doc_path,
            self._zoom,
            to_render,
            highlight_page=self._search_page,
            search_text=self._search_text,
        )
        self._render_worker.page_rendered.connect(self._on_page_rendered)
        self._render_worker.finished_render.connect(self._on_render_finished)
        self._render_worker.start()

    def _start_thumbnails(self) -> None:
        if not self._doc_path:
            return
        if self._thumb_worker and self._thumb_worker.isRunning():
            self._thumb_worker.requestInterruption()
            self._thumb_worker.wait(2000)
        self._thumb_worker = ThumbnailsWorker(self._doc_path, zoom=0.2)
        self._thumb_worker.thumb_rendered.connect(self._on_thumb_rendered)
        self._thumb_worker.start()

    def _on_thumb_rendered(self, page_index: int, image) -> None:
        self.reader.set_thumbnail(page_index, image)

    def _sync_page_ui(self) -> None:
        if self._page_count == 0:
            self.reader.set_page_info(0, 0)
            self.reader.set_controls_enabled(False)
            return
        self.reader.set_page_info(self._current_page + 1, self._page_count)
        self.reader.scroll_to_page(self._current_page)
        self.reader.set_current_thumbnail(self._current_page)
        self.reader.set_nav_enabled(
            self._current_page > 0,
            self._current_page < self._page_count - 1,
        )
        self._schedule_visible_render()

    def _prev_page(self) -> None:
        if self._page_count == 0:
            return
        if self._current_page <= 0:
            return
        self._current_page -= 1
        self._sync_page_ui()

    def _next_page(self) -> None:
        if self._page_count == 0:
            return
        if self._current_page >= self._page_count - 1:
            return
        self._current_page += 1
        self._sync_page_ui()

    def _goto_page(self, page_number: int) -> None:
        if self._page_count == 0:
            return
        index = page_number - 1
        if index < 0 or index >= self._page_count:
            self.reader.show_status("Página fuera de rango")
            self._log(f"Página fuera de rango: {page_number}")
            return
        self._current_page = index
        self._sync_page_ui()

    def _zoom_in(self) -> None:
        if not self._doc_path:
            return
        self._zoom = min(self._zoom + 0.25, 4.0)
        self._reset_cache()
        self._search_page = None
        self._setup_placeholders()
        self._schedule_visible_render()
        self._sync_page_ui()
        self.reader.show_status(f"Zoom: {int(self._zoom * 100)}%")
        self._log(f"Zoom: {int(self._zoom * 100)}%")

    def _zoom_out(self) -> None:
        if not self._doc_path:
            return
        self._zoom = max(self._zoom - 0.25, 0.5)
        self._reset_cache()
        self._search_page = None
        self._setup_placeholders()
        self._schedule_visible_render()
        self._sync_page_ui()
        self.reader.show_status(f"Zoom: {int(self._zoom * 100)}%")
        self._log(f"Zoom: {int(self._zoom * 100)}%")

    def _fit_width(self) -> None:
        if not self._doc_path:
            return
        if self._page_width_points <= 0:
            return
        viewport_width = self.reader.scroll_area.viewport().width()
        target_width = max(200, viewport_width - 40)
        self._zoom = max(target_width / self._page_width_points, 0.25)
        self._reset_cache()
        self._search_page = None
        self._setup_placeholders()
        self._schedule_visible_render()
        self._sync_page_ui()
        self.reader.show_status(f"Fit width ({int(self._zoom * 100)}%)")
        self._log(f"Fit width: {int(self._zoom * 100)}%")

    def _on_page_rendered(self, page_index: int, image) -> None:
        self.reader.set_page_image(page_index, image)
        self._rendering_pages.discard(page_index)
        self._cache[page_index] = image
        self._cache.move_to_end(page_index)
        if len(self._cache) > self._cache_limit:
            evicted_index, _ = self._cache.popitem(last=False)
            self.reader.clear_page_image(evicted_index)

    def _on_render_finished(self) -> None:
        self._rendering_pages.clear()
        if self._page_count > 0:
            self.reader.show_status("Listo")
            self._log("Render terminado")

    def _search_next(self, text: str) -> None:
        self._search(text, direction=1)

    def _search_prev(self, text: str) -> None:
        self._search(text, direction=-1)

    def _search(self, text: str, direction: int) -> None:
        if not self._doc_path or self._page_count == 0:
            return
        previous_search_page = self._search_page
        start = self._current_page + direction
        found = self._find_page_with_text(text, start, direction)
        if found is None:
            wrap_start = 0 if direction > 0 else self._page_count - 1
            found = self._find_page_with_text(text, wrap_start, direction)
        if found is None:
            self.reader.show_status("No se encontró")
            self._log(f"Búsqueda sin resultados: {text}")
            return
        self._search_text = text
        self._search_page = found
        if previous_search_page is not None and previous_search_page != found:
            self._cache.pop(previous_search_page, None)
            self.reader.clear_page_image(previous_search_page)
        self._current_page = found
        self._sync_page_ui()
        self.reader.show_status(f"Encontrado en página {found + 1}")
        self._log(f"Búsqueda '{text}' → página {found + 1}")

    def _find_page_with_text(self, text: str, start: int, direction: int) -> int | None:
        if not self._doc_path:
            return None
        if direction >= 0:
            indices = range(max(0, start), self._page_count)
        else:
            indices = range(min(self._page_count - 1, start), -1, -1)
        doc = open_document(self._doc_path)
        try:
            for i in indices:
                page = doc.load_page(i)
                hits = page.search_for(text)
                if hits:
                    return i
        finally:
            doc.close()
        return None

    def _export_pdf_images(self, pdf_path: str, out_dir: str, zoom: float) -> None:
        if zoom < 0 and out_dir:
            self._open_folder(out_dir)
            return
        if self._export_worker and self._export_worker.isRunning():
            self.pdf_to_images.append_log("Export en progreso. Espera...")
            self._log("Export en progreso (PDF → Imágenes)")
            return
        self.pdf_to_images.append_log(f"Exportando... (zoom {zoom}x)")
        self._log(f"Exportando PDF → Imágenes: {pdf_path} (zoom {zoom}x)")
        self.pdf_to_images.set_busy(True)
        self.pdf_to_images.set_progress(0, 1)
        self._export_worker = PdfToImagesWorker(pdf_path, out_dir, zoom)
        self._export_worker.finished_export.connect(self._on_export_finished)
        self._export_worker.failed_export.connect(self._on_export_failed)
        self._export_worker.progress.connect(self._on_export_progress)
        self._export_worker.canceled.connect(self._on_export_canceled)
        self._export_worker.start()

    def _on_export_finished(self, files: list[str]) -> None:
        self.pdf_to_images.append_log(f"OK: {len(files)} imágenes")
        self._log(f"Export OK: {len(files)} imágenes")
        self.pdf_to_images.set_busy(False)
        if files:
            out_dir = str(Path(files[0]).parent)
            self.pdf_to_images.set_last_output_dir(out_dir)

    def _on_export_failed(self, error: str) -> None:
        self.pdf_to_images.append_log(f"Error: {error}")
        self._log(f"Export error: {error}")
        self.pdf_to_images.set_busy(False)

    def _on_export_progress(self, current: int, total: int) -> None:
        self.pdf_to_images.set_progress(current, total)

    def _on_export_canceled(self) -> None:
        self.pdf_to_images.append_log("Export cancelado")
        self._log("Export cancelado")
        self.pdf_to_images.set_busy(False)

    def _cancel_export(self) -> None:
        if self._export_worker and self._export_worker.isRunning():
            self._export_worker.requestInterruption()

    def _convert_images_pdf(self, images: list[str], out_path: str, mode: str) -> None:
        if mode == "open":
            self._open_file(out_path)
            return
        if self._convert_worker and self._convert_worker.isRunning():
            self.images_to_pdf.append_log("Conversión en progreso. Espera...")
            self._log("Conversión en progreso (Imágenes → PDF)")
            return
        self.images_to_pdf.append_log(f"Convirtiendo... ({mode})")
        self._log(f"Convirtiendo imágenes → PDF ({mode})")
        self._convert_worker = ImagesToPdfWorker(images, out_path, mode)
        self._convert_worker.finished_convert.connect(self._on_convert_finished)
        self._convert_worker.failed_convert.connect(self._on_convert_failed)
        self._convert_worker.start()

    def _on_convert_finished(self, out_path: str) -> None:
        self.images_to_pdf.append_log(f"OK: {out_path}")
        self._log(f"Conversión OK: {out_path}")
        self.images_to_pdf.set_last_output(out_path)

    def _on_convert_failed(self, error: str) -> None:
        self.images_to_pdf.append_log(f"Error: {error}")
        self._log(f"Conversión error: {error}")

    def _log(self, message: str) -> None:
        self.log.append(message)

    def _merge_pdfs(self, pdfs: list[str], out_path: str) -> None:
        if not pdfs and out_path:
            self._open_file(out_path)
            return
        if self._merge_worker and self._merge_worker.isRunning():
            self.pdf_tools.append_log("Merge en progreso. Espera...")
            self._log("Merge en progreso (PDFs)")
            return
        self.pdf_tools.append_log("Uniendo PDFs...")
        self._log(f"Uniendo PDFs ({len(pdfs)})")
        self.pdf_tools.set_merge_busy(True)
        self.pdf_tools.set_merge_progress(0, max(1, len(pdfs)))
        self._merge_worker = PdfMergeWorker(pdfs, out_path)
        self._merge_worker.finished_merge.connect(self._on_merge_finished)
        self._merge_worker.failed_merge.connect(self._on_merge_failed)
        self._merge_worker.progress.connect(self._on_merge_progress)
        self._merge_worker.canceled.connect(self._on_merge_canceled)
        self._merge_worker.start()

    def _on_merge_finished(self, out_path: str) -> None:
        self.pdf_tools.append_log(f"OK: {out_path}")
        self._log(f"Merge OK: {out_path}")
        self.pdf_tools.set_merge_busy(False)
        self.pdf_tools.set_merge_output(out_path)

    def _on_merge_failed(self, error: str) -> None:
        self.pdf_tools.append_log(f"Error: {error}")
        self._log(f"Merge error: {error}")
        self.pdf_tools.set_merge_busy(False)

    def _on_merge_progress(self, current: int, total: int) -> None:
        self.pdf_tools.set_merge_progress(current, total)

    def _on_merge_canceled(self) -> None:
        self.pdf_tools.append_log("Merge cancelado")
        self._log("Merge cancelado")
        self.pdf_tools.set_merge_busy(False)

    def _cancel_merge(self) -> None:
        if self._merge_worker and self._merge_worker.isRunning():
            self._merge_worker.requestInterruption()

    def _compress_pdf(self, pdf_path: str, out_path: str, level: str, strategy: str) -> None:
        if level == "open" and out_path:
            self._open_file(out_path)
            return
        if not out_path:
            self._preview_compress(pdf_path, level, strategy)
            return
        if self._compress_worker and self._compress_worker.isRunning():
            self.pdf_tools.append_log("Compresión en progreso. Espera...")
            self._log("Compresión en progreso (PDF)")
            return
        self.pdf_tools.append_log(f"Comprimiendo... ({level}, {strategy})")
        self._log(f"Comprimiendo PDF ({level}, {strategy})")
        self.pdf_tools.set_compress_busy(True)
        self._compress_worker = PdfCompressWorker(pdf_path, out_path, level, strategy)
        self._compress_worker.finished_compress.connect(self._on_compress_finished)
        self._compress_worker.not_saved.connect(self._on_compress_not_saved)
        self._compress_worker.failed_compress.connect(self._on_compress_failed)
        self._compress_worker.canceled.connect(self._on_compress_canceled)
        self._compress_worker.start()

    def _preview_compress(self, pdf_path: str, level: str, strategy: str) -> None:
        if self._compress_preview_worker and self._compress_preview_worker.isRunning():
            self.pdf_tools.append_log("Preview en progreso. Espera...")
            return
        self.pdf_tools.append_log(f"Preview... ({level}, {strategy})")
        self._compress_preview_worker = PdfCompressPreviewWorker(pdf_path, level, strategy)
        self._compress_preview_worker.finished_preview.connect(self._on_preview_ready)
        self._compress_preview_worker.failed_preview.connect(self._on_preview_failed)
        self._compress_preview_worker.start()

    def _on_compress_finished(self, out_path: str, original: int, compressed: int) -> None:
        self.pdf_tools.append_log(f"OK: {out_path}")
        self._log(f"Compresión OK: {out_path} ({compressed}/{original} bytes)")
        self.pdf_tools.set_compress_busy(False)
        self.pdf_tools.set_compress_output(out_path)

    def _on_compress_failed(self, error: str) -> None:
        self.pdf_tools.append_log(f"Error: {error}")
        self._log(f"Compresión error: {error}")
        self.pdf_tools.set_compress_busy(False)

    def _on_compress_not_saved(self, original: int, compressed: int) -> None:
        self.pdf_tools.append_log(
            "Resultado mayor que el original. No se guardó el PDF comprimido."
        )
        self._log(f"Compresión descartada: {compressed} >= {original}")
        self.pdf_tools.set_compress_busy(False)

    def _on_preview_ready(self, original: int, compressed: int) -> None:
        def fmt(b: int) -> str:
            for unit in ["B", "KB", "MB", "GB"]:
                if b < 1024:
                    return f"{b:.1f} {unit}"
                b /= 1024
            return f"{b:.1f} TB"

        self.pdf_tools.set_preview_text(
            f"Preview: {fmt(original)} → {fmt(compressed)}"
        )

    def _on_preview_failed(self, error: str) -> None:
        self.pdf_tools.set_preview_text(f"Preview: error ({error})")

    def _open_file(self, path: str) -> None:
        if not path:
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(path))

    def _open_folder(self, path: str) -> None:
        if not path:
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(path))

    def _on_compress_canceled(self) -> None:
        self.pdf_tools.append_log("Compresión cancelada")
        self._log("Compresión cancelada")
        self.pdf_tools.set_compress_busy(False)

    def _cancel_compress(self) -> None:
        if self._compress_worker and self._compress_worker.isRunning():
            self._compress_worker.requestInterruption()
