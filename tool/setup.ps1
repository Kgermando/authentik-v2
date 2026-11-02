# Prépare le projet Flutter : plateformes de bureau + dépendances.
# Usage (PowerShell, depuis la racine du projet) :  .\tool\setup.ps1
$ErrorActionPreference = 'Stop'
flutter create --project-name authentik_v2 --org com.acatech --platforms=windows,macos,linux .
if (Test-Path test\widget_test.dart) { Remove-Item test\widget_test.dart }
flutter pub add provider file_picker desktop_drop pdfrx opencv_dart sqflite sqflite_common_ffi path_provider path crypto archive
flutter pub add --dev flutter_lints
flutter pub get
Write-Host "Prêt. Lancez :  flutter run -d windows"
Write-Host "Compilation release :  flutter build windows --release"
Write-Host "Icônes (après changement du visuel) :  pip install Pillow; python tool/generate_icons.py"
Write-Host "Installateur MSIX Windows :  .\tool\build_msix.ps1"
