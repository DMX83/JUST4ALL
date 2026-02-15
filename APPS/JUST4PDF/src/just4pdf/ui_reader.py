from PySide6.QtCore import Qt, Signal, QSize
from PySide6.QtGui import QPixmap, QIcon
from PySide6.QtWidgets import (
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QPushButton,
    QLabel,
    QLineEdit,
    QScrollArea,
    QFrame,
    QSizePolicy,
    QListWidget,
    QListWidgetItem,
    QComboBox,
)


class ReaderWidget(QWidget):
    open_requested = Signal()
    prev_requested = Signal()
    next_requested = Signal()
    page_requested = Signal(int)
    zoom_in_requested = Signal()
    zoom_out_requested = Signal()
    fit_width_requested = Signal()
    search_next_requested = Signal(str)
    search_prev_requested = Signal(str)
    recent_selected = Signal(str)

    def __init__(self) -> None:
        super().__init__()
        self.page_labels: list[QLabel] = []

        root = QVBoxLayout(self)

        toolbar = QHBoxLayout()
        self.open_btn = QPushButton("Open")
        self.recent_combo = QComboBox()
        self.recent_combo.setMinimumWidth(220)
        self.prev_btn = QPushButton("Prev")
        self.next_btn = QPushButton("Next")
        self.page_input = QLineEdit()
        self.page_input.setPlaceholderText("Página")
        self.page_input.setFixedWidth(80)
        self.page_label = QLabel("/ 0")
        self.zoom_out_btn = QPushButton("-")
        self.zoom_in_btn = QPushButton("+")
        self.fit_width_btn = QPushButton("Fit Width")
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("Buscar…")
        self.search_prev_btn = QPushButton("◀")
        self.search_next_btn = QPushButton("▶")
        self.status_label = QLabel("Sin documento")
        self.status_label.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)

        toolbar.addWidget(self.open_btn)
        toolbar.addWidget(self.recent_combo)
        toolbar.addSpacing(8)
        toolbar.addWidget(self.prev_btn)
        toolbar.addWidget(self.next_btn)
        toolbar.addSpacing(8)
        toolbar.addWidget(QLabel("Page:"))
        toolbar.addWidget(self.page_input)
        toolbar.addWidget(self.page_label)
        toolbar.addStretch(1)
        toolbar.addWidget(self.zoom_out_btn)
        toolbar.addWidget(self.zoom_in_btn)
        toolbar.addWidget(self.fit_width_btn)
        toolbar.addSpacing(12)
        toolbar.addWidget(self.search_input)
        toolbar.addWidget(self.search_prev_btn)
        toolbar.addWidget(self.search_next_btn)
        toolbar.addSpacing(12)
        toolbar.addWidget(self.status_label, 1)

        root.addLayout(toolbar)

        content_row = QHBoxLayout()

        self.thumb_list = QListWidget()
        self.thumb_list.setFixedWidth(140)
        self.thumb_list.setIconSize(QSize(96, 120))
        self.thumb_list.setSpacing(6)
        content_row.addWidget(self.thumb_list)

        # Scroll area for rendered pages
        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(True)
        self.page_container = QFrame()
        self.page_container.setLayout(QVBoxLayout())
        self.page_container.layout().setAlignment(Qt.AlignTop | Qt.AlignHCenter)
        self.scroll_area.setWidget(self.page_container)
        content_row.addWidget(self.scroll_area, 1)

        root.addLayout(content_row, 1)

        self._wire()

    def _wire(self) -> None:
        self.open_btn.clicked.connect(self.open_requested)
        self.prev_btn.clicked.connect(self.prev_requested)
        self.next_btn.clicked.connect(self.next_requested)
        self.zoom_in_btn.clicked.connect(self.zoom_in_requested)
        self.zoom_out_btn.clicked.connect(self.zoom_out_requested)
        self.fit_width_btn.clicked.connect(self.fit_width_requested)
        self.page_input.returnPressed.connect(self._emit_page)
        self.search_next_btn.clicked.connect(self._emit_search_next)
        self.search_prev_btn.clicked.connect(self._emit_search_prev)
        self.search_input.returnPressed.connect(self._emit_search_next)
        self.thumb_list.currentRowChanged.connect(self._on_thumb_selected)
        self.recent_combo.currentIndexChanged.connect(self._emit_recent_selected)

    def _emit_page(self) -> None:
        text = self.page_input.text().strip()
        if not text:
            return
        try:
            value = int(text)
        except ValueError:
            return
        self.page_requested.emit(value)

    def set_page_info(self, current: int, total: int) -> None:
        self.page_label.setText(f"/ {total}")
        if current > 0:
            self.page_input.setText(str(current))
        elif total == 0:
            self.page_input.clear()

    def clear_pages(self) -> None:
        layout = self.page_container.layout()
        while layout.count():
            item = layout.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.deleteLater()
        self.page_labels = []

    def set_placeholders(self, sizes: list[tuple[int, int]]) -> None:
        self.clear_pages()
        for w, h in sizes:
            label = QLabel()
            label.setAlignment(Qt.AlignCenter)
            label.setMinimumSize(max(100, w), max(140, h))
            label.setText("Cargando…")
            label.setStyleSheet("background: #f5f5f5; border: 1px solid #ddd;")
            self.page_container.layout().addWidget(label)
            self.page_container.layout().addSpacing(16)
            self.page_labels.append(label)
        self.init_thumbnails(len(sizes))

    def set_controls_enabled(self, enabled: bool) -> None:
        self.prev_btn.setEnabled(enabled)
        self.next_btn.setEnabled(enabled)
        self.page_input.setEnabled(enabled)
        self.zoom_in_btn.setEnabled(enabled)
        self.zoom_out_btn.setEnabled(enabled)
        self.fit_width_btn.setEnabled(enabled)
        self.search_input.setEnabled(enabled)
        self.search_prev_btn.setEnabled(enabled)
        self.search_next_btn.setEnabled(enabled)
        self.recent_combo.setEnabled(True)

    def set_nav_enabled(self, prev_enabled: bool, next_enabled: bool) -> None:
        self.prev_btn.setEnabled(prev_enabled)
        self.next_btn.setEnabled(next_enabled)

    def show_status(self, text: str) -> None:
        self.status_label.setText(text)

    def set_page_image(self, index: int, image) -> None:
        if index < 0 or index >= len(self.page_labels):
            return
        label = self.page_labels[index]
        label.setStyleSheet("")
        label.setText("")
        label.setPixmap(QPixmap.fromImage(image))
        self.set_thumbnail(index, image)

    def clear_page_image(self, index: int) -> None:
        if index < 0 or index >= len(self.page_labels):
            return
        label = self.page_labels[index]
        label.setPixmap(QPixmap())
        label.setText("Cargando…")
        label.setStyleSheet("background: #f5f5f5; border: 1px solid #ddd;")

    def init_thumbnails(self, count: int) -> None:
        self.thumb_list.blockSignals(True)
        self.thumb_list.clear()
        for i in range(count):
            item = QListWidgetItem(str(i + 1))
            self.thumb_list.addItem(item)
        self.thumb_list.blockSignals(False)

    def set_thumbnail(self, index: int, image) -> None:
        if index < 0 or index >= self.thumb_list.count():
            return
        pix = QPixmap.fromImage(image).scaled(
            96, 120, Qt.KeepAspectRatio, Qt.SmoothTransformation
        )
        item = self.thumb_list.item(index)
        item.setIcon(QIcon(pix))

    def _emit_search_next(self) -> None:
        text = self.search_input.text().strip()
        if text:
            self.search_next_requested.emit(text)

    def _emit_search_prev(self) -> None:
        text = self.search_input.text().strip()
        if text:
            self.search_prev_requested.emit(text)

    def set_recent_files(self, paths: list[str]) -> None:
        self.recent_combo.blockSignals(True)
        self.recent_combo.clear()
        self.recent_combo.addItem("Recientes…", "")
        for p in paths:
            self.recent_combo.addItem(p, p)
        self.recent_combo.setCurrentIndex(0)
        self.recent_combo.blockSignals(False)

    def _emit_recent_selected(self, index: int) -> None:
        if index <= 0:
            return
        path = self.recent_combo.currentData()
        if path:
            self.recent_selected.emit(path)
            self.recent_combo.setCurrentIndex(0)

    def _on_thumb_selected(self, row: int) -> None:
        if row >= 0:
            self.page_requested.emit(row + 1)

    def scroll_to_page(self, page_index: int) -> None:
        if page_index < 0 or page_index >= len(self.page_labels):
            return
        self.scroll_area.ensureWidgetVisible(self.page_labels[page_index], 0, 20)

    def set_current_thumbnail(self, index: int) -> None:
        if index < 0 or index >= self.thumb_list.count():
            return
        self.thumb_list.blockSignals(True)
        self.thumb_list.setCurrentRow(index)
        self.thumb_list.blockSignals(False)
