from PySide6.QtCore import Qt
from PySide6.QtWidgets import QWidget, QVBoxLayout, QLabel, QCheckBox

from just4pdf.config import get_setting, set_setting


class PreferencesWidget(QWidget):
    def __init__(self) -> None:
        super().__init__()
        layout = QVBoxLayout(self)

        title = QLabel("Preferencias")
        title.setStyleSheet("font-weight: bold;")
        layout.addWidget(title)

        self.open_with_checkbox = QCheckBox("Permitir abrir PDFs desde 'Open With' en macOS")
        self.open_with_checkbox.setChecked(bool(get_setting("macos_open_with_enabled", True)))
        self.open_with_checkbox.stateChanged.connect(self._on_open_with_changed)
        layout.addWidget(self.open_with_checkbox)

        hint = QLabel(
            "Nota: Esto no cambia la app por defecto. Solo controla si JUST4PDF abre archivos "
            "recibidos desde el sistema."
        )
        hint.setWordWrap(True)
        hint.setStyleSheet("color: #555;")
        layout.addWidget(hint)

        layout.addStretch(1)

    def _on_open_with_changed(self, state: int) -> None:
        set_setting("macos_open_with_enabled", state == Qt.Checked)
