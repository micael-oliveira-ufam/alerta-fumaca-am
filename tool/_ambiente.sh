#!/usr/bin/env bash
# Localiza Flutter, Java e Android SDK instalados em lugares comuns e os coloca no PATH
# desta execução. Não execute diretamente: use `source tool/_ambiente.sh`.

localizar_ambiente() {
  if ! command -v flutter >/dev/null 2>&1; then
    local d
    for d in "$HOME/development/flutter" "$HOME/flutter" "/opt/flutter" "$HOME/snap/flutter/common/flutter" "/usr/local/flutter"; do
      if [[ -x "$d/bin/flutter" ]]; then export PATH="$d/bin:$PATH"; break; fi
    done
  fi
  if [[ -z "${ANDROID_SDK_ROOT:-}" ]]; then
    local s
    for s in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "/opt/android-sdk"; do
      if [[ -d "$s" ]]; then export ANDROID_SDK_ROOT="$s"; export ANDROID_HOME="$s"; break; fi
    done
  fi
  if [[ -z "${JAVA_HOME:-}" && -d /usr/lib/jvm ]]; then
    local j
    j="$(ls -d /usr/lib/jvm/*17* 2>/dev/null | head -n 1 || true)"
    [[ -n "$j" ]] && export JAVA_HOME="$j"
  fi
}

mensagem_instalar_flutter() {
  if [[ "$(uname -s)" == "Linux" ]]; then
    echo "Flutter não encontrado. No Linux, rode:  bash tool/instalar_requisitos_linux.sh"
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    echo "Flutter não encontrado. No macOS, rode:  bash tool/instalar_requisitos_macos.sh"
  else
    echo "Flutter não encontrado. Instale: https://docs.flutter.dev/get-started/install"
  fi
}

localizar_ambiente
