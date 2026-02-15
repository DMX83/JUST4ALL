# -*- mode: python ; coding: utf-8 -*-
import os
from pathlib import Path

project_root = Path.cwd()
app_path = project_root / "src" / "just4pdf" / "app.py"

block_cipher = None
app_version = os.environ.get("APP_VERSION", "0.1.0")
min_macos = os.environ.get("MIN_MACOS_VERSION", "13.0")


a = Analysis(
    [str(app_path)],
    pathex=[str(project_root)],
    binaries=[],
    datas=[(str(project_root / "images"), "images")],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="JUST4PDF",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    exclude_binaries=True,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    name="JUST4PDF",
)

app = BUNDLE(
    coll,
    name="JUST4PDF.app",
    icon=str(project_root / "images" / "logo_just4pdf.icns"),
    bundle_identifier="com.dmx83.just4pdf",
    info_plist={
        "CFBundleDisplayName": "JUST4PDF",
        "CFBundleName": "JUST4PDF",
        "CFBundleIdentifier": "com.dmx83.just4pdf",
        "CFBundleShortVersionString": app_version,
        "CFBundleVersion": app_version,
        "LSMinimumSystemVersion": min_macos,
        "CFBundleDocumentTypes": [
            {
                "CFBundleTypeName": "PDF document",
                "LSItemContentTypes": ["com.adobe.pdf"],
                "CFBundleTypeRole": "Viewer",
            }
        ],
    },
)
