#!/usr/bin/env bash
# Prépare le projet Flutter : plateformes de bureau + dépendances.
# Usage : ./tool/setup.sh   (depuis la racine du projet)
set -euo pipefail
flutter create --project-name authentik_v2 --org com.acatech --platforms=windows,macos,linux .
rm -f test/widget_test.dart
flutter pub add provider file_picker desktop_drop pdfrx opencv_dart sqflite sqflite_common_ffi path_provider path crypto archive
flutter pub add --dev flutter_lints
flutter pub get
echo "Prêt. Lancez :  flutter run -d linux | macos | windows"
