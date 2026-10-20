# Changelog

Todas as mudanças notáveis do Alerta Fumaça AM (app e servidor) estão aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e a versão segue [SemVer](https://semver.org/lang/pt-BR/):

- **MAIOR**: mudança que quebra compatibilidade (API, formato de dados ou fluxo que exige reinstalação).
- **MENOR**: funcionalidade nova compatível com as anteriores.
- **PATCH**: correção sem funcionalidade nova.

Cada versão aponta para o commit de release (tag `vX.Y.Z`). Como publicar: `tool/versao.py` (ver README, seção "Versionamento").

## [Não lançado]

Nenhuma mudança desde a 1.7.0.

## [1.7.0] - 2026-10-20

### Corrigido
- `tool/instalar_requisitos_linux.sh`: o `flutter doctor` acusava "No valid Android SDK platforms found" porque o instalador só baixava `platform-tools`. Agora também instala a plataforma (`platforms;android-N`) e o `build-tools` mais recentes (só versões finais, sem `-rc`/`-ext`), descobertos por `sdkmanager --list`; `--sdk_root` é passado explicitamente. Se a lista não puder ser obtida, o script mostra o comando manual.
- O fim do instalador explica que os itens "Linux toolchain" (clang, CMake, GTK) do doctor são só para apps de desktop e não afetam o APK.

## [1.6.9] - 2026-10-20

### Corrigido
- `tool/instalar_requisitos_linux.sh`: terminava com "FileSystemException ... Broken pipe" (ao rodar `flutter --version` na primeira vez). Causa: a saída era cortada com `| head -1`, o que fecha o pipe enquanto o Flutter ainda escreve. Agora a saída é capturada inteira e só a primeira linha é exibida; se o Flutter não iniciar, o erro real aparece. O instalador é reexecutável: o que já foi instalado é reaproveitado.

## [1.6.8] - 2026-10-20

### Corrigido
- Mapas das páginas web (painel público e do administrador) mostravam "Access blocked ... 403" no lugar do mapa. Causa: o servidor enviava `Referrer-Policy: no-referrer` e o OpenStreetMap recusa tiles sem o cabeçalho Referer (política de uso de tiles). Agora é `strict-origin-when-cross-origin` (só a origem vai a terceiros, nunca o caminho). Teste novo em `server/tests/test_publico.py`.

## [1.6.7] - 2026-10-20

Nenhuma mudança desde a 1.6.6.

## [1.6.6] - 2026-10-20

### Adicionado
- `tool/instalar_requisitos_linux.sh`: instala no Linux (apt, dnf ou pacman) as dependências do Flutter, o Java 17, o Flutter (clone do repositório oficial, ramo `stable` por padrão) e o Android SDK (command-line tools, `platform-tools`, licenças), grava o PATH em `~/.bashrc` e `~/.profile` e roda `flutter doctor -v`.
- `tool/_ambiente.sh`: localiza Flutter (`~/development/flutter`, `~/flutter`, `/opt/flutter`…), Android SDK (`~/Android/Sdk`) e Java 17 já instalados e os põe no PATH da execução.

### Alterado
- `tool/gerar_apk.sh` e `tool/_preparar.sh`: usam a detecção acima e, se o Flutter não existir, indicam o instalador do sistema certo (Linux ou macOS) em vez de só apontar a documentação.

## [1.6.5] - 2026-10-20

### Alterado
- `tool/iniciar_servidor.sh`: se o Docker recusar uma porta mesmo depois do teste prévio, o script troca a porta que falhou (painel ou API) pela próxima livre e tenta de novo, até 5 vezes, sem intervenção.

## [1.6.4] - 2026-10-20

### Corrigido
- `tool/iniciar_servidor.sh`: falhava com "Bind for 0.0.0.0:8080 failed: port is already allocated" quando outro programa já usava a porta do painel (ou da API). Agora detecta a porta ocupada, escolhe a próxima livre, grava no `.env` e mostra o endereço certo.

## [1.6.3] - 2026-10-20

### Corrigido
- `tool/iniciar_servidor.sh` no Linux: falhava com `unknown shorthand flag: 'd' in -d` quando o Docker não tem o plugin Compose. Agora usa `docker compose` ou `docker-compose`, explica como instalar se faltar, usa `sudo` quando o usuário não está no grupo `docker`, gera os segredos sem depender do `openssl` e mostra o link do túnel e o comando para compilar o app com ele.

## [1.6.2] - 2026-10-20

### Corrigido
- Telefone local do CIT: o (92) 3305-4700 não foi confirmado em nenhuma fonte; substituído pelo (92) 3305-4702 (Abracit e lista de CIATox do Ministério da Saúde). O 0800 722 6001 foi confirmado.
- Textos de saúde revisados contra fontes lidas: retiradas afirmações sem fonte (nebulização com soro, acroleína/formaldeído, "HEPA", raças de focinho curto, gato de boca aberta, limpeza dos olhos do pet com soro, "álcool destrói a máscara", locais de distribuição de máscaras, "sobrecarrega o coração").
- Dica de máscara de pano/cirúrgica no resultado do questionário não exibe mais texto interno.

### Alterado
- Referências ampliadas de 10 para 20 (ASBAI, OMS/OPAS, OMS Europa, VIGIAR, SES-AM/FVS-RCP, CRMV-AM no lugar do CFMV, Anvisa, 3M, DGS, Manual MSD, EPA, imprensa especializada), todas lidas em 20/10/2026.

## [1.6.1] - 2026-10-20

### Corrigido
- Fotos dos desenvolvedores estavam trocadas (Micael = óculos e crachá; Elias = camiseta cinza), no app e na plataforma online.
- Referências de "Fato ou Fake?" e da farmácia caseira passaram a apontar para fontes efetivamente lidas (VIGIAR/Ministério da Saúde e SES-AM/FVS-RCP).

### Adicionado
- `tool/teste_comunicacao.py`: teste de comunicação app -> servidor com o mesmo JSON que o app envia.

## [1.6.0] - 2026-10-20

### Adicionado
- Questionário: pergunta final "Quer compartilhar suas respostas para estudos epidemiológicos?"; "Sim" envia ao servidor (com localização aproximada de ~1 km se permitida), "Não" não envia nada. Termo LGPD 1.2.
- "Sintomas mais relatados": gráficos sempre visíveis (zerados sem dados), nível de risco e **bairros de Manaus mais afetados** (`GET /bairros`, `server/app/bairros.py`, tabela `celulas_bairro`, geocodificação reversa com Nominatim; variáveis `GEOCODER_ATIVO`, `GEOCODER_URL`, `GEOCODER_CONTATO`).
- Mapa: seletor que mostra só as datas de imagem de satélite com imagem disponível (`gibs_availability.dart`).
- Sobre: link da plataforma online e desenvolvedores com foto e e-mail.
- Plataforma online: bairros, focos de calor detalhados (por satélite, dia e município; mapa de calor com `leaflet.heat` 0.2.0), links oficiais de desmatamento e desenvolvedores.

### Alterado
- Questionário: removidos os botões "Refazer" e "Compartilhar localização".
- Fato ou Fake, Farmácia Caseira, Pets e CIT: mostram só as referências, sem texto da equipe nem selo de verificação (o estado de verificação ficou nos dados e no CLAUDE.md).
- Sobre: removido "Alterar endereço".

### Corrigido
- Mapa de focos em "Hoje" nunca mostrava focos: agora usa a camada de 48 h recortada pelo dia atual de Manaus (causa provável, não confirmada ao vivo). O servidor mapeia `today` para a camada de 48 h.
- Mensagem de erro técnica quando a imagem de satélite não existe para a data.

## [1.5.1] - 2026-10-20

### Corrigido
- `tool/_preparar.sh` (usado por `abrir_emulador.sh` e `gerar_ios.sh`): `pod install` falhava com "No `Podfile' found in the project directory" quando `ios/Podfile` ainda não existia. O Flutter só cria o Podfile ao preparar o projeto iOS. Agora, se faltar, o script roda `flutter build ios --config-only --no-codesign` para gerá-lo; se ainda assim não existir, segue sem o `pod install` manual (o `flutter run` e o `flutter build ios` rodam o CocoaPods sozinhos). **Não testado num Mac real**; a lógica foi conferida com comandos simulados.

Nenhuma mudança desde a 1.5.0.

## [1.5.0] - 2026-10-20

### Adicionado
- **Painel público, sem senha**, servido pela própria API em `/` (acessível pelo link do túnel): hero com indicador "ao vivo", filtro 24 h/7/30/90 dias, indicadores-chave, ranking de **sintomas mais relatados** (barras empilhadas leve/moderado/intenso, ordenável por frequência ou intensidade), rosca de níveis de risco, respostas por dia, mapa de áreas, perfil, tempo de exposição, contexto, nota "como ler estes dados" e download do JSON agregado. Claro/escuro, responsivo, sem bibliotecas externas além do Leaflet já incluso, respeita "reduzir movimento".
- `GET /publico/painel?dias=1|7|30|90` (aberto, dados agregados, cache de 10 s). Módulos `app/publico.py` e `app/rotulos.py`; `tests/test_publico.py` (10 testes, entre eles: abre sem senha mesmo com `ADMIN_TOKEN`, nada individual vaza, mínimos de privacidade, CSV continua protegido).

### Privacidade
- O painel público respeita as regras do termo LGPD (mínimo de 5 respostas; área com 3+). Contagens pequenas de perfil e contexto são escondidas ("menos de 3"). Respostas individuais e horários exatos **não** são expostos.
- Perfil (idoso, gestante, criança...), tempo de exposição e contexto passam a aparecer publicamente **em forma agregada**. O termo cita "sintomas mais relatados, níveis de risco e mapa"; avaliar se o texto deve citar também estes agregados (mudar o texto exige subir `kLgpdTermsVersion`).

Nenhuma mudança desde a 1.4.0.

## [1.4.0] - 2026-10-20

### Adicionado
- **iOS e emuladores**: `tool/gerar_ios.sh` (simulador ou release sem assinatura, com SHA-256), `tool/abrir_emulador.sh ios|android` (baixa pacotes, abre o Simulador/emulador e roda o app), `tool/instalar_requisitos_macos.sh` (Flutter, CocoaPods, runtime do simulador, `flutter doctor`) e `tool/_preparar.sh` (funções comuns). Seção "iOS e emuladores" no README.

### Corrigido
- `tool/gerar_apk.sh`: no bash 3.2 do macOS, `"${DEFINES[@]}"` com a lista vazia falha com "unbound variable" (por causa do `set -u`) quando o script roda sem URL de servidor. Trocado por `${DEFINES[@]+"${DEFINES[@]}"}`.

Nenhuma mudança desde a 1.3.1.

## [1.3.1] - 2026-10-19

### Alterado
- **Pacote Dart `alerta_fumaca_am` -> `respirar_amazonas`** e **repositório `alerta-fumaca-am` -> `respirar-amazonas`** (nomes inferidos do nome do app). Atualizados `pubspec.yaml`, imports dos testes, scripts, README e links. O renome do repositório no GitHub precisa ser feito pelo usuário (o ambiente do agente não tem permissão).
- Atenção: o identificador do app (`br.ufam.fcf.<pacote>`) muda, então um aparelho com a versão antiga instalada receberá um segundo app, não uma atualização.

Nenhuma mudança desde a 1.3.0.

## [1.3.0] - 2026-10-19

### Alterado
- **Nome do app: "Alerta Fumaça AM" passou a "RespirAR Amazonas"** (decisão do usuário). Atualizado no app (título, início, *Sobre*, termo LGPD), no servidor (título da API e do painel), nos scripts de plataforma (`tool/apply_platform_config.py`, que grava o nome no Android e no iOS) e no README. O nome do pacote Dart (`alerta_fumaca_am`) e o repositório continuam iguais.
- Termo LGPD: versão `1.0` -> `1.1` porque o nome aparece no texto (regra do próprio arquivo: qualquer mudança de texto pede nova leitura). **O usuário verá o termo de novo na próxima abertura.**
- **Tela de abertura reformulada**: fumaça que sobe e se dissipa ao fundo, logo com anéis de pulso, entrada escalonada do nome ("Respir" + "AR" destacado), slogan "Alertas, triagem e proteção contra fumaça no Amazonas.", quatro recursos (focos do INPE, qualidade do ar, triagem, orientações sem internet), instituição, versão, aviso educativo e barra de progresso. Dura 3,8 s; um toque pula. Com "remover animações" do sistema ligado, o movimento contínuo é desligado.

### Adicionado
- `test/app_name_test.dart`.

Nenhuma mudança desde a 1.2.0.

## [1.2.0] - 2026-10-19

### Adicionado
- **App**: conteúdo do documento "TEXTOS PARA ATUALIZAÇÃO DO APLICATIVO" (`lib/data/pdf_content.dart`), embutido no app e, portanto, disponível sem internet:
  - *O que fazer agora*: cartões "Qual máscara protege" e "Purificador vs. Umidificador", e o painel do CIT (HUGV/UFAM) detalhado, com discagem direta, "Quando ligar" e segundo telefone.
  - Botão **Entenda seus sintomas** no resultado do questionário (CO, gases irritantes, PM2,5).
  - Telas **Farmácia caseira**, **E os nossos pets?** (3 cartões) e **Fato ou Fake?** (3 mitos).
  - Banner de **alerta roxo** na aba de qualidade do ar quando alguma leitura chega a AQI 201 ou mais.
  - Referências 4 a 10 na tela *Referências*, cada uma com o que foi e o que NÃO foi verificado.
  - Selo de verificação ("Conferido", "Parcialmente conferido", "Texto da equipe, fonte não consultada") em todo cartão.
- `CLAUDE.md`: ordens obrigatórias ao agente, diretrizes de comportamento anexadas, histórico detalhado e regra de sempre perguntar os próximos passos com escolhas.
- `test/pdf_content_test.dart`.

### Alterado
- Créditos: "Elias Barros" passou a "Elias de Souza Barros" (tela *Sobre* e README).
- Ajustes declarados nos textos da equipe: no CIT, confusão/desmaio manda ligar primeiro ao SAMU (192); removidas as frases sem fonte ("autoridade máxima", "ácido fraco", "diretamente na corrente sanguínea", e partes de leite/monóxido).

### Não implementado (pedido no PDF)
- Alerta laranja (mudança de vento) e notificações push: exigem previsão de vento e serviço de push que o app não tem.

### Corrigido
- Focos do INPE só carregavam depois de abrir a aba de qualidade do ar. Causa: o `TabBarView` destruía a aba que não estava visível, e a consulta só era refeita ao voltar a ela; uma primeira consulta que falhava não era repetida. Agora as abas ficam vivas (`KeepAlivePage`) e a consulta do INPE é repetida automaticamente em falha de rede ou de servidor (2 novas tentativas, com espera crescente). O tempo limite caiu de 60 s para 30 s.
- Sete sugestões do analisador (`prefer_const_constructors` e `prefer_const_literals_to_create_immutables`) aplicadas em `about_screen`, `guidance_screen`, `home_screen`, `air_quality_tab`, `questionnaire_screen` e `cit_card`.
- `tool/gerar_apk.sh` remove o `test/widget_test.dart` padrão do `flutter create`, que não compila neste projeto.
- `tool/gerar_apk.sh` avisa quando o caminho do projeto tem acentos ou espaços, causa provável de `flutter analyze` falhar com "Unexpected end of input". O README ganhou essa linha no diagnóstico.
- Tela de LGPD: a cor de fundo da área de aceite estava num `DecoratedBox` acima do `CheckboxListTile`, o que escondia o efeito de toque (falha em `test/lgpd_test.dart`). A cor agora fica num `Material`.
- Adicionado `analysis_options.yaml` (estava ausente, então as regras do `flutter_lints` não eram aplicadas e o analisador não tinha configuração explícita).
- `tool/iniciar_servidor.sh` e `tool/gerar_apk.sh` funcionam no macOS: o `sed -i` (sintaxe do GNU) foi trocado por `awk`, e `sha256sum` por `shasum -a 256` quando necessário. O script também confere se o Docker está rodando.

## [1.1.0] - 2026-10-19

Servidor próprio com painel em tempo real, questionário ampliado e interface circular.

### Adicionado
- **App**: questionário em 4 etapas com botões circulares; 10 perguntas de contexto opcionais (local, fumaça visível, máscara, exercício, trabalho ao ar livre, ar filtrado, imunidade, medicação à mão, piora, medicação que não alivia). Não alteram a pontuação e geram cuidados por situação.
- **App**: tela **Referências** com as fontes de cada pergunta (CDC HAN 00495, EPA-452/R-21-901, nota do Ministério da Saúde via imprensa), com ressalvas do que foi verificado.
- **App**: mapas sem rotação, botões de zoom, minha localização, visão inicial, camadas (fundo Ruas ou Satélite NASA GIBS; sobreposições de fumaça/aerossóis e focos VIIRS) e barra de escala.
- **App**: tela cheia (modo imersivo) e nome exibido "Alerta Fumaça AM".
- **App**: termo de privacidade (LGPD) na primeira abertura (commit `638ded1`).
- **App**: endereço do servidor configurável em *Sobre*, com aviso de consentimento.
- **Servidor**: painel em tempo real (KPIs, série de 48 h, mapa, últimas respostas, contexto agregado) protegido por `ADMIN_TOKEN`.
- **Servidor**: túnel Cloudflare com link aleatório a cada início, exibido no painel com QR code.
- **Servidor**: coluna `contexto` (opcional) em `respostas`, com migração que adiciona a coluna em bancos existentes.
- **Servidor**: colunas `ctx_*` no CSV de exportação.
- **Operação**: `tool/iniciar_servidor.sh` (gera `.env` com segredos e sobe o Docker Compose) e `tool/gerar_apk.sh` (gera o APK de release com SHA-256).

### Alterado
- Menu inicial com botões circulares; botões com formato de pílula.
- O questionário envia o contexto apenas se a pessoa respondeu, e "Não sei" não é enviado.
- Repositório sem GitHub Actions: os testes passam a ser rodados localmente (ver README).

### Removido
- Workflows `ci.yml` e `release.yml` do GitHub Actions, e o APK publicado em Releases.
- `tool/ci_annotate.py`.

### Corrigido
- Remoção de import não usado apontado pelo `flutter analyze` (commit `10e36d5`).
- CSP do painel: `img-src` agora libera `https://tile.openstreetmap.org` (o domínio curinga não cobria o domínio raiz).
- Colunas de horário do painel não quebram linha.

## [1.0.0] - 2026-10-19

Primeira versão: orientação e triagem educativa durante episódios de fumaça no Amazonas.

### Adicionado
- Focos de calor do INPE/Programa Queimadas por satélite (MODIS, NOAA-20, Suomi NPP), com recorte do Amazonas e do Brasil.
- Qualidade do ar estimada por modelo (Open-Meteo, CAMS) para 9 sedes do Amazonas.
- Mapa da comunidade com registros anonimizados e agregados por área (~1 km).
- Questionário de sintomas com triagem em 4 níveis e perfil de vulnerabilidade.
- Orientações por nível de risco e cartão do CIT-AM.
- API FastAPI com PostgreSQL 16, Docker Compose e testes automatizados.
- Pipeline no GitHub Actions: testes do servidor (SQLite e PostgreSQL), teste do Compose, análise e testes do Flutter, e APK anexado ao release ao enviar a tag `vX.Y.Z`.

[Não lançado]: https://github.com/micael-oliveira-ufam/respirar-amazonas/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/micael-oliveira-ufam/respirar-amazonas/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/micael-oliveira-ufam/respirar-amazonas/releases/tag/v1.0.0
