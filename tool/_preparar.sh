#!/usr/bin/env bash
# Funções comuns de preparo do projeto (usado por gerar_ios.sh e abrir_emulador.sh).
# Não execute diretamente: use `source tool/_preparar.sh`.

erro() { echo "ERRO: $*" >&2; exit 1; }

aviso_caminho() {
  # O analisador do Dart falha com caminhos com acentos ou espaços.
  if printf '%s' "$PWD" | LC_ALL=C grep -q '[^ -~]' || [[ "$PWD" == *" "* ]]; then
    echo "AVISO: o caminho do projeto tem acentos ou espaços:"
    echo "  $PWD"
    echo "  Se 'flutter analyze' falhar com 'Unexpected end of input', mova a pasta para um"
    echo "  caminho só com letras, números e hífens (ex.: ~/projetos/respirar-amazonas)."
  fi
}

exige_flutter() {
  command -v flutter >/dev/null || erro "Flutter não encontrado. Rode: bash tool/instalar_requisitos_macos.sh"
}

exige_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || erro "este passo só funciona no macOS (o iOS exige Xcode)."
  command -v xcodebuild >/dev/null || erro "Xcode não encontrado. Instale pela App Store e rode: bash tool/instalar_requisitos_macos.sh"
  command -v xcrun >/dev/null || erro "xcrun não encontrado (ferramentas de linha de comando do Xcode)."
}

# Gera android/ e ios/ (se faltarem), aplica permissões/nome e baixa os pacotes.
preparar_projeto() {
  exige_flutter
  python3 tool/versao.py verificar || erro "versões inconsistentes (tool/versao.py)."

  if [[ ! -d ios || ! -d android ]]; then
    flutter create --platforms=android,ios --org br.ufam.fcf --project-name respirar_amazonas .
    rm -f test/widget_test.dart
  fi
  # Modelo padrão do flutter create referencia MyApp e não compila aqui.
  if grep -q "MyApp" test/widget_test.dart 2>/dev/null; then
    rm -f test/widget_test.dart
  fi

  python3 tool/apply_platform_config.py
  python3 tool/apply_platform_config.py --check

  echo "== Baixando pacotes Dart (flutter pub get)"
  flutter pub get
  echo "== Baixando artefatos de plataforma (flutter precache)"
  flutter precache --ios --android
  echo "== Gerando ícones e splash nativa"
  dart run flutter_launcher_icons
  dart run flutter_native_splash:create
}

# Instala os pods do iOS (CocoaPods baixa as bibliotecas nativas).
instalar_pods() {
  command -v pod >/dev/null || erro "CocoaPods não encontrado. Rode: brew install cocoapods"
  echo "== Baixando bibliotecas nativas do iOS (pod install)"
  ( cd ios && pod install --repo-update )
}

soma_sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}
