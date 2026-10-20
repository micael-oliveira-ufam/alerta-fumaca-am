#!/usr/bin/env bash
# Gera o APK de release do Alerta Fumaça AM na sua máquina.
#
# Uso:
#   tool/gerar_apk.sh                              # modo local (sem servidor)
#   tool/gerar_apk.sh https://api.seudominio.com  # aponta o app para o seu servidor
#
# Requisitos: Flutter 3.27+ (flutter doctor), Java 17 e Android SDK.
set -euo pipefail
cd "$(dirname "$0")/.."

API_URL="${1:-}"
DEFINES=()
if [[ -n "$API_URL" ]]; then
  DEFINES+=("--dart-define=API_BASE_URL=$API_URL")
fi

python3 tool/versao.py verificar || { echo 'Corrija a versão antes de gerar o APK (tool/versao.py).'; exit 1; }

command -v flutter >/dev/null || { echo "Flutter não encontrado. Instale: https://docs.flutter.dev/get-started/install"; exit 1; }

# Gera android/ e ios/ se ainda não existem (não são versionadas).
if [[ ! -d android ]]; then
  flutter create --platforms=android,ios --org br.ufam.fcf --project-name alerta_fumaca_am .
  rm -f test/widget_test.dart
fi

python3 tool/apply_platform_config.py          # nome, INTERNET, localização, discagem
python3 tool/apply_platform_config.py --check
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter analyze
flutter test
flutter build apk --release "${DEFINES[@]}"

APK="build/app/outputs/flutter-apk/app-release.apk"
DEST="dist/Alerta-Fumaca-AM.apk"
mkdir -p dist
cp "$APK" "$DEST"
( cd dist && sha256sum Alerta-Fumaca-AM.apk > SHA256SUMS.txt )
echo
echo "APK pronto: $DEST"
echo "Versão: $(cat VERSION)"
echo "SHA-256: $(cut -d' ' -f1 dist/SHA256SUMS.txt)"
