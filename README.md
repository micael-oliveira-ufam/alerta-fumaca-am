# RespirAR Amazonas

App Flutter (Android e iOS) para **orientação e triagem educativa** durante episódios de fumaça no Amazonas, com focos de calor por satélite (INPE), qualidade do ar estimada e estatísticas anonimizadas dos sintomas. Acompanha um servidor (FastAPI + PostgreSQL) que sobe com um comando via Docker.

Projeto da UFAM / FCF. Desenvolvedores: Micael Davi Lima de Oliveira e Elias de Souza Barros.

> **Aviso.** O app **não faz diagnóstico** e não substitui atendimento médico. Em emergência, ligue **192 (SAMU)**.

## Instalar

Este repositório contém **apenas o código-fonte**: não há APK pronto nem pipeline de compilação. Gere o app na sua máquina (seção "Compilar o app"). Sem servidor configurado (`API_BASE_URL` ou o endereço no cartão *Sobre → Servidor*), o app roda em **modo local**: nenhuma resposta sai do aparelho.

Nome exibido do aplicativo: **RespirAR Amazonas** (o script `tool/apply_platform_config.py` grava esse nome no Android e no iOS). O app abre em **tela cheia** (modo imersivo; as barras do sistema voltam com um deslize na borda da tela).

## O que o app faz

| Tela | Conteúdo |
|---|---|
| **Início** | Botões circulares para as funções, atalho às referências e ao SAMU (192). |
| **O que fazer agora** | Orientações por nível de risco. |
| **Como estou me sentindo** | Questionário em 4 etapas com botões circulares: **sintomas** (11), **exposição** (local, fumaça visível, tempo ao ar livre, máscara, exercício, trabalho ao ar livre, ar filtrado), **sobre você** (idoso, gestante, criança, doença respiratória/cardíaca, imunidade, medicação à mão) e **situação atual** (piorando, remédio não alivia). Classificação em 4 níveis + cuidados para a situação. As perguntas de contexto são opcionais e **não entram na pontuação**. Ao final, o usuário decide (com consentimento separado) se envia a resposta anônima ao servidor. |
| **Referências** | Fontes de cada pergunta, o que foi verificado e o que é critério do projeto (ver abaixo). |
| **Mapas** | Todos os mapas: **sem rotação** (zoom por pinça não gira mais), botões circulares de aproximar/afastar, minha localização, visão inicial e **camadas**, barra de escala. Camadas: fundo *Ruas* (OpenStreetMap) ou *Satélite* (NASA GIBS, cor real), sobreposições *Fumaça e aerossóis* e *Focos de calor VIIRS* (NASA GIBS) com escolha do dia, além das chaves de cada aba (focos do INPE, densidade). |
| **Mapa · Focos · INPE** | Focos de calor de **hoje** ou das **últimas 48 h**, com **Amazonas** (padrão, enfatizado) ou **Brasil**. Filtro por satélite: **MODIS (Aqua e Terra)**, **NOAA-20** e **Suomi NPP** (padrão), mais NOAA-21 opcional. Resumo (totais, parcela do Amazonas, por satélite, estado, bioma, ranking de municípios), mapa e lista. |
| **Mapa · Qualidade do ar** | Índice de qualidade do ar (padrão EUA), PM2,5 e PM10 **estimados por modelo** para 9 sedes municipais do Amazonas. |
| **Mapa · Comunidade** | Mapa centrado em Manaus ou no GPS (com permissão), com áreas agregadas (~1 km). Com servidor: dados coletivos; sem servidor: só os do aparelho. |
| **Sintomas mais relatados** | Ranking dos sintomas com % das respostas, distribuição leve/moderado/intenso e gravidade média. Vem do servidor (todas as respostas coletadas) ou, sem servidor, só do aparelho. |
| **CIT-AM** | Cartão com o Centro de Informações Toxicológicas do Amazonas. |
| **Sobre** | Desenvolvedores, logos, fontes de dados, termo LGPD e **endereço do servidor** (colar o link do painel). |

## Fontes de dados e o que "tempo real" significa

### Focos de calor — INPE / Programa Queimadas (TerraBrasilis, WFS 2.0.0, GeoJSON)

