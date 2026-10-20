#!/usr/bin/env bash
# Gera o APK de release do RespirAR Amazonas na sua máquina.
#
# Uso:
#   tool/gerar_apk.sh                              # modo local (sem servidor)
#   tool/gerar_apk.sh https://api.seudominio.com  # aponta o app para o seu servidor
#
# Requisitos: Flutter 3.27+ (flutter doctor), Java 17 e Android SDK.
# No Linux, instale tudo com:  bash tool/instalar_requisitos_linux.sh
set -euo pipefail
cd "$(dirname "$0")/.."

API_URL="${1:-}"
DEFINES=()
if [[ -n "$API_URL" ]]; then
  DEFINES+=("--dart-define=API_BASE_URL=$API_URL")
fi

# O analisador do Dart (flutter analyze) trava com "Unexpected end of input" quando o caminho
# tem acentos ou espaços: o protocolo conta bytes e caracteres de forma diferente.
if printf '%s' "$PWD" | LC_ALL=C grep -q '[^ -~]' || [[ "$PWD" == *" "* ]]; then
  echo "AVISO: o caminho do projeto tem acentos ou espaços:"
  echo "  $PWD"
  echo "  Se 'flutter analyze' falhar com 'Unexpected end of input', mova a pasta para um caminho"
  echo "  só com letras, números e hífens (ex.: ~/projetos/respirar-amazonas) e rode de novo."
fi

python3 tool/versao.py verificar || { echo 'Corrija a versão antes de gerar o APK (tool/versao.py).'; exit 1; }

source tool/_ambiente.sh
command -v flutter >/dev/null || { mensagem_instalar_flutter; exit 1; }

# Gera android/ e ios/ se ainda não existem (não são versionadas).
if [[ ! -d android ]]; then
  flutter create --platforms=android,ios --org br.ufam.fcf --project-name respirar_amazonas .
  rm -f test/widget_test.dart
fi

# O flutter create gera um teste padrão (test/widget_test.dart) que referencia MyApp e
# não compila neste projeto. Remove só se for esse modelo.
if grep -q "MyApp" test/widget_test.dart 2>/dev/null; then
  rm -f test/widget_test.dart
  echo "Removido test/widget_test.dart (modelo padrão do flutter create)."
fi

python3 tool/apply_platform_config.py          # nome, INTERNET, localização, discagem
python3 tool/apply_platform_config.py --check
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter analyze
flutter test
flutter build apk --release ${DEFINES[@]+"${DEFINES[@]}"}

APK="build/app/outputs/flutter-apk/app-release.apk"
DEST="dist/Alerta-Fumaca-AM.apk"
mkdir -p dist
cp "$APK" "$DEST"
if command -v sha256sum >/dev/null; then
  ( cd dist && sha256sum Alerta-Fumaca-AM.apk > SHA256SUMS.txt )
else
  ( cd dist && shasum -a 256 Alerta-Fumaca-AM.apk > SHA256SUMS.txt )  # macOS
fi
echo
echo "APK pronto: $DEST"
echo "Versão: $(cat VERSION)"
echo "SHA-256: $(cut -d' ' -f1 dist/SHA256SUMS.txt)"
