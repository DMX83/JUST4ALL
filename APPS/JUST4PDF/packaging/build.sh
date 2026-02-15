#!/bin/sh
set -e

python3.11 -m pip install pyinstaller
python3.11 -m PyInstaller -y packaging/pyinstaller.spec