- Camadas `dados_abertos:focos_hoje_br_todosats` e `dados_abertos:focos_48h_br_todosats` (todos os satélites; as camadas `*_satref` trazem só o satélite de referência e não permitem separar por satélite).
- Campo `satelite` (valores conferidos por contagem no servidor do INPE): `AQUA_M-T`, `TERRA_M-T` (**MODIS**), `NOAA-20`, `NOAA-21`, `NPP-375` e `NPP-375D` (**Suomi NPP**). Satélites geoestacionários (GOES, MSG) existem na camada, mas ficaram de fora de propósito.
- O significado do sufixo "D" em `NPP-375D` **não foi confirmado** em documentação; as duas variantes são somadas como Suomi NPP.
- Filtro no servidor do INPE: `CQL_FILTER=estado='AMAZONAS' AND satelite IN (...)`.
- **"Tempo real"** = o dado mais recente publicado pelo INPE, consultado ao abrir a tela, ao trocar filtros, ao tocar em atualizar e a cada 10 minutos. O INPE publica com atraso em relação à passagem do satélite; o app mostra o horário da detecção mais recente.
- Um foco é uma detecção térmica por satélite. **Não é medição da qualidade do ar** nem confirmação de incêndio.
- A cor/tamanho por FRP (10 e 50 MW) é uma escala de exibição escolhida para leitura, **não** um limiar de risco à saúde.

### Qualidade do ar — Open-Meteo Air Quality API (modelo CAMS)

- Variáveis: `us_aqi`, `pm2_5`, `pm10`, resolução do modelo da ordem de dezenas de km.
- É **estimativa de modelo**, não medição de estação, e o índice é o **dos EUA, não o IQAr oficial brasileiro**.
- Uso **não comercial**, com atribuição ao Open-Meteo (exibida no app). Revise os termos se o uso mudar.
- As coordenadas das 9 cidades (`lib/services/air_quality_service.dart`) são aproximadas; revise antes de usar em pesquisa.

## Servidor e banco de dados (Docker)

```bash
cp .env.example .env          # edite POSTGRES_PASSWORD e ADMIN_TOKEN (ex.: openssl rand -hex 24)
docker compose up -d --build  # sobe PostgreSQL 16 + API + painel + túnel da Cloudflare
curl http://localhost:8000/health
bash tool/smoke_test_api.sh   # envia 1 resposta de teste e confere os endpoints
# painel em tempo real: http://localhost:8080
```

- O banco **não é publicado no host**; só a API o acessa pela rede interna. Dados no volume `pgdata`.
- `docker compose down` mantém os dados. `docker compose down -v` **apaga tudo**.
- Documentação interativa da API: `http://localhost:8000/docs`.

| Endpoint | Função |
|---|---|
| `POST /respostas` | Registra uma resposta. 201 novo, 200 duplicado (idempotente por `submission_id`), 422 inválido, 429 limite. |
| `GET /estatisticas?dias=30` | Sintomas mais relatados, níveis de risco, série diária. |
| `GET /mapa?horas=72` | Áreas (~1 km) com respostas. |
| `GET /focos?window=today\|last48h&scope=amazonas\|brasil&satellites=...` | Focos do INPE com cache no servidor. |
| `GET /respostas/export.csv` | Exportação completa (cabeçalho `X-Admin-Token`; desativada se `ADMIN_TOKEN` vazio). |
| `GET /health` | Verifica API e banco. |

Configuração (`.env`): `POSTGRES_*`, `API_PORT`, `ADMIN_TOKEN`, `INPE_CACHE_SECONDS`, `RATE_LIMIT_PER_MIN`, `MIN_RESPOSTAS_PUBLICAS` (padrão 5), `MIN_RESPOSTAS_CELULA` (padrão 3), `GEOCODER_ATIVO` (padrão `true`: consulta o Nominatim para dar nome de bairro às áreas de ~1 km de Manaus; política de uso: ≤1 consulta/s, com `User-Agent` identificado e cache em `celulas_bairro`), `GEOCODER_CONTATO`.

### Painel em tempo real e link público (Cloudflare)

