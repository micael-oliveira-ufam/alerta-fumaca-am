#!/usr/bin/env bash
# Baixa os pacotes, abre um emulador/simulador e roda o app nele.
#
# Uso:
#   bash tool/abrir_emulador.sh ios [URL|--local]           # Simulador do iPhone (macOS + Xcode)
#   bash tool/abrir_emulador.sh android [URL|--local]       # Emulador Android (padrão: servidor fixo)
#
# Variáveis opcionais:
#   SIMULADOR_IOS="iPhone 16"     nome do aparelho (padrão: o primeiro iPhone disponível)
#   EMULADOR_ANDROID="Pixel_8"    id do emulador (padrão: o primeiro de `flutter emulators`)
#
# Dentro do `flutter run`: r = recarrega, R = reinicia, q = sai.
set -euo pipefail
cd "$(dirname "$0")/.."
source tool/_preparar.sh

PLATAFORMA="${1:-}"
source tool/_ambiente.sh
API_URL="$(resolver_url_servidor "${2:-}")"   # padrão: servidor fixo; "--local" = sem servidor
DEFINES=()
[[ -n "$API_URL" ]] && DEFINES+=("--dart-define=API_BASE_URL=$API_URL")
echo "Servidor do app: ${API_URL:-nenhum (modo local)}"
case "$PLATAFORMA" in ios|android) ;; *) erro "uso: bash tool/abrir_emulador.sh ios|android [URL]";; esac

aviso_caminho
[[ "$PLATAFORMA" == "ios" ]] && exige_macos
preparar_projeto

abrir_ios() {
  instalar_pods
  local nome="${SIMULADOR_IOS:-}"
  local udid
  if [[ -n "$nome" ]]; then
    udid="$(xcrun simctl list devices available | grep -F "$nome (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
  else
    udid="$(xcrun simctl list devices available | grep -E "iPhone" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
  fi
  [[ -n "$udid" ]] || erro "nenhum simulador de iPhone disponível. Rode: xcodebuild -downloadPlatform iOS"
  echo "== Simulador: $udid"
  xcrun simctl boot "$udid" 2>/dev/null || true   # já ligado não é erro
  open -a Simulator
  xcrun simctl bootstatus "$udid" -b
  DISPOSITIVO="$udid"
}

abrir_android() {
  command -v adb >/dev/null || erro "adb não encontrado. Instale o Android Studio e o Android SDK (flutter doctor mostra como)."
  local id="${EMULADOR_ANDROID:-}"
  if [[ -z "$id" ]]; then
    id="$(flutter emulators 2>/dev/null | awk -F' • ' 'NF>=4 && $4 ~ /android/ {print $1; exit}')"
  fi
  [[ -n "$id" ]] || erro "nenhum emulador Android. Crie um no Android Studio (Device Manager) ou: flutter emulators --create"
  echo "== Emulador: $id"
  flutter emulators --launch "$id"
  adb wait-for-device
  until [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do sleep 2; done
  DISPOSITIVO="$(adb devices | awk '/emulator-/ && $2=="device" {print $1; exit}')"
  [[ -n "$DISPOSITIVO" ]] || erro "o emulador abriu, mas o adb não o lista."
}

DISPOSITIVO=""
if [[ "$PLATAFORMA" == "ios" ]]; then abrir_ios; else abrir_android; fi

echo "== Rodando o app em $DISPOSITIVO"
flutter run -d "$DISPOSITIVO" ${DEFINES[@]+"${DEFINES[@]}"}
