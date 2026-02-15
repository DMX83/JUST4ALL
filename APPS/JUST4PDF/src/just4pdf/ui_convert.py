from __future__ import annotations

from PySide6.QtCore import Signal, Qt
from PySide6.QtGui import QPixmap
from PySide6.QtWidgets import (
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QPushButton,
    QLabel,
    QFileDialog,
    QLineEdit,
    QTextEdit,
    QListWidget,
    QProgressBar,
    QComboBox,
)


class PdfToImagesWidget(QWidget):
    export_requested = Signal(str, str, float)
    cancel_requested = Signal()

    def __init__(self) -> None:
        super().__init__()
        root = QVBoxLayout(self)

        row = QHBoxLayout()
        self.pdf_path = QLineEdit()
        self.pdf_path.setPlaceholderText("Selecciona un PDF")
        self.pick_pdf_btn = QPushButton("Elegir PDF")
        row.addWidget(self.pdf_path, 1)
        row.addWidget(self.pick_pdf_btn)
        root.addLayout(row)

        row_out = QHBoxLayout()
        self.out_dir = QLineEdit()
        self.out_dir.setPlaceholderText("Carpeta de salida")
        self.pick_out_btn = QPushButton("Elegir carpeta")
        row_out.addWidget(self.out_dir, 1)
        row_out.addWidget(self.pick_out_btn)
        root.addLayout(row_out)

        row_quality = QHBoxLayout()
        row_quality.addWidget(QLabel("Calidad:"))
        self.quality_combo = QComboBox()
        self.quality_combo.addItem("Borrador (1x)", 1.0)
        self.quality_combo.addItem("Normal (2x)", 2.0)
        self.quality_combo.addItem("Alta (3x)", 3.0)
        self.quality_combo.setCurrentIndex(1)
        row_quality.addWidget(self.quality_combo)
        row_quality.addStretch(1)
        root.addLayout(row_quality)

        self.export_btn = QPushButton("Exportar")
        self.cancel_btn = QPushButton("Cancelar")
        self.cancel_btn.setEnabled(False)
        self.open_folder_btn = QPushButton("Abrir carpeta")
        self.open_folder_btn.setEnabled(False)
        row_actions = QHBoxLayout()
        row_actions.addWidget(self.export_btn)
        row_actions.addWidget(self.cancel_btn)
        row_actions.addWidget(self.open_folder_btn)
        row_actions.addStretch(1)
        root.addLayout(row_actions)

        self.progress = QProgressBar()
        self.progress.setValue(0)
        self.progress.setTextVisible(True)
        root.addWidget(self.progress)

        root.addWidget(QLabel("Log:"))
        self.log = QTextEdit()
        self.log.setReadOnly(True)
        root.addWidget(self.log, 1)

        self._wire()

    def _wire(self) -> None:
        self.pick_pdf_btn.clicked.connect(self._pick_pdf)
        self.pick_out_btn.clicked.connect(self._pick_out_dir)
        self.export_btn.clicked.connect(self._emit_export)
        self.cancel_btn.clicked.connect(self.cancel_requested)
        self.open_folder_btn.clicked.connect(self._emit_open_folder)

    def _pick_pdf(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Seleccionar PDF", "", "PDF Files (*.pdf)")
        if path:
            self.pdf_path.setText(path)

    def _pick_out_dir(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Seleccionar carpeta")
        if path:
            self.out_dir.setText(path)

    def _emit_export(self) -> None:
        pdf = self.pdf_path.text().strip()
        out_dir = self.out_dir.text().strip()
        if not pdf or not out_dir:
            self.append_log("Falta PDF o carpeta de salida")
            return
        zoom = float(self.quality_combo.currentData())
        self.export_requested.emit(pdf, out_dir, zoom)

    def append_log(self, text: str) -> None:
        self.log.append(text)

    def set_busy(self, busy: bool) -> None:
        self.export_btn.setEnabled(not busy)
        self.cancel_btn.setEnabled(busy)
        self.pick_pdf_btn.setEnabled(not busy)
        self.pick_out_btn.setEnabled(not busy)
        self.open_folder_btn.setEnabled(not busy and bool(getattr(self, "_last_out_dir", "")))

    def set_progress(self, current: int, total: int) -> None:
        if total <= 0:
            self.progress.setValue(0)
            return
        self.progress.setMaximum(total)
        self.progress.setValue(current)

    def set_last_output_dir(self, path: str) -> None:
        self._last_out_dir = path
        self.open_folder_btn.setEnabled(bool(path))

    def _emit_open_folder(self) -> None:
        path = getattr(self, "_last_out_dir", "")
        if path:
            self.export_requested.emit("", path, -1.0)


class ImagesToPdfWidget(QWidget):
    convert_requested = Signal(list, str, str)

    def __init__(self) -> None:
        super().__init__()
        root = QVBoxLayout(self)

        row = QHBoxLayout()
        self.pick_images_btn = QPushButton("Elegir imágenes")
        self.up_btn = QPushButton("Subir")
        self.down_btn = QPushButton("Bajar")
        self.remove_btn = QPushButton("Quitar")
        self.clear_btn = QPushButton("Limpiar")
        row.addWidget(self.pick_images_btn)
        row.addWidget(self.up_btn)
        row.addWidget(self.down_btn)
        row.addWidget(self.remove_btn)
        row.addWidget(self.clear_btn)
        row.addStretch(1)
        root.addLayout(row)

        list_row = QHBoxLayout()
        self.images_list = ImageListWidget()
        self.images_list.setSelectionMode(QListWidget.SingleSelection)
        self.images_list.setDragDropMode(QListWidget.InternalMove)
        self.images_list.setAcceptDrops(True)
        list_row.addWidget(self.images_list, 1)

        self.preview = QLabel("Preview")
        self.preview.setAlignment(Qt.AlignCenter)
        self.preview.setFixedWidth(240)
        self.preview.setMinimumHeight(240)
        self.preview.setStyleSheet("border: 1px solid #ccc;")
        list_row.addWidget(self.preview)

        root.addLayout(list_row, 1)

        row_out = QHBoxLayout()
        self.output_path = QLineEdit()
        self.output_path.setPlaceholderText("Destino PDF")
        self.pick_out_btn = QPushButton("Elegir destino")
        row_out.addWidget(self.output_path, 1)
        row_out.addWidget(self.pick_out_btn)
        root.addLayout(row_out)

        row_quality = QHBoxLayout()
        row_quality.addWidget(QLabel("Modo:"))
        self.mode_combo = QComboBox()
        self.mode_combo.addItem("PNG (sin pérdida)", "png")
        self.mode_combo.addItem("JPEG (calidad 85)", "jpeg85")
        row_quality.addWidget(self.mode_combo)
        row_quality.addStretch(1)
        root.addLayout(row_quality)

        row_actions = QHBoxLayout()
        self.convert_btn = QPushButton("Convertir a PDF")
        self.open_output_btn = QPushButton("Abrir PDF")
        self.open_output_btn.setEnabled(False)
        row_actions.addWidget(self.convert_btn)
        row_actions.addWidget(self.open_output_btn)
        row_actions.addStretch(1)
        root.addLayout(row_actions)

        root.addWidget(QLabel("Log:"))
        self.log = QTextEdit()
        self.log.setReadOnly(True)
        root.addWidget(self.log, 1)

        self._wire()

    def _wire(self) -> None:
        self.pick_images_btn.clicked.connect(self._pick_images)
        self.pick_out_btn.clicked.connect(self._pick_output)
        self.convert_btn.clicked.connect(self._emit_convert)
        self.clear_btn.clicked.connect(self._clear)
        self.open_output_btn.clicked.connect(self._emit_open_output)
        self.up_btn.clicked.connect(lambda: self._move_selected(-1))
        self.down_btn.clicked.connect(lambda: self._move_selected(1))
        self.remove_btn.clicked.connect(self._remove_selected)
        self.images_list.currentItemChanged.connect(self._update_preview)

    def _pick_images(self) -> None:
        paths, _ = QFileDialog.getOpenFileNames(
            self, "Seleccionar imágenes", "", "Images (*.png *.jpg *.jpeg *.tiff *.bmp)"
        )
        for path in paths:
            self.images_list.addItem(path)

    def _pick_output(self) -> None:
        path, _ = QFileDialog.getSaveFileName(self, "Guardar PDF", "", "PDF Files (*.pdf)")
        if path:
            if not path.lower().endswith(".pdf"):
                path += ".pdf"
            self.output_path.setText(path)

    def _emit_convert(self) -> None:
        items = [self.images_list.item(i).text() for i in range(self.images_list.count())]
        out = self.output_path.text().strip()
        if not items or not out:
            self.append_log("Faltan imágenes o destino")
            return
        mode = str(self.mode_combo.currentData())
        self.convert_requested.emit(items, out, mode)

    def _clear(self) -> None:
        self.images_list.clear()
        self.preview.clear()

    def _move_selected(self, delta: int) -> None:
        row = self.images_list.currentRow()
        if row < 0:
            return
        new_row = row + delta
        if new_row < 0 or new_row >= self.images_list.count():
            return
        item = self.images_list.takeItem(row)
        self.images_list.insertItem(new_row, item)
        self.images_list.setCurrentRow(new_row)

    def _remove_selected(self) -> None:
        row = self.images_list.currentRow()
        if row < 0:
            return
        self.images_list.takeItem(row)

    def _update_preview(self) -> None:
        item = self.images_list.currentItem()
        if not item:
            self.preview.clear()
            return
        path = item.text()
        pix = QPixmap(path)
        if pix.isNull():
            self.preview.setText("No preview")
            return
        self.preview.setPixmap(pix.scaled(220, 220, Qt.KeepAspectRatio, Qt.SmoothTransformation))

    def append_log(self, text: str) -> None:
        self.log.append(text)

    def set_last_output(self, path: str) -> None:
        self._last_output = path
        self.open_output_btn.setEnabled(bool(path))

    def _emit_open_output(self) -> None:
        path = getattr(self, "_last_output", "")
        if path:
            self.convert_requested.emit([], path, "open")


class PdfToolsWidget(QWidget):
    merge_requested = Signal(list, str)
    compress_requested = Signal(str, str, str, str)
    merge_cancel_requested = Signal()
    compress_cancel_requested = Signal()

    def __init__(self) -> None:
        super().__init__()
        root = QVBoxLayout(self)

        root.addWidget(QLabel("Unir PDFs"))
        merge_row = QHBoxLayout()
        self.pick_pdfs_btn = QPushButton("Elegir PDFs")
        self.merge_up_btn = QPushButton("Subir")
        self.merge_down_btn = QPushButton("Bajar")
        self.merge_remove_btn = QPushButton("Quitar")
        self.merge_cancel_btn = QPushButton("Cancelar")
        self.merge_cancel_btn.setEnabled(False)
        merge_row.addWidget(self.pick_pdfs_btn)
        merge_row.addWidget(self.merge_up_btn)
        merge_row.addWidget(self.merge_down_btn)
        merge_row.addWidget(self.merge_remove_btn)
        merge_row.addWidget(self.merge_cancel_btn)
        merge_row.addStretch(1)
        root.addLayout(merge_row)

        list_row = QHBoxLayout()
        self.pdf_list = PdfListWidget()
        self.pdf_list.setSelectionMode(QListWidget.SingleSelection)
        self.pdf_list.setDragDropMode(QListWidget.InternalMove)
        self.pdf_list.setAcceptDrops(True)
        list_row.addWidget(self.pdf_list, 1)
        root.addLayout(list_row, 1)

        out_row = QHBoxLayout()
        self.merge_output = QLineEdit()
        self.merge_output.setPlaceholderText("Destino PDF combinado")
        self.pick_merge_out_btn = QPushButton("Elegir destino")
        out_row.addWidget(self.merge_output, 1)
        out_row.addWidget(self.pick_merge_out_btn)
        root.addLayout(out_row)

        merge_actions = QHBoxLayout()
        self.merge_btn = QPushButton("Unir PDFs")
        self.merge_open_btn = QPushButton("Abrir PDF")
        self.merge_open_btn.setEnabled(False)
        merge_actions.addWidget(self.merge_btn)
        merge_actions.addWidget(self.merge_open_btn)
        merge_actions.addStretch(1)
        root.addLayout(merge_actions)

        self.merge_progress = QProgressBar()
        self.merge_progress.setValue(0)
        root.addWidget(self.merge_progress)

        root.addSpacing(12)
        root.addWidget(QLabel("Comprimir PDF"))

        comp_row = QHBoxLayout()
        self.compress_input = QLineEdit()
        self.compress_input.setPlaceholderText("Selecciona un PDF")
        self.pick_compress_btn = QPushButton("Elegir PDF")
        comp_row.addWidget(self.compress_input, 1)
        comp_row.addWidget(self.pick_compress_btn)
        root.addLayout(comp_row)

        comp_out_row = QHBoxLayout()
        self.compress_output = QLineEdit()
        self.compress_output.setPlaceholderText("Destino PDF comprimido")
        self.pick_compress_out_btn = QPushButton("Elegir destino")
        comp_out_row.addWidget(self.compress_output, 1)
        comp_out_row.addWidget(self.pick_compress_out_btn)
        root.addLayout(comp_out_row)

        level_row = QHBoxLayout()
        level_row.addWidget(QLabel("Nivel:"))
        self.compress_level = QComboBox()
        self.compress_level.addItem("Bajo", "low")
        self.compress_level.addItem("Medio", "medium")
        self.compress_level.addItem("Alto", "high")
        self.compress_level.setCurrentIndex(1)
        level_row.addWidget(self.compress_level)
        self.compress_strategy = QComboBox()
        self.compress_strategy.addItem("Auto (pikepdf)", "auto")
        self.compress_strategy.addItem("pikepdf (qpdf)", "pikepdf")
        self.compress_strategy.addItem("PyMuPDF", "fitz")
        level_row.addWidget(self.compress_strategy)
        level_row.addStretch(1)
        root.addLayout(level_row)

        comp_action_row = QHBoxLayout()
        self.compress_btn = QPushButton("Comprimir")
        self.compress_preview_btn = QPushButton("Preview tamaño")
        self.compress_open_btn = QPushButton("Abrir PDF")
        self.compress_open_btn.setEnabled(False)
        comp_action_row.addWidget(self.compress_btn)
        comp_action_row.addWidget(self.compress_preview_btn)
        comp_action_row.addWidget(self.compress_open_btn)
        comp_action_row.addStretch(1)
        root.addLayout(comp_action_row)

        self.compress_cancel_btn = QPushButton("Cancelar")
        self.compress_cancel_btn.setEnabled(False)
        root.addWidget(self.compress_cancel_btn)

        self.compress_preview_label = QLabel("Preview: —")
        root.addWidget(self.compress_preview_label)

        root.addWidget(QLabel("Log:"))
        self.log = QTextEdit()
        self.log.setReadOnly(True)
        root.addWidget(self.log, 1)

        self._wire()

    def _wire(self) -> None:
        self.pick_pdfs_btn.clicked.connect(self._pick_pdfs)
        self.merge_up_btn.clicked.connect(lambda: self._move_selected(self.pdf_list, -1))
        self.merge_down_btn.clicked.connect(lambda: self._move_selected(self.pdf_list, 1))
        self.merge_remove_btn.clicked.connect(self._remove_selected)
        self.pick_merge_out_btn.clicked.connect(self._pick_merge_output)
        self.merge_btn.clicked.connect(self._emit_merge)
        self.merge_cancel_btn.clicked.connect(self._emit_merge_cancel)
        self.merge_open_btn.clicked.connect(self._emit_merge_open)
        self.pick_compress_btn.clicked.connect(self._pick_compress_input)
        self.pick_compress_out_btn.clicked.connect(self._pick_compress_output)
        self.compress_btn.clicked.connect(self._emit_compress)
        self.compress_cancel_btn.clicked.connect(self._emit_compress_cancel)
        self.compress_preview_btn.clicked.connect(self._emit_preview)
        self.compress_open_btn.clicked.connect(self._emit_compress_open)

    def _pick_pdfs(self) -> None:
        paths, _ = QFileDialog.getOpenFileNames(self, "Seleccionar PDFs", "", "PDF Files (*.pdf)")
        for path in paths:
            self.pdf_list.addItem(path)

    def _pick_merge_output(self) -> None:
        path, _ = QFileDialog.getSaveFileName(self, "Guardar PDF", "", "PDF Files (*.pdf)")
        if path:
            if not path.lower().endswith(".pdf"):
                path += ".pdf"
            self.merge_output.setText(path)

    def _emit_merge(self) -> None:
        items = [self.pdf_list.item(i).text() for i in range(self.pdf_list.count())]
        out = self.merge_output.text().strip()
        if not items or not out:
            self.append_log("Faltan PDFs o destino")
            return
        self.merge_requested.emit(items, out)

    def _emit_merge_cancel(self) -> None:
        self.merge_cancel_requested.emit()

    def _emit_merge_open(self) -> None:
        path = getattr(self, "_merge_last_output", "")
        if path:
            self.merge_requested.emit([], path)

    def _pick_compress_input(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Seleccionar PDF", "", "PDF Files (*.pdf)")
        if path:
            self.compress_input.setText(path)

    def _pick_compress_output(self) -> None:
        path, _ = QFileDialog.getSaveFileName(self, "Guardar PDF", "", "PDF Files (*.pdf)")
        if path:
            if not path.lower().endswith(".pdf"):
                path += ".pdf"
            self.compress_output.setText(path)

    def _emit_compress(self) -> None:
        pdf = self.compress_input.text().strip()
        out = self.compress_output.text().strip()
        if not pdf or not out:
            self.append_log("Falta PDF o destino")
            return
        level = str(self.compress_level.currentData())
        strategy = str(self.compress_strategy.currentData())
        self.compress_requested.emit(pdf, out, level, strategy)

    def _emit_preview(self) -> None:
        pdf = self.compress_input.text().strip()
        if not pdf:
            self.append_log("Falta PDF para preview")
            return
        level = str(self.compress_level.currentData())
        strategy = str(self.compress_strategy.currentData())
        self.compress_requested.emit(pdf, "", level, strategy)

    def _emit_compress_cancel(self) -> None:
        self.compress_cancel_requested.emit()

    def _emit_compress_open(self) -> None:
        path = getattr(self, "_compress_last_output", "")
        if path:
            self.compress_requested.emit(path, path, "open", "open")

    def _move_selected(self, widget: QListWidget, delta: int) -> None:
        row = widget.currentRow()
        if row < 0:
            return
        new_row = row + delta
        if new_row < 0 or new_row >= widget.count():
            return
        item = widget.takeItem(row)
        widget.insertItem(new_row, item)
        widget.setCurrentRow(new_row)

    def _remove_selected(self) -> None:
        row = self.pdf_list.currentRow()
        if row < 0:
            return
        self.pdf_list.takeItem(row)

    def append_log(self, text: str) -> None:
        self.log.append(text)

    def set_merge_busy(self, busy: bool) -> None:
        self.merge_btn.setEnabled(not busy)
        self.merge_cancel_btn.setEnabled(busy)
        self.pick_pdfs_btn.setEnabled(not busy)
        self.merge_up_btn.setEnabled(not busy)
        self.merge_down_btn.setEnabled(not busy)
        self.merge_remove_btn.setEnabled(not busy)

    def set_merge_progress(self, current: int, total: int) -> None:
        if total <= 0:
            self.merge_progress.setValue(0)
            return
        self.merge_progress.setMaximum(total)
        self.merge_progress.setValue(current)

    def set_compress_busy(self, busy: bool) -> None:
        self.compress_btn.setEnabled(not busy)
        self.compress_cancel_btn.setEnabled(busy)
        self.pick_compress_btn.setEnabled(not busy)
        self.pick_compress_out_btn.setEnabled(not busy)
        self.compress_preview_btn.setEnabled(not busy)

    def set_preview_text(self, text: str) -> None:
        self.compress_preview_label.setText(text)

    def set_merge_output(self, path: str) -> None:
        self._merge_last_output = path
        self.merge_open_btn.setEnabled(bool(path))

    def set_compress_output(self, path: str) -> None:
        self._compress_last_output = path
        self.compress_open_btn.setEnabled(bool(path))


class ImageListWidget(QListWidget):
    def dragEnterEvent(self, event) -> None:
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            return
        super().dragEnterEvent(event)

    def dropEvent(self, event) -> None:
        if event.mimeData().hasUrls():
            for url in event.mimeData().urls():
                if url.isLocalFile():
                    path = url.toLocalFile()
                    self.addItem(path)
            event.acceptProposedAction()
            return
        super().dropEvent(event)


class PdfListWidget(QListWidget):
    def dragEnterEvent(self, event) -> None:
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            return
        super().dragEnterEvent(event)

    def dropEvent(self, event) -> None:
        if event.mimeData().hasUrls():
            for url in event.mimeData().urls():
                if url.isLocalFile():
                    path = url.toLocalFile()
                    if path.lower().endswith(".pdf"):
                        self.addItem(path)
            event.acceptProposedAction()
            return
        super().dropEvent(event)