- **Painel** (`http://localhost:8080`, só neste computador): total e ritmo de respostas, níveis de risco, sintomas mais relatados, respostas por hora, mapa de áreas (~1 km), perfil, últimas respostas anônimas, estado do banco e o **link do servidor com QR code**. Atualiza a cada 5 s (consulta periódica, não conexão contínua). Exige o `ADMIN_TOKEN` quando definido. É outro processo e **não passa pelo túnel**.
- **Painel público (sem senha):** o próprio link do túnel (`https://<palavras>.trycloudflare.com/`) abre uma página com os dados **agregados** dos usuários: sintomas mais relatados (ranking com leve/moderado/intenso, ordenável por frequência ou intensidade), níveis de risco, respostas por dia, mapa de áreas (~1 km), **bairros de Manaus mais afetados**, perfil, tempo de exposição e contexto, **focos de calor do INPE em detalhe** (por satélite, dia e município, com mapa de calor via `leaflet.heat` 0.2.0, copiado de `server/app/static/vendor/leaflet-heat`), links oficiais de desmatamento (TerraBrasilis) e os desenvolvedores, com filtro de 24 h / 7 / 30 / 90 dias e atualização a cada 15 s. Qualquer pessoa com o link vê; não há login. Os mesmos dados saem em JSON em `GET /publico/painel?dias=30` (aberto, com CORS liberado). **Regras de privacidade aplicadas no servidor** (as do termo LGPD): abaixo de `MIN_RESPOSTAS_PUBLICAS` respostas só aparece o total; área do mapa só com `MIN_RESPOSTAS_CELULA`+ respostas; contagens de perfil/contexto menores que `MIN_RESPOSTAS_CELULA` viram "menos de N". **Não são públicos:** respostas individuais, horário de cada envio, exportação CSV e o painel do administrador (`127.0.0.1:8080`, com token). O resultado é guardado 10 s em memória para aguentar muitos acessos. Como o endereço do túnel é aleatório e muda a cada início, divulgue o link atual (o painel do administrador o mostra com QR code) ou use um túnel nomeado/domínio próprio para um endereço fixo.
- **Link aleatório:** o serviço `tunnel` abre um *túnel rápido* da Cloudflare (`cloudflared`, sem conta) e sorteia `https://<palavras>.trycloudflare.com` **cada vez que inicia**. O painel lê o link atual e o exibe.
- **No app:** o endereço é definido **na compilação** (`tool/gerar_apk.sh` usa `https://respirar-amazonas.cloud` por padrão; ou `<URL>`, ou `--dart-define=API_BASE_URL=...`); não há campo para alterá-lo. Em *Sobre → Plataforma online* o app apenas mostra o link, que o usuário abre no navegador. Ao final de cada questionário o app pergunta se a pessoa quer compartilhar as respostas para estudos epidemiológicos; só com "Sim" há envio.
- **Atenção (só no link aleatório), o link muda** quando o túnel reinicia; um app compilado com o link antigo deixa de enviar até ser recompilado. Por isso o padrão é o domínio fixo. Os envios que falharam ficam guardados no aparelho e são reenviados (o `submission_id` evita duplicar).
- **Domínio fixo (`respirar-amazonas.cloud`):** o serviço `tunnel_dominio` usa um túnel *nomeado* da Cloudflare, então o endereço não muda e o app compilado continua enviando. Passo a passo (exige conta Cloudflare com o domínio adicionado):
  1. No painel da Cloudflare (*Zero Trust → Networks → Tunnels*) crie um túnel e copie o **token**.
  2. No mesmo túnel, publique uma rota (*Published application*) com o domínio `respirar-amazonas.cloud` e o serviço `http://api:8000`.
  3. Rode `TUNNEL_TOKEN=<token> bash tool/iniciar_servidor.sh` (ou rode sem a variável e cole o token quando o script pedir). O script grava o token no `.env` (fora do Git), liga o perfil `dominio`, define `PUBLIC_URL` e confere `https://respirar-amazonas.cloud/health`.
  4. Compile o app com `bash tool/gerar_apk.sh`: sem argumento ele já aponta para `https://respirar-amazonas.cloud`. Outro servidor: passe a URL; sem servidor: `--local`.
  Caminhos conforme a documentação da Cloudflare (comando `cloudflared tunnel --no-autoupdate run` com o token em `TUNNEL_TOKEN`). **Verificado:** o fluxo do script com `docker` e `curl` simulados. **Não testado:** o túnel e o domínio reais.
