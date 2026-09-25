#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "== JUST4DESK QA smoke =="
echo "== swift build =="
swift build

echo "== swift test =="
swift test

echo ""
echo "== Checklist manual (usuario) =="
cat <<'EOF'
1. swift run → onboarding: elegir carpeta raiz de organizacion y carpeta de entrada.
2. Verificar que se crea el arbol de taxonomia (01_Fiscal ... 99_SinClasificar).
3. Buscador: probar terminos (con acentos y guiones), chips de tipo, scope y acciones.
4. Organizacion: soltar un PDF/documento en la carpeta de entrada y comprobar
   archivado + actividad (undo) o cuarentena si no es clasificable.
5. Modo simulacion y pausa de organizacion desde el menu "Carpetas".
EOF
