#!/bin/sh
set -e

cd "$(dirname "$0")/.."

if swift package generate-xcodeproj >/dev/null 2>&1; then
	echo "Xcode project generado."
else
	echo "generate-xcodeproj no esta disponible en esta version de SwiftPM."
	echo "Abriendo el paquete en Xcode..."
	open -a Xcode .
fi