- **Limitações:** a Cloudflare descreve os túneis rápidos como para testes, sem garantia de disponibilidade. O computador precisa ficar ligado.
- **Painel público (1.8.0):** além do descrito acima, tem download em CSV (`/publico/export.csv`), qualidade do ar por município (`/publico/qualidade-ar`, estimativa de modelo de ~45 km, sem valor por bairro), horário detalhado dos focos, mais mapas (relevo, satélite, NASA GIBS), fontes oficiais e, no cabeçalho, download do app com QR code. O APK é lido de `dist/` (gerado por `tool/gerar_apk.sh`; a pasta é montada em `/srv/dist`).
- **Alertas de qualidade do ar (1.9.0, Android):** tela "Alertas de qualidade do ar" no app; notificações locais quando o índice (estimativa de modelo) do município escolhido passa do limite. Servidor: `GET /app/ar?cod=<IBGE>`.
- **Atualizações depois de instalado:** o app instalado consulta `GET /app/versao` e avisa quando há versão nova (abre o download; o Android pede a confirmação). `APP_VERSAO_MINIMA` no `.env` torna o aviso permanente para versões antigas. A página aberta avisa quando o servidor passa a servir uma versão nova (`/publico/versao`). Para publicar uma atualização: `tool/gerar_apk.sh` e, se precisar, `docker compose up -d --build`.
- **Segurança:** o link dá acesso à API **de coleta** e ao painel público (somente leitura, dados agregados); ele não é uma senha. Qualquer pessoa que o tenha pode enviar respostas, inclusive falsas. As estatísticas **não são verificadas** e não devem ser usadas como dado científico sem tratamento. O limite de envios usa o IP real (`CF-Connecting-IP`) só em memória; isso só é seguro porque a API escuta apenas em `127.0.0.1` (`API_BIND`).
- Para desligar o túnel: deixe `COMPOSE_PROFILES=` vazio no `.env`.

### Privacidade (LGPD)

- **Não há** nome, telefone, e-mail, conta, identificador de aparelho ou IP gravados. O `submission_id` é um UUID aleatório **por envio** (só evita duplicar em reenvio).
- Coordenadas arredondadas a **2 casas (~1,1 km)** no app **e** no servidor, e só se o usuário marcar essa opção.
- Estatísticas só são divulgadas com ao menos 5 respostas no período; áreas do mapa, com ao menos 3.
- O log de acesso do uvicorn fica desligado (`--no-access-log`).
- **Termo de privacidade (LGPD)** exibido na primeira abertura e a cada nova versão (`lib/data/lgpd_terms.dart`, `kLgpdTermsVersion`); sem aceitar, o app não é usado. Aceitar o termo **não** autoriza envio.
- Três consentimentos separados: uso local da localização; envio de dados de saúde ao servidor; inclusão da localização.
- Como os registros são anônimos, **não é possível apagar um envio depois**; o diálogo avisa isso. Dado de saúde é dado pessoal sensível: **defina a base legal, o controlador e a retenção** antes de operar o servidor com o público.
- Publique a API **atrás de HTTPS** (proxy reverso). O Compose expõe HTTP na porta 8000.

## Início rápido (pacote final)

```bash
tool/iniciar_servidor.sh                          # servidor: cria o .env com segredos e sobe o Docker
tool/gerar_apk.sh                                 # APK em dist/Alerta-Fumaca-AM.apk, ligado a https://respirar-amazonas.cloud
tool/gerar_apk.sh https://SEU-SERVIDOR            # outro servidor
tool/gerar_apk.sh --local                         # modo local (nada é enviado)
```

