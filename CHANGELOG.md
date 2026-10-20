# Changelog

Todas as mudanças notáveis do Alerta Fumaça AM (app e servidor) estão aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e a versão segue [SemVer](https://semver.org/lang/pt-BR/):

- **MAIOR**: mudança que quebra compatibilidade (API, formato de dados ou fluxo que exige reinstalação).
- **MENOR**: funcionalidade nova compatível com as anteriores.
- **PATCH**: correção sem funcionalidade nova.

Cada versão aponta para o commit de release (tag `vX.Y.Z`). Como publicar: `tool/versao.py` (ver README, seção "Versionamento").

## [Não lançado]

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

[Não lançado]: https://github.com/micael-oliveira-ufam/alerta-fumaca-am/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/micael-oliveira-ufam/alerta-fumaca-am/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/micael-oliveira-ufam/alerta-fumaca-am/releases/tag/v1.0.0
