#!/usr/bin/env bash
# Gera o app iOS na sua máquina (macOS com Xcode).
#
# Uso:
#   bash tool/gerar_ios.sh                          # simulador, modo local (sem servidor)
#   bash tool/gerar_ios.sh simulador https://api.seudominio.com
#   bash tool/gerar_ios.sh dispositivo [URL]        # release SEM assinatura (ver aviso abaixo)
#
# Saídas em dist/:
#   simulador   -> RespirAR-Amazonas-simulador.zip   (Runner.app para arrastar ao simulador)
#   dispositivo -> RespirAR-Amazonas-ios-sem-assinatura.ipa
#
# AVISO (dispositivo): o .ipa sai SEM assinatura. Ele NÃO instala em um iPhone como está.
# Para instalar num aparelho ou publicar na App Store é preciso assinar com uma conta Apple
# Developer (abra ios/Runner.xcworkspace no Xcode e configure Signing & Capabilities).
set -euo pipefail
cd "$(dirname "$0")/.."
source tool/_preparar.sh

ALVO="${1:-simulador}"
API_URL="${2:-}"
DEFINES=()
[[ -n "$API_URL" ]] && DEFINES+=("--dart-define=API_BASE_URL=$API_URL")
case "$ALVO" in simulador|dispositivo) ;; *) erro "alvo inválido: '$ALVO' (use simulador ou dispositivo)";; esac

aviso_caminho
exige_macos
preparar_projeto
instalar_pods

echo "== Análise e testes"
flutter analyze
flutter test

mkdir -p dist
if [[ "$ALVO" == "simulador" ]]; then
  flutter build ios --simulator --debug ${DEFINES[@]+"${DEFINES[@]}"}
  APP="build/ios/iphonesimulator/Runner.app"
  [[ -d "$APP" ]] || erro "não encontrei $APP depois do build."
  rm -f dist/RespirAR-Amazonas-simulador.zip
  ( cd build/ios/iphonesimulator && zip -qry ../../../dist/RespirAR-Amazonas-simulador.zip Runner.app )
  SAIDA="dist/RespirAR-Amazonas-simulador.zip"
else
  flutter build ios --release --no-codesign ${DEFINES[@]+"${DEFINES[@]}"}
  APP="build/ios/iphoneos/Runner.app"
  [[ -d "$APP" ]] || erro "não encontrei $APP depois do build."
  rm -rf build/ios/ipa_tmp && mkdir -p build/ios/ipa_tmp/Payload
  cp -R "$APP" build/ios/ipa_tmp/Payload/
  rm -f dist/RespirAR-Amazonas-ios-sem-assinatura.ipa
  ( cd build/ios/ipa_tmp && zip -qry ../../../dist/RespirAR-Amazonas-ios-sem-assinatura.ipa Payload )
  SAIDA="dist/RespirAR-Amazonas-ios-sem-assinatura.ipa"
fi

( cd dist && soma_sha256 "$(basename "$SAIDA")" > "$(basename "$SAIDA").sha256" )
echo
echo "Pronto: $SAIDA"
echo "Versão: $(cat VERSION)"
echo "SHA-256: $(cut -d' ' -f1 "$SAIDA.sha256")"
if [[ "$ALVO" == "simulador" ]]; then
  echo "Para abrir direto no simulador: bash tool/abrir_emulador.sh ios"
fi