- `iniciar_servidor.sh` precisa de Docker com acesso ao Docker Hub (imagens `postgres:16-alpine` e `python:3.12-slim`).
- **Linux:** `bash tool/iniciar_servidor.sh` detecta sozinho o Compose (`docker compose` v2 ou `docker-compose` v1), usa `sudo` se o usuário não estiver no grupo `docker` e, no fim, mostra o link do túnel e o comando `gerar_apk.sh` com ele. Se aparecer `unknown shorthand flag: 'd' in -d`, o Docker está **sem o plugin Compose**: instale `docker-compose-v2` (Ubuntu/Debian), `docker-compose-plugin` (Fedora/repositório oficial) ou `docker-compose`. Para não usar `sudo`: `sudo usermod -aG docker $USER` e reinicie a sessão. Verificado só com `docker` simulado; **não testado em Docker real**.
- `gerar_apk.sh` precisa de Flutter 3.27+, Java 17 e Android SDK, e roda os testes antes de compilar. **Linux:** `bash tool/instalar_requisitos_linux.sh` instala tudo isso (apt/dnf/pacman; pede `sudo` só para pacotes do sistema) e grava o PATH; depois abra um novo terminal. O script de APK também acha sozinho o Flutter em `~/development/flutter`, `~/flutter` ou `/opt/flutter`. Se a descoberta do zip das command-line tools falhar, rode com `CMDLINE_TOOLS_URL=<zip para Linux de developer.android.com/studio>`. Verificado só com comandos simulados; **não testado numa instalação real**.
- Ambos os scripts foram escritos e revisados aqui, mas **não foram executados de ponta a ponta** neste ambiente: o Docker Hub e o Flutter estavam bloqueados. O servidor foi testado direto com Python (SQLite).

## Compilar o app

Requisito: Flutter 3.27 ou superior (desenvolvido para **3.27.x**). As pastas `android/` e `ios/` **não** são versionadas; são geradas assim:

```bash
flutter create --platforms=android,ios --org br.ufam.fcf --project-name respirar_amazonas .
rm -f test/widget_test.dart
python3 tool/apply_platform_config.py            # INTERNET, localização, discagem (idempotente)
python3 tool/apply_platform_config.py --check
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter analyze && flutter test
flutter build apk --release --dart-define=API_BASE_URL=https://api.seudominio.com.br
```

Omita `--dart-define` para o modo local (os scripts de `tool/` já passam `https://respirar-amazonas.cloud` por padrão).

## iOS e emuladores (macOS)

Requisitos: macOS, **Xcode** (App Store), Flutter e CocoaPods. O Xcode não é instalável por script; o resto sim.

```bash
# 1) Uma vez: confere/instala Homebrew-Flutter, CocoaPods, runtime do simulador iOS e roda o flutter doctor
bash tool/instalar_requisitos_macos.sh

# 2) Baixa os pacotes (pub get, precache, pods), abre o Simulador do iPhone e roda o app
bash tool/abrir_emulador.sh ios                      # modo local
bash tool/abrir_emulador.sh ios https://SEU-LINK     # com servidor

# Emulador Android (precisa de um AVD criado no Android Studio)
bash tool/abrir_emulador.sh android

# Gerar o app iOS em dist/
bash tool/gerar_ios.sh simulador                     # RespirAR-Amazonas-simulador.zip (Runner.app)
bash tool/gerar_ios.sh dispositivo [URL]             # .ipa SEM assinatura
```

Variáveis: `SIMULADOR_IOS="iPhone 16"` e `EMULADOR_ANDROID="Pixel_8"` escolhem o aparelho.

Comandos manuais equivalentes (iOS):

```bash
flutter create --platforms=android,ios --org br.ufam.fcf --project-name respirar_amazonas .   # só se ios/ não existir
python3 tool/apply_platform_config.py
flutter pub get && flutter precache --ios
(cd ios && pod install --repo-update)
open -a Simulator
flutter run                       # escolha o simulador, ou: flutter run -d <UDID>
flutter build ios --simulator --debug
```

