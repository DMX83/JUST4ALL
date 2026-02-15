from __future__ import annotations

import json
from pathlib import Path
from typing import Any


DEFAULT_SETTINGS = {
    "macos_open_with_enabled": True,
    "recent_files": [],
}


def _config_dir() -> Path:
    return Path.home() / "Library" / "Application Support" / "JUST4PDF"


def config_path() -> Path:
    return _config_dir() / "settings.json"


def load_settings() -> dict[str, Any]:
    path = config_path()
    if not path.exists():
        return dict(DEFAULT_SETTINGS)
    try:
        data = json.loads(path.read_text())
    except Exception:
        return dict(DEFAULT_SETTINGS)
    merged = dict(DEFAULT_SETTINGS)
    merged.update(data if isinstance(data, dict) else {})
    return merged


def save_settings(settings: dict[str, Any]) -> None:
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(settings, indent=2))


def get_setting(key: str, default: Any = None) -> Any:
    settings = load_settings()
    return settings.get(key, default)


def set_setting(key: str, value: Any) -> None:
    settings = load_settings()
    settings[key] = value
    save_settings(settings)


def add_recent_file(path: str, limit: int = 10) -> None:
    settings = load_settings()
    recents = settings.get("recent_files", [])
    if not isinstance(recents, list):
        recents = []
    if path in recents:
        recents.remove(path)
    recents.insert(0, path)
    settings["recent_files"] = recents[:limit]
    save_settings(settings)


def get_recent_files() -> list[str]:
    settings = load_settings()
    recents = settings.get("recent_files", [])
    return recents if isinstance(recents, list) else []
