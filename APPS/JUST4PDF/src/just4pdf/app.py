import sys
from pathlib import Path

from PySide6.QtCore import QTimer, QEvent
from PySide6.QtGui import QFileOpenEvent, QIcon
from PySide6.QtWidgets import QApplication

from just4pdf.ui_main import MainWindow
from just4pdf.config import get_setting


def main() -> None:
    app = Just4PdfApplication(sys.argv)
    _set_app_icon(app)
    window = MainWindow()
    window.show()
    app.set_main_window(window)
    _open_from_argv(window)
    sys.exit(app.exec())


def _open_from_argv(window: MainWindow) -> None:
    if not get_setting("macos_open_with_enabled", True):
        return
    args = [a for a in sys.argv[1:] if a and not a.startswith("-")]
    if not args:
        return
    first = Path(args[0])
    if not first.exists():
        return
    if first.suffix.lower() != ".pdf":
        return
    QTimer.singleShot(0, lambda: window.open_path(str(first)))


class Just4PdfApplication(QApplication):
    def __init__(self, argv) -> None:
        super().__init__(argv)
        self._main_window = None
        self._pending_paths: list[str] = []

    def set_main_window(self, window: MainWindow) -> None:
        self._main_window = window
        if self._pending_paths:
            path = self._pending_paths.pop(0)
            QTimer.singleShot(0, lambda: window.open_path(path))

    def event(self, event) -> bool:
        if event.type() == QEvent.FileOpen:
            if not get_setting("macos_open_with_enabled", True):
                return True
            file_event = event  # type: QFileOpenEvent
            path = file_event.file()
            if path and path.lower().endswith(".pdf"):
                if self._main_window is not None:
                    QTimer.singleShot(0, lambda: self._main_window.open_path(path))
                else:
                    self._pending_paths.append(path)
                return True
        return super().event(event)


def _set_app_icon(app: QApplication) -> None:
    icon_path = _find_icon_path()
    if icon_path:
        app.setWindowIcon(QIcon(str(icon_path)))


def _find_icon_path() -> Path | None:
    # Prefer bundled resources when frozen
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        candidate = Path(meipass) / "images" / "logo_just4pdf.png"
        if candidate.exists():
            return candidate
    # Fallback to source tree
    candidate = Path(__file__).resolve().parents[2] / "images" / "logo_just4pdf.png"
    if candidate.exists():
        return candidate
    return None


if __name__ == "__main__":
    main()