Limites que valem saber:
- **O `.ipa` do modo `dispositivo` sai sem assinatura e não instala num iPhone.** Para instalar num aparelho ou publicar na App Store é preciso uma conta Apple Developer e configurar *Signing & Capabilities* em `ios/Runner.xcworkspace`.
- O Simulador **não faz ligações**: o botão de discagem (SAMU e CIT) só funciona num aparelho real.
- Servidor em `http://` (sem TLS) é bloqueado pelo iOS (App Transport Security). Use o link `https://` do túnel Cloudflare.
- Os scripts novos foram validados aqui apenas com comandos simulados (Linux, sem Xcode nem Flutter): a lógica dos passos foi conferida, **mas nenhum build iOS real foi feito**.

> **Por que o script de permissões.** Sem `INTERNET` no `AndroidManifest.xml` principal, um APK de release não acessa a rede (o Flutter só injeta essa permissão nos builds de debug). Confira com `python3 tool/apply_platform_config.py --check`.

### Diagnóstico pelo próprio app

| Mensagem | Causa provável | Ação |
|---|---|---|
| "Não foi possível baixar o mapa base" | Sem rede ou sem `INTERNET` | Reaplicar o script e reinstalar |
| INPE com "Failed host lookup" | Mesmo motivo, ou DNS/"DNS privado" do aparelho | Idem; ou usar o servidor próprio (`API_BASE_URL`), que consulta o INPE por você |
| "Compilado sem a permissão de localização" | `ACCESS_*_LOCATION` ausente | Reaplicar o script e reinstalar |
| "Permissão bloqueada" | Negada em definitivo | Liberar nas configurações do Android |
| `flutter analyze` falha com "Unexpected end of input" (`LspByteStreamServerChannel`) | Caminho do projeto com acentos ou espaços (ex.: `Projeto Alerta Fumaça AM`). O analisador conta bytes e caracteres de forma diferente, e a mensagem chega cortada. `flutter test` pode funcionar, porque não usa o analisador | Mover a pasta para um caminho só com letras, números e hífens, e rodar `flutter clean && flutter analyze` de novo |

## Versionamento

