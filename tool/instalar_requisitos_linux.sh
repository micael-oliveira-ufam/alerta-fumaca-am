#!/usr/bin/env bash
# Instala/confere o que o Linux precisa para compilar o APK: dependências, Java 17, Flutter
# e Android SDK (command-line tools). Para iOS é preciso um Mac (Xcode).
#
# Uso: bash tool/instalar_requisitos_linux.sh
#
# Variáveis opcionais:
#   FLUTTER_DIR=~/development/flutter   onde instalar o Flutter
#   FLUTTER_REF=stable                  ramo ou versão (ex.: 3.27.4); padrão: stable
#   ANDROID_SDK_ROOT=~/Android/Sdk      onde instalar o Android SDK
#   CMDLINE_TOOLS_URL=<url do zip>      zip do "command-line tools" (se a descoberta automática falhar)
#
# Pede a senha (sudo) só para instalar pacotes do sistema. Nada é instalado sem aparecer na tela.
set -euo pipefail

[[ "$(uname -s)" == "Linux" ]] || { echo "ERRO: este script é só para Linux."; exit 1; }

FLUTTER_DIR="${FLUTTER_DIR:-$HOME/development/flutter}"
FLUTTER_REF="${FLUTTER_REF:-stable}"
SDK="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"

SUDO=""
[[ "$(id -u)" -ne 0 ]] && SUDO="sudo"

echo "== 1/5 Pacotes do sistema (git, curl, unzip, xz, zip, libglu1-mesa, Java 17)"
if command -v apt-get >/dev/null; then
  $SUDO apt-get update -y
  $SUDO apt-get install -y curl git unzip xz-utils zip libglu1-mesa openjdk-17-jdk
elif command -v dnf >/dev/null; then
  $SUDO dnf install -y curl git unzip xz zip mesa-libGLU java-17-openjdk-devel
elif command -v pacman >/dev/null; then
  $SUDO pacman -Sy --needed --noconfirm curl git unzip xz zip glu jdk17-openjdk
else
  echo "Gerenciador de pacotes não reconhecido. Instale manualmente: curl git unzip xz zip libglu1-mesa e o JDK 17."
fi
# Captura a saída inteira: cortar com `| head` fecha o pipe e o Flutter acusa 'Broken pipe'.
saida_java="$(java -version 2>&1 || true)"; echo "${saida_java%%$'\n'*}"

echo "== 2/5 Flutter ($FLUTTER_REF) em $FLUTTER_DIR"
if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
  mkdir -p "$(dirname "$FLUTTER_DIR")"
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_REF" "$FLUTTER_DIR"
else
  echo "Já existe: $FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"
saida_flutter="$(flutter --version 2>&1)" || { echo "$saida_flutter"; echo "ERRO: o Flutter não iniciou."; exit 1; }
echo "${saida_flutter%%$'\n'*}"

echo "== 3/5 Android SDK (command-line tools) em $SDK"
if [[ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]]; then
  url="${CMDLINE_TOOLS_URL:-}"
  if [[ -z "$url" ]]; then
    # Descobre o zip atual na página oficial (o número da versão muda; não está fixo aqui).
    arq="$(curl -fsSL https://developer.android.com/studio 2>/dev/null | grep -Eom1 'commandlinetools-linux-[0-9]+_latest\.zip' || true)"
    [[ -n "$arq" ]] && url="https://dl.google.com/android/repository/$arq"
  fi
  if [[ -z "$url" ]]; then
    echo "Não consegui descobrir o zip dos command-line tools. Baixe em"
    echo "  https://developer.android.com/studio#command-line-tools-only"
    echo "e rode de novo com:  CMDLINE_TOOLS_URL=<link do zip para Linux> bash tool/instalar_requisitos_linux.sh"
    echo "(ou instale o Android Studio e use o SDK Manager)."
    exit 1
  fi
  tmp="$(mktemp -d)"
  echo "Baixando $url"
  curl -fL "$url" -o "$tmp/cmdline.zip"
  unzip -q "$tmp/cmdline.zip" -d "$tmp"
  mkdir -p "$SDK/cmdline-tools"
  rm -rf "$SDK/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
  rm -rf "$tmp"
else
  echo "Já existe: $SDK/cmdline-tools/latest"
fi
export ANDROID_SDK_ROOT="$SDK" ANDROID_HOME="$SDK"

echo "== 4/5 Pacotes do SDK e licenças"
yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null || true
"$SDK/cmdline-tools/latest/bin/sdkmanager" "platform-tools"
flutter config --android-sdk "$SDK" >/dev/null
yes | flutter doctor --android-licenses >/dev/null 2>&1 || true

echo "== 5/5 PATH permanente"
linha="export PATH=\"$FLUTTER_DIR/bin:\$PATH\"; export ANDROID_SDK_ROOT=\"$SDK\"; export ANDROID_HOME=\"$SDK\""
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  if [[ -f "$rc" ]] && ! grep -qF "$FLUTTER_DIR/bin" "$rc"; then
    printf '\n# Flutter e Android SDK (RespirAR Amazonas)\n%s\n' "$linha" >> "$rc"
    echo "PATH gravado em $rc"
  fi
done

echo
flutter doctor -v || true
echo
echo "Abra um NOVO terminal (ou rode: source ~/.bashrc) e então:  bash tool/gerar_apk.sh <link do túnel>"
echo "Se o 'flutter doctor' mostrar [!] ou [✗] em Android toolchain, corrija o item indicado."