Uma versão só para o projeto (app e servidor), no padrão [SemVer](https://semver.org/lang/pt-BR/). A fonte é o arquivo `VERSION`; o `tool/versao.py` mantém as cópias sincronizadas (`pubspec.yaml`, `lib/data/app_info.dart`, `server/app/main.py`) e confere o `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)).

```bash
python3 tool/versao.py mostrar                 # versão e situação das cópias
python3 tool/versao.py verificar               # erro se algo divergir (também roda antes do APK)
python3 tool/versao.py nova minor              # patch | minor | major | X.Y.Z
```

Fluxo de uma release:

1. Escreva as mudanças em `CHANGELOG.md`, na seção `## [Não lançado]`, nas categorias Adicionado, Alterado, Corrigido ou Removido.
2. `python3 tool/versao.py nova minor` (ou `patch`/`major`): sobe `VERSION`, o número de build do `pubspec.yaml` (+1) e move o não lançado para a nova seção com a data.
3. Faça o commit e marque: `git tag -a vX.Y.Z -m "Versão X.Y.Z"` e `git push origin main vX.Y.Z`.

Regras: o build (`+N` do pubspec) só cresce, porque o Android exige isso para atualizar o app instalado; mudança que quebra a API ou o formato de dados é MAIOR. Os testes (`tool/test_versao.py` e `server/tests/test_versao.py`) falham se alguma cópia divergir.

Histórico de versões: `CHANGELOG.md`. Tags: `v1.0.0` (commit `eb29899`) e `v1.1.0`.

## Testes

Não há GitHub Actions neste repositório. Rode localmente:

```bash
# servidor (SQLite por padrão; defina TEST_DATABASE_URL para rodar também em PostgreSQL)
cd server && pip install -r requirements.txt pytest && pytest -q
# script de permissões/nome do app
python3 tool/test_apply_platform_config.py
# app Flutter (depois de gerar android/ios e rodar flutter pub get)
flutter analyze && flutter test
```

Nova versão: altere `version:` em `pubspec.yaml` e `kAppVersion` em `lib/data/app_info.dart`.

## Referências do questionário

Detalhadas (com ressalvas e o mapeamento pergunta → fonte) na tela **Referências** do app e em `lib/data/references.dart`.

1. CDC. *Wildfire Smoke Exposure Poses Threat to At-Risk Populations*. HAN CDCHAN-00495, 30/06/2023. <https://www.cdc.gov/han/2023/han00495.html> — sintomas, grupos de risco, N95/P100, ambiente fechado, purificador/cômodo mais limpo. **Lida.** Não traz lista de sinais de emergência.
2. U.S. EPA. *Wildfire Smoke: A Guide for Public Health Officials*. EPA-452/R-21-901 (set. 2021, rev. 2019). Trecho inicial e resumo executivo: <https://www.airnow.gov/sites/default/files/2021-09/wildfire-smoke-guide-forward_0.pdf> — grupos de risco (inclui trabalhadores ao ar livre), reduzir atividade, filtros/purificadores, N95/P100, máscara cirúrgica não recomendada. **Lido só o início e o resumo**, não os capítulos.
3. Ministério da Saúde. Nota de orientações sobre fumaça de queimadas (ago. 2024), via Agência Brasil: <https://agenciabrasil.ebc.com.br/saude/noticia/2024-08/confira-as-orientacoes-para-amenizar-efeitos-da-fumaca-na-saude>. **O texto da nota não foi consultado**; nenhuma regra do app se apoia em trecho específico dela.

O que **não** vem das fontes: a pontuação e os limiares (8 e 15 pontos), os cortes de 1 h e 4 h de exposição, a pergunta sobre tontura, a de imunidade reduzida e os gatilhos "piorando" e "remédio não alivia". São critérios do projeto, **não validados clinicamente**.

## Limitações e itens a confirmar

- **Termo LGPD**: redigido pela equipe técnica, **não revisado por jurídico**. A UFAM/FCF deve designar o controlador e o canal do encarregado (art. 41) e fixar a retenção; ajuste `lgpd_terms.dart` e incremente a versão.

- **Telefones do CIT-AM**: 0800 722 6001 e (92) 3305-4702 **confirmados em 20/10/2026** (Abracit, lista de CIATox do Ministério da Saúde, matéria de A Crítica). O (92) 3305-4700, usado antes, **não foi confirmado** e foi retirado. Reconfirme periodicamente; estão em `lib/data/guidance_content.dart` e `lib/data/pdf_content.dart`.
- **Logos da UFAM e do CIT**: confirme a autorização de uso das marcas.
- **Limiares da triagem** (`moderateThreshold`, `highThreshold`, pontos) são provisórios e **não foram validados clinicamente**.
- **Camadas de satélite da NASA (GIBS)**: os identificadores das camadas, formatos e níveis de zoom (`lib/logic/map_layers.dart`) seguem o padrão público da GIBS, mas **não foram conferidos contra o serviço** (o ambiente de desenvolvimento não alcançava o host). Se uma camada ficar em branco, o app avisa; confira o nome no catálogo da GIBS e ajuste. A imagem tem atraso, depende de nuvens e **não mede PM2,5**.
- **Interface, mapa e questionário (Dart)**: escritos sem compilador disponível na sessão. Rode `flutter analyze` e `flutter test` antes de distribuir e teste os mapas num aparelho.
- **Qualidade do ar**: estimativa de modelo (ver acima); resposta da API não conferida ao vivo no desenvolvimento (a rede do ambiente bloqueava o host), apenas por testes com amostra sintética.
- **Estatísticas dos sintomas** refletem quem usa o app e decide enviar: **não são amostra representativa** da população.
- iOS: o código é compartilhado, mas **não foi compilado nem testado** (nenhuma plataforma é compilada em CI).

## Estrutura

```
lib/            app Flutter (logic/ = regras puras e testáveis; services/ = rede; screens/)
server/         API FastAPI + SQLAlchemy + PostgreSQL (app/, tests/, Dockerfile)
test/           testes Dart (triagem, parser INPE, estatísticas, API, qualidade do ar, mapa)
tool/           permissões de plataforma, geração de ícones, smoke test da API
docker-compose.yml, .env.example
```

Regenerar ícone/logos a partir do logo da UFAM: `pip install pillow && python3 tool/generate_brand_assets.py caminho/ufam.png [caminho/cit.png]`.
