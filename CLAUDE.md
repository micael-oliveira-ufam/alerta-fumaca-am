# CLAUDE.md — Alerta Fumaça AM

Instruções permanentes para o agente (Claude Code) que trabalha neste repositório.
**Leia este arquivo inteiro antes de qualquer alteração.** Ele tem quatro partes:

1. [Ordens obrigatórias](#1-ordens-obrigatórias-ao-agente) — o que o agente DEVE fazer sempre.
2. [Diretrizes de comportamento (SKILL anexada)](#2-diretrizes-de-comportamento-skill-anexada) — texto original, sem alterações.
3. [O projeto](#3-o-projeto) — o que é, como está organizado e como rodar.
4. [Histórico detalhado](#4-histórico-detalhado-do-que-foi-feito) — o que já foi feito, na ordem, e o que ficou pendente ou não verificado.

Autores: Micael Davi Lima de Oliveira e Elias de Souza Barros (FCF · UFAM).
Repositório: https://github.com/micael-oliveira-ufam/respirar-amazonas (ramo `main`).

---

## 1. Ordens obrigatórias ao agente

Estas ordens têm prioridade sobre qualquer preferência de estilo do agente. As diretrizes da seção 2 complementam estas ordens; em caso de conflito, **valem estas**.

### 1.1 Postura científica (a mais importante)

O usuário é cientista: precisa garantir **integridade dos dados e reprodutibilidade**.

1. **Nunca inventar dado.** Número, telefone, URL, citação, versão de biblioteca, resultado de teste ou comportamento de API só entram no código ou na resposta se foram **vistos** (em fonte lida, em saída de comando executado) nesta sessão ou estão registrados neste arquivo como verificados.
2. **Separar sempre “verificado” de “não verificado”**, na resposta e no código (comentários, `caveat`, rótulos do app). Os rótulos *Conferido em fonte*, *Parcialmente conferido* e *Texto da equipe, fonte não consultada* vivem **só nos dados** (`lib/data/pdf_content.dart`) e na lista de pendências deste arquivo; **o app NÃO os exibe** (ver 1.4).
3. **Dizer o que não foi executado.** O ambiente do agente **não tem Flutter nem Dart**. Todo código Dart é escrito sem compilar. O agente deve dizer isso e pedir que o usuário rode `flutter analyze` e `flutter test`, e depois **trazer os resultados reais** de volta.
4. **Fonte de texto de saúde.** Texto de saúde (humana ou veterinária) fornecido pela equipe é preservado, mas cada afirmação sem fonte lida recebe o rótulo de não verificada. Se uma afirmação puder causar dano (telefone de emergência, dose, conduta), o agente **sinaliza** e propõe a correção em vez de aplicar em silêncio. Ajustes feitos pelo agente a um texto da equipe devem ser **declarados** ao usuário e na própria nota do cartão.
5. **Reprodutibilidade.** Comandos exatos, versões e caminhos devem constar na resposta ou no README. Dependência nova é registrada no `pubspec.yaml` ou no `server/requirements.txt`. Resultado de teste é citado com a contagem real.
6. **Se não souber ou não conseguir verificar, dizer.** Nunca preencher a lacuna com uma suposição apresentada como fato.

### 1.4 Este arquivo (a SKILL) descreve a versão FINAL para o usuário

Regra do usuário (20/10/2026): tudo o que o usuário final vê deve estar **o mais correto e alinhado possível**, como produto final.

- **Nenhuma nota interna na interface**: nada de "texto da equipe", "não verificado", "não consultei", pendências ou selos de verificação. Cada cartão de saúde mostra só **"Referências: [n] fonte"**. O estado de verificação fica nos dados, neste arquivo (seção de pendências) e na resposta ao usuário.
- Botões enxutos; sem passos redundantes. Sem telas vazias: gráficos aparecem mesmo sem dados, com mensagem clara.
- Erros técnicos nunca vão cruas ao usuário: mensagem em português, dizendo o que fazer.
- Antes de mexer em UI, perguntar-se: "isto é o que o usuário final deveria ler?"

### 1.2 Idioma e tom

- Responder **em português do Brasil**, com detalhe (preferência permanente do usuário: “seja sempre detalhista nas explicações”).
- Textos do app, comentários de código, mensagens de commit e `CHANGELOG.md` em português.
- Nomes de identificadores de código podem ficar em inglês ou português, seguindo o que o arquivo já usa.

### 1.3 Perguntar os próximos passos, sempre com escolhas

**Ao terminar qualquer tarefa, o agente SEMPRE encerra perguntando quais são os próximos passos e oferecendo escolhas.**

Regras de formato:

1. Oferecer de **2 a 4 opções concretas** e mutuamente exclusivas, cada uma com uma linha dizendo o que acontece se for escolhida.
2. Marcar a opção que o agente recomenda como **(Recomendada)** e colocá-la em primeiro lugar, dizendo por quê.
3. Permitir resposta livre (“ou diga outra coisa”).
4. Em ambiente com a ferramenta `AskUserQuestion`, usá-la. Sem ela, escrever as opções em lista numerada no fim da resposta.
5. Incluir nas opções, quando fizer sentido: o que está **pendente de verificação** pelo usuário (rodar testes, `git push` de tags, confirmar telefones), próxima funcionalidade e dívidas conhecidas.
6. **Antes de começar** trabalho grande, ambíguo, caro de refazer ou irreversível, perguntar o escopo com escolhas (diretriz 1 da seção 2). Para tarefa clara, começar e perguntar os próximos passos no fim.
7. Nunca encerrar com “posso ajudar em mais algo?” genérico. A pergunta deve listar escolhas específicas ao projeto.

Exemplo de fecho:

> **Próximos passos — o que você prefere?**
> 1. **(Recomendada) Rodar `flutter analyze` e `flutter test` e me enviar a saída** — é o único jeito de verificar o Dart novo; corrijo o que aparecer.
> 2. **Implementar notificações locais do alerta roxo** — avisa o usuário com o app fechado; exige a dependência `flutter_local_notifications`.
> 3. **Confirmar os telefones do CIT** — remove o aviso do app depois que você validar com o CIT.
> 4. **Outra coisa** — descreva.

### 1.4 Regras do repositório

- **Sem GitHub Actions e sem APK no repositório.** O usuário pediu explicitamente: o repositório não compila o APK nem usa Actions. O APK é gerado localmente por `tool/gerar_apk.sh`. Não recriar `.github/workflows/` nem commitar `*.apk`.
- **Nunca commitar segredos.** `.env`, senhas, `ADMIN_TOKEN`, chaves e dados reais de usuários ficam fora do Git (ver `.gitignore`). Se um segredo aparecer em saída ou arquivo, avisar o usuário.
- **Nome do app:** exibido como **RespirAR Amazonas** (desde a 1.3.0; antes era "Alerta Fumaça AM"). O pacote Dart é `respirar_amazonas` e o repositório é `respirar-amazonas` (desde a 1.3.1). Ao trocar o nome de novo, atualizar `appDisplayName`, `tool/apply_platform_config.py`, textos do app e do servidor, README e subir `kLgpdTermsVersion` (o nome aparece no termo).
- **Tela cheia:** o app abre em modo imersivo (`immersiveSticky`), reaplicado quando o app volta ao primeiro plano.
- **Privacidade (LGPD):** nada de dado pessoal novo sem passar pelo termo de consentimento. Localização é anonimizada antes do envio. Qualquer campo novo no servidor deve ser opcional e discutido antes.
- **Caminho do projeto sem acentos e sem espaços.** Pastas como `Projeto Alerta Fumaça AM` quebram o servidor de análise do Dart (“Unexpected end of input”). Avisar o usuário se vir esse caminho.
- **Versionamento (SemVer) obrigatório**, ver 1.5.
- **Mensagens de commit** em português, no imperativo, com o corpo explicando o porquê, e **terminando com as linhas de atribuição** indicadas pelo ambiente (formato atual):
  ```
  Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TbEDFVGCDSk8ajLx5M467Z
  ```
  Se o ambiente informar outro modelo ou sessão, usar o que ele informar. Só commitar ou dar `push` quando o usuário pedir ou quando a tarefa em curso incluir isso.
- **Tags não sobem do sandbox do agente** (o proxy devolve 403 para `git push` de tags). Criar a tag localmente e **avisar o usuário** de que ele precisa rodar `git push origin vX.Y.Z`.
- **Não usar `pkill -f`** no sandbox: ele mata o próprio shell (saída 144). Parar processos por PID.
- **Não commitar arquivos gerados** (`build/`, `dist/`, `android/`, `ios/`, zips). O pacote final em `.zip` é entregue ao usuário por fora do Git.

### 1.5 Versionamento — fluxo obrigatório

Fonte única: o arquivo `VERSION`. O script `tool/versao.py` sincroniza `pubspec.yaml` (`version: X.Y.Z+N`), `lib/data/app_info.dart` (`kAppVersion`) e `server/app/main.py` (`APP_VERSION`) e move a seção `## [Não lançado]` do `CHANGELOG.md`.

1. Durante o trabalho, registrar cada mudança em `## [Não lançado]` do `CHANGELOG.md` (seções *Adicionado*, *Alterado*, *Corrigido*, *Removido*), em português, dizendo **o porquê**.
2. Ao fechar uma entrega: `python3 tool/versao.py nova patch|minor|major` (ou `nova X.Y.Z`).
   - **PATCH**: correção sem funcionalidade nova.
   - **MENOR**: funcionalidade nova compatível.
   - **MAIOR**: quebra de compatibilidade (API, formato de dados, reinstalação).
3. Conferir com `python3 tool/versao.py verificar` e rodar `python3 tool/test_versao.py`.
4. Commit de release, tag local `vX.Y.Z`, avisar o usuário do `git push origin vX.Y.Z`.

### 1.6 Verificações antes de entregar

Executar e relatar a saída real:

```bash
cd server && python3 -m pytest -q          # testes do servidor (SQLite)
python3 tool/test_versao.py                # testes do versionamento
python3 tool/versao.py verificar           # versões sincronizadas
bash -n tool/*.sh                          # sintaxe dos scripts
```

Para o Dart, o agente **não consegue** rodar. Conferir pelo menos o balanceamento de parênteses/colchetes e, em seguida, pedir ao usuário:

```bash
flutter pub get
flutter analyze
flutter test
```

### 1.7 Entrega

- Arquivo pronto para o usuário: enviar com `SendUserFile`. Pacote final: `.zip` da versão atual (`respirar-amazonas-vX.Y.Z-<commit>.zip`), sem `.git`, `build`, `dist`, `.env`.
- Ao final, dizer em poucas linhas: o que mudou, o que foi verificado, o que **não** foi, e o que o usuário precisa rodar.
- Terminar com a pergunta de próximos passos (ordem 1.3).

---

## 2. Diretrizes de comportamento (SKILL anexada)

> Texto original, mantido sem alterações. Fonte: arquivo `CLAUDE.md` anexado pelo usuário.

# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

### Como as diretrizes se aplicam aqui

- *Think Before Coding* + ordem 1.3: dúvida real vira pergunta com escolhas **antes** de implementar.
- *Simplicity First*: nada de funcionalidade especulativa (ex.: não criar sistema de push “por precaução”).
- *Surgical Changes*: toda linha alterada deve se ligar ao pedido; achou código morto alheio, **mencione, não apague**. (Neste projeto isso já se aplica a avisos do analisador que não são do trecho em edição.)
- *Goal-Driven*: cada mudança vem com teste ou com critério de verificação explícito. Para bug, primeiro um teste que reproduz.

---

## 3. O projeto

**Alerta Fumaça AM** é um app Flutter (Android/iOS) com servidor FastAPI + PostgreSQL (Docker) para orientação, triagem educativa e vigilância comunitária de fumaça de queimadas no Amazonas. Projeto acadêmico (UFAM/FCF). É **orientação educativa, não diagnóstico**.

### 3.1 Estrutura

```
VERSION                  versão única (SemVer)
CHANGELOG.md             histórico por versão (Keep a Changelog)
pubspec.yaml             app Flutter (version X.Y.Z+N)
analysis_options.yaml    flutter_lints; ignora build/dist/android/ios
lib/
  main.dart              modo imersivo, tema, rotas
  data/                  textos e constantes: guidance_content, pdf_content, references, app_info
  logic/                 regras puras (testáveis): risk_assessment, context_advice, map_layers, fire_stats…
  models/                modelos de dados
  services/              INPE (focos), Open-Meteo (ar), API do servidor, localização
  screens/               telas (home, questionário, mapa, estatísticas, referências, sobre, LGPD, info_screen)
  widgets/               componentes (ui, choice_widgets, cit_card, info_card, keep_alive_page)
test/                    testes Dart (flutter test)
server/                  FastAPI + SQLAlchemy 2 + psycopg3 + painel; testes em server/tests
tool/                    gerar_apk.sh, iniciar_servidor.sh, versao.py (+ testes)
docker-compose.yml       servidor + banco + túnel Cloudflare
```

### 3.2 Comandos

| Objetivo | Comando |
|---|---|
| Gerar APK | `bash tool/gerar_apk.sh` (saída em `dist/`, com `SHA256SUMS`) |
| Requisitos no Linux | `bash tool/instalar_requisitos_linux.sh` |
| Requisitos no macOS | `bash tool/instalar_requisitos_macos.sh` |
| Abrir emulador e rodar | `bash tool/abrir_emulador.sh ios|android [URL]` |
| Gerar iOS | `bash tool/gerar_ios.sh simulador|dispositivo [URL]` (dispositivo = .ipa sem assinatura) |
| Subir servidor | `bash tool/iniciar_servidor.sh` (cria `.env` com segredos aleatórios; painel em `127.0.0.1:8080`) |
| Testes do servidor | `cd server && python3 -m pytest -q` |
| Testes do app | `flutter test` |
| Análise estática | `flutter analyze` |
| Ver/sincronizar versão | `python3 tool/versao.py mostrar|verificar|sincronizar` |
| Nova versão | `python3 tool/versao.py nova patch|minor|major|X.Y.Z` |

Ambiente do usuário (informado): agora **Linux** (antes macOS, com Flutter 3.47.7 e Dart 3.13.5). `pubspec.yaml` exige `sdk: '>=3.6.0 <4.0.0'`.

### 3.3 Fontes externas (todas dependem de internet)

- **INPE / TerraBrasilis (WFS):** focos de calor. Consulta com tempo limite de 30 s e 2 repetições.
- **Open-Meteo Air Quality (modelo CAMS):** estimativa, ~45 km, **não** substitui o IQAr oficial. Uso gratuito só não comercial; atribuição obrigatória. O formato de resposta foi escrito a partir da documentação e **não foi conferido ao vivo** pelo agente.
- **NASA GIBS (WMTS):** camadas de fundo/aerossol/térmica do mapa. Nomes de camada **não verificados** ao vivo.
- **Servidor próprio:** recebe respostas anonimizadas (`POST /respostas`, idempotente).

### 3.4 O que funciona sem internet

Orientações, triagem (cálculo local), conteúdo educativo (proteção, sintomas, farmácia caseira, pets, mitos) e telefones (SAMU 192, CIT) estão embutidos no app. Mapas, focos, qualidade do ar e envio ao servidor exigem internet. O envio fica pendente localmente quando não há rede (`report_repository`/`answer_sync`).

---

## 4. Histórico detalhado do que foi feito

Ordem cronológica. “Verificado” = executado ou lido pelo agente; “Não verificado” = depende do usuário.

### 4.1 Versão 1.0.0 (commit `eb29899`)
- App com focos MODIS/NOAA-20/Suomi (INPE), qualidade do ar (Open-Meteo), mapa comunitário, estatísticas de sintomas e orientações por nível de risco.
- API FastAPI + PostgreSQL com testes (SQLite).
- **Verificado:** testes do servidor. **Não verificado:** compilação do Dart pelo agente.

### 4.2 Termo de privacidade (LGPD) — `638ded1`
- Tela de consentimento na primeira abertura; nada é enviado sem aceite.

### 4.3 CI removido — `f8c0dba` em diante
- O usuário pediu que o repositório **não compile o APK nem use GitHub Actions**. Workflow e APK removidos. Ver ordem 1.4.

### 4.4 Painel em tempo real e servidor — `2dac1e0`
- Painel (`127.0.0.1:8080`) com login por `X-Admin-Token`: KPIs, série de 48 h, mapa, últimas respostas e contexto agregado.
- Túnel Cloudflare (*quick tunnel*) com link aleatório a cada início, exibido no painel com QR code. O endereço do servidor é colado em *Sobre* no app.
- Coluna `contexto` opcional em `respostas`, com migração idempotente; colunas `ctx_*` no CSV.
- **Verificado:** 65 testes do servidor (SQLite) passaram. **Não verificado:** Docker Compose real (Docker Hub bloqueado no sandbox).

### 4.5 Questionário, interface e mapa — `09eff61`
- Questionário em 4 etapas + resultado; botões **circulares** (`CircleChoiceRow`, `SeverityPicker`, `YesNoRow`); 10 perguntas de contexto que **não alteram a pontuação**.
- Tela **Referências** (CDC HAN 00495, EPA-452/R-21-901, nota do Ministério da Saúde via imprensa) com ressalvas do que foi lido.
- Mapas **sem rotação** (`InteractionOptions`), botões de zoom, localização, camadas e barra de escala.
- Tela cheia; nome exibido “Alerta Fumaça AM”; home com grade de ações circulares.
- **Limiares de pontuação (8 e 15 pontos) são escolha do projeto**, não de escala clínica validada. Ver `scoringNotice`.

### 4.6 Scripts de pacote final — `f8c0dba`
- `tool/gerar_apk.sh` e `tool/iniciar_servidor.sh`.

### 4.7 Versionamento — `fbe55a7` (v1.1.0)
- `VERSION`, `tool/versao.py`, `CHANGELOG.md`, testes. Tags `v1.0.0` e `v1.1.0` existem **só localmente** (push de tag dá 403 no sandbox).

### 4.8 Correções feitas a partir de erros reais do usuário
| Erro relatado | Causa | Correção |
|---|---|---|
| `sed: 1: ".env ": invalid command code .` no macOS | `sed -i` do GNU não funciona no BSD | `awk` (`definir_var`) — `5e897bd` |
| `sha256sum` ausente no macOS | comando só existe no GNU | fallback `shasum -a 256` |
| Servidor de análise do Dart: `Unexpected end of input` | caminho do projeto com acento/espaço (“Projeto Alerta Fumaça AM”) | mover a pasta; aviso no script e no README — `666687a` |
| `flutter test`: falha em `lgpd_test` | `ListTile` sobre `DecoratedBox` colorido | cor movida para `Material` — `af33d70` |
| `flutter analyze`: 7 infos `const` + erro em `widget_test.dart` | `const` faltando; teste padrão do `flutter create` usa `MyApp` | `const` inserido; script remove o teste padrão — `3a4b0e8` |
| Focos do INPE só carregavam após abrir “qualidade do ar” | `TabBarView` destruía a aba não visível | `KeepAlivePage` + repetição automática (2×) + tempo limite 30 s — `3f3e422`. **Causa exata da falha da 1ª consulta NÃO confirmada**; pedido o texto de “Detalhes técnicos” ao usuário |

Resultados que o usuário já reportou: `flutter analyze` com 8 problemas (agora corrigidos) e `flutter test` com 104 aprovados + a falha de LGPD (corrigida). **Resultados posteriores a `3f3e422` não foram reportados.**

### 4.9 Conteúdo do documento “TEXTOS_APP_FUMAÇA.pdf” — versão 1.2.0

Pedido: “Implemente tudo o que foi anexado no pdf.” Implementado em `lib/data/pdf_content.dart` (conteúdo) + `lib/widgets/info_card.dart` e `lib/screens/info_screen.dart` (apresentação).

| Item do PDF | Onde está no app | Verificação do conteúdo |
|---|---|---|
| Tela 1: máscaras (PFF2/N95) | *O que fazer agora* → “Proteção: máscaras e ambiente” | **Parcial.** CDC e EPA (lidos) recomendam N95/P100 e a EPA desaconselha cirúrgica/papel. PFF2 = N95 e locais de distribuição: texto da equipe |
| Tela 1: purificador vs. umidificador | idem | **Parcial.** Purificador/ambiente fechado: CDC e EPA. Umidificador, toalhas molhadas e baldes: sem fonte lida |
| Tela 2: entenda seus sintomas (CO, gases irritantes, PM2,5) | botão no resultado do questionário | **Parcial.** Sintomas constam no CDC; mecanismos (CO, acroleína/formaldeído) sem fonte lida |
| Tela 3: farmácia caseira (soro 0,9%, nebulização, alerta de remédios, chá e mel) | home → “Farmácia caseira” | **Texto da equipe, sem fonte lida** |
| Tela 4: painel CIT (HUGV/UFAM, 24 h, discagem direta, quando ligar) | `CitCard(detailed: true)` em *O que fazer agora* e na tela de sintomas | 0800 722 6001 informado pela equipe e **não confirmado**; (92) 3305-4700 consta na carta de serviços do HUGV |
| Seção “E os nossos pets?” (3 cartões) | home → “E os nossos pets?” | **Parcial.** AVMA (“Wildfire smoke and animals”, lida): pets dentro de casa, sinais de alerta, evitar exercício. Focinho curto, água fresca, limpeza dos olhos e remédios humanos: sem fonte lida |
| Lista de referências (7) + SES-AM/FVS-AM | tela *Referências* → “Fontes dos textos educativos” (numeradas 4 a 10) | Cada uma com “Verificação:”; CFMV, ASBAI, OPAS/OMS, Vigifis, SES-AM/FVS-AM **não consultadas** |
| Tela 5.1: alerta roxo | banner na aba de qualidade do ar quando algum ponto tem AQI ≥ 201 (`alertPurpleMinAqi`) | Faixa “muito ruim” da escala dos EUA; usar 201 como limiar do alerta é decisão do projeto |
| Tela 5.1: alerta laranja (mudança de vento) e notificações push | **Não implementado** | Exige previsão de vento/trajetória e serviço de push; o app não tem nenhum dos dois |
| Tela 5.2: funcionamento offline | conteúdo embutido; aviso em *O que fazer agora* | Verdadeiro para textos e triagem; mapas, focos e envio exigem internet (dito no aviso) |
| Tela 5.3: Fato ou Fake? (leite, lavar PFF2, queimar casca/borra) | home → “Fato ou Fake?” | Texto da equipe; um item parcial (CDC: evitar fontes internas de fumaça) |
| Créditos: “Elias de Souza Barros” | tela *Sobre* e README | — |
| Sugestões de nome (RespirAR Amazonas etc.) e slogan | **Não aplicado** (decisão de nome é do usuário) | — |

**Ajustes que o agente fez nos textos da equipe (e declarou no app):**
1. No CIT “quando ligar”, acrescentou que em confusão mental ou desmaio se liga **primeiro ao SAMU (192)**.
2. Retirou “autoridade máxima” (sem fonte).
3. Retirou a comparação com “ácido fraco”.
4. Retirou “caem diretamente na corrente sanguínea” e “riscos toxicológicos a longo prazo”.
5. Em “leite”, retirou a frase de que soro fisiológico é líquido essencial; em “queimar casca/borra”, retirou a parte do monóxido de carbono.
6. Manteve o “Alerta vermelho de farmácia” (prudência), marcando a frase sobre o coração como não conferida.

### 4.11 Renomeação para RespirAR Amazonas e nova splash — versão 1.3.0
- Pedido: “Altere o nome do aplicativo para RespirAR Amazonas, melhore a tela de splash fornecendo mais informações e também uma animação melhor ao iniciar.”
- Antes, o agente discutiu vantagens e desvantagens dos nomes. **Verificado:** VIGIAR é nome de programa de vigilância em saúde (por isso foi desaconselhado). **Não verificado:** disponibilidade de “RespirAR” nas lojas, no INPI e em domínios.
- Nome trocado em app, servidor, scripts e README; `kLgpdTermsVersion` 1.0 -> 1.1 (o usuário reaceita o termo).
- Splash: fumaça animada, anéis de pulso, entrada escalonada, recursos, versão, barra de progresso, toque para pular, respeita “remover animações”. Dart não compilado no sandbox; aparência e fluidez **não foram vistas** (nem em emulador).
- O ícone do app (`assets/icon`) e a splash nativa **não foram alterados** e ainda são os da marca anterior; refazer o ícone é decisão aberta.

### 4.12 Renomeação do pacote e do repositório — versão 1.3.1
- Pedido: “Altere o nome do pacote e do repositório.” Os nomes não foram especificados; o agente **inferiu** `respirar_amazonas` (pacote Dart) e `respirar-amazonas` (repositório) a partir do nome do app. Confirmar.
- Pacote: `pubspec.yaml`, todos os imports `package:` em `test/`, `tool/gerar_apk.sh`, README e testes de `tool/`. **Verificado:** nenhum `package:alerta_fumaca_am` restante (grep).
- **Efeito no Android/iOS:** o identificador do app deriva de `--org br.ufam.fcf` + nome do pacote (`br.ufam.fcf.respirar_amazonas`). Quem tem a versão antiga instalada terá **um segundo app**, não uma atualização. Aceitável antes de publicar; confirmar com o usuário.
- **Repositório:** o agente **não consegue renomear** (o proxy devolve 403 para escrita de configurações). O usuário deve renomear em *Settings → General → Repository name* e depois rodar `git remote set-url origin https://github.com/micael-oliveira-ufam/respirar-amazonas.git`. O GitHub redireciona o nome antigo.
- A pasta local também pode ser renomeada (sem acentos e sem espaços).

### 4.13 iOS e emuladores — versão 1.4.0
- Pedido: gerar também uma versão para iOS e fornecer todo o código para baixar os pacotes e abrir o emulador.
- Scripts novos em `tool/`: `gerar_ios.sh`, `abrir_emulador.sh`, `instalar_requisitos_macos.sh`, `_preparar.sh`. Detalhes e limites no README.
- **Verificado:** `bash -n` e execução completa dos fluxos com comandos simulados (`uname`, `flutter`, `xcrun`, `pod`, `adb` falsos) em Linux: ordem dos passos, argumentos, geração do zip/.ipa e patch do `Info.plist`. **Não verificado:** build iOS real, Simulador, Android real, `brew install --cask flutter`, `xcodebuild -downloadPlatform iOS`.
- O `.ipa` é **sem assinatura**: não instala em iPhone; exige conta Apple Developer.
- Corrigido o bug do `DEFINES` vazio no bash 3.2 do macOS (também em `gerar_apk.sh`).

### 4.14 Painel público sem senha — versão 1.5.0
- Pedido: melhorar muito a interface do painel online com todos os dados enviados, especialmente os sintomas mais relatados, **sem senha e de livre visualização**.
- Decisão do agente (a confirmar com o usuário): a visão pública mostra **dados agregados**, não respostas individuais, porque o termo LGPD do app promete anonimização e mínimos de divulgação (5 respostas; 3 por área). O painel do administrador (token, `127.0.0.1:8080`) continua com as últimas respostas; a exportação CSV segue com token.
- Implementação: `server/app/publico.py`, `server/app/rotulos.py`, `server/app/static_publico/` (HTML, CSS, JS), rotas `/`, `/assets`, `/vendor`, `/publico/painel` em `main.py`.
- **Verificado:** 75 testes do servidor passaram (10 novos); a página foi aberta num Chromium (Playwright) com 240 respostas de teste geradas por mim, em desktop, celular e escuro, sem erros de JavaScript (só falhas de carregar o mapa do OpenStreetMap, bloqueado no sandbox). **Não verificado:** o mapa com tiles reais, o acesso pelo túnel Cloudflare, uso com PostgreSQL e comportamento com muito tráfego. Os dados da demonstração eram **fictícios** e não foram commitados.
- Ainda aberto: o termo LGPD não cita perfil, exposição e contexto como estatísticas públicas.

### 4.15 Erro "No Podfile found" — versão 1.5.1
- O usuário colou: `[!] No Podfile' found in the project directory.` ao rodar o fluxo iOS. Causa provável: `ios/Podfile` ainda não existia (o `flutter create` não o gera nesse ponto); **a causa exata no Mac do usuário não foi confirmada**. Correção em `_preparar.sh` (ver CHANGELOG). Se persistir, pedir a saída de `ls ios` e de `flutter build ios --config-only --no-codesign`.

### 4.16 Ajustes de produto final — versão 1.6.0
- **Questionário:** removidos "Refazer" e "Compartilhar localização". Ao final, pergunta por resposta: "Quer compartilhar suas respostas para estudos epidemiológicos?" Sim → envio ao servidor (com localização ~1 km se permitida; sem ela se negada); Não → nada sai. Causa de o envio "não ocorrer": app sem URL do servidor na compilação (modo local) e fluxo antigo de consentimento em caixas de diálogo. Termo LGPD v1.2.
- **Referências no lugar de selos** em Fato ou Fake, Farmácia Caseira, Pets e CIT (UI sem notas internas; ver 1.4). Mapa de referências: farmácia → [4, 7, 8]; pets → [6, 10]; mitos → [9] e [5, 9], [1, 9]; sintomas → [1, 2, 4, 7]. **Atenção:** as fontes 5, 6, 7, 8 e 9 **continuam NÃO consultadas** (ver pendências); estão citadas como referência por pedido do usuário.
- **Sintomas mais relatados:** gráficos sempre visíveis (zerados se não houver dados), nível de risco e **bairros de Manaus** (`server/app/bairros.py`: coordenada de ~1 km → bairro via Nominatim, cache em `celulas_bairro`, mínimo 3 respostas por bairro, só Manaus).
- **Mapa "Hoje" sem focos:** causa provável (**não confirmada**: o INPE não é acessível daqui) é a camada `focos_hoje_*` vir vazia. Correção: "Hoje" usa a camada de 48 h e recorta o dia atual de Manaus (UTC-4) no app (`FireWindow.filter`) e o servidor mapeia `today` para a camada de 48 h.
- **Datas de satélite:** `lib/services/gibs_availability.dart` testa um tile (zoom 3, Manaus) por data e mostra só as datas com imagem. **Não verificado ao vivo** (GIBS inacessível daqui): se a GIBS devolver 200 com tile em branco para datas sem dado, a data aparecerá; o aviso de falha de tile segue como segunda proteção.
- **Sobre:** removido "Alterar endereço"; o link da plataforma abre no navegador. `ApiConfig.save/override` ficou sem tela (código morto, mantido por testes). Desenvolvedores com foto e e-mail (`assets/images/dev_*.jpg`). **Suposição declarada:** confirmado pelo usuário: Micael = óculos e crachá LNCC; Elias = camiseta cinza.
- **Plataforma online:** seções de bairros, focos de calor (KPIs, por satélite/dia/município, mapa de calor), links de desmatamento e desenvolvedores. **Desmatamento: só links oficiais** (TerraBrasilis); nomes de camadas WMS do DETER/PRODES não foram verificados e não foram usados.
- **Verificado:** testes do servidor; a página pública em Chromium com focos simulados (dados fictícios). **Não verificado:** todo o Dart novo (não compila aqui), Nominatim, GIBS, INPE.

### 4.17 Fotos corrigidas, fontes e teste de comunicação — versão 1.6.1
- Usuário corrigiu: **Micael = óculos e crachá LNCC; Elias = camiseta cinza**. Fotos trocadas.
- Fontes [8] (VIGIAR, Ministério da Saúde, 2ª ed.) e [9] (SES-AM/FVS-RCP, 18/09/2024) foram lidas e as referências dos mitos reajustadas ([8], [8,9], [1,8]); [5], [6], [7] seguem não consultadas.
- `tool/teste_comunicacao.py`: envia ao servidor o mesmo JSON do app (11 sintomas, contexto, coordenada a 2 casas, data com microssegundos). **Resultado real (servidor local, HTTP, SQLite):** /health 200; novo 201; reenvio 200 `duplicado:true`; sem localização 201; nível inválido e sem sintomas 422 (o app trata 4xx como "rejeitado", sem reenvio); painel público com 10 respostas: suficiente, 11 sintomas, 1 área. **Não testado:** o app Dart de fato, o túnel Cloudflare, PostgreSQL.

### 4.18 Validação das fontes e dos textos de saúde — versão 1.6.2
- Pedido do usuário: descobrir todas as fontes pendentes e validar todas as informações. **Método:** busca na web, leitura de cada documento com `WebFetch` e comparação afirmação a afirmação. Resultado por tema (tudo em `lib/data/pdf_content.dart`, notas internas em `verificationNote`):
  - **Máscaras:** confirmado (MS/VIGIAR: N95, PFF2 ou P100; OMS Europa: FFP2 ou N95; SES-AM via imprensa; CDC; EPA). Retirado "locais de distribuição" (sem fonte).
  - **Purificador/umidificador:** purificador confirmado (CDC, EPA, MS); "HEPA" retirado. Umidificador e toalhas/baldes: só opinião de especialistas em reportagens (CNN Brasil, Correio Braziliense); **nenhuma fonte oficial lida confirma que ajudam contra a fumaça**.
  - **Monóxido de carbono:** mecanismo confirmado no Manual MSD. **Acroleína/formaldeído: nenhuma fonte lida os cita; nomes retirados.**
  - **Soro nasal/ocular:** só médicos em reportagens; **nebulização com soro removida** (sem fonte).
  - **Mel:** menores de 1 ano confirmado (Anvisa via CFM, 2008); o benefício para a garganta segue sem fonte.
  - **Pets:** AVMA e CRMV-AM (via A Crítica). **Removidos** sem fonte: raças de focinho curto, gato de boca aberta, limpeza dos olhos com soro, pano úmido no corpo. CFMV: nada localizado; trocado pelo CRMV-AM.
  - **Mitos:** leite (DGS Portugal via notícia: "não é antídoto do monóxido de carbono"); máscara (3M: não limpar, descartar úmida/suja; retirado "álcool destrói a filtragem"); casca/borra (ASBAI, DGS: evitar combustão; os itens específicos não constam nas fontes).
  - **CIT:** 0800 722 6001 **confirmado** em 3 fontes; **(92) 3305-4700 NÃO confirmado** e trocado por (92) 3305-4702 (Abracit, Ministério da Saúde). Texto "inclusive por fumaça" retirado.
  - **Ações por nível de risco** (`levelActions`), limiares 8/15 e cortes de 1 h/4 h: **continuam critério do projeto, sem validação clínica**; exigem revisão por profissional de saúde.
- **Limites:** parte das fontes foi lida só pela imprensa; as páginas foram lidas por um resumidor automático (`WebFetch`), então trechos literais devem ser conferidos nos links antes de publicar em periódico. Nenhum documento original da SES-AM/FVS-RCP ou da DGS foi lido.
- Teste de comunicação e fotos: ver 4.17.

### 4.19 Servidor no Linux — versão 1.6.3
- Erro do usuário: `unknown shorthand flag: 'd' in -d` ao rodar `tool/iniciar_servidor.sh`. **Causa provável (não confirmada na máquina dele):** Docker Engine sem o plugin Compose (`docker compose` inexistente). Correção: detecção de `docker compose`/`docker-compose`, `sudo` automático, `openssl` opcional, link do túnel no fim. **Verificado:** `bash -n` e 3 cenários com `docker` simulado (só docker-compose v1; sem Compose; sem permissão). **Não testado em Docker real.**

### 4.20 Porta ocupada — versão 1.6.4
- Erro do usuário: `Bind for 0.0.0.0:8080 failed: port is already allocated` (painel). Causa: outro processo/contêiner já escuta em 8080 (**qual programa é, não sei**; o usuário pode descobrir com `ss -ltnp | grep :8080`). Correção: o script escolhe a próxima porta livre (`PAINEL_PORT`/`API_PORT` no `.env`). **Verificado** com `docker` simulado e uma porta 8080 realmente ocupada, inclusive com a API já rodando; **não testado em Docker real**.

### 4.21 Porta automática com nova tentativa — versão 1.6.5
- Pedido: publicar o servidor automaticamente numa porta livre. Já havia a detecção prévia (1.6.4); agora também há **nova tentativa** quando o Docker recusa a porta ("port is already allocated"). **Verificado** com `docker` simulado que falha na 8080 e passa na 8081 (o endereço do painel impresso é o novo). **Não testado em Docker real.** O túnel usa a porta interna da API (`api:8000`), que não muda.

### 4.22 Flutter no Linux — versão 1.6.6
- Erro do usuário: `Flutter não encontrado` ao rodar `tool/gerar_apk.sh` no Linux (o Flutter não estava instalado/no PATH). Novo `tool/instalar_requisitos_linux.sh` (dependências, JDK 17, Flutter por `git clone`, Android SDK por command-line tools, PATH) e `tool/_ambiente.sh` (detecção automática). Dependências conforme a documentação oficial do Flutter para Linux (`curl git unzip xz-utils zip libglu1-mesa`). **Não está na documentação lida:** o método `git clone`, o JDK 17 e `flutter config --android-sdk` (escolhas minhas). O número do zip das command-line tools é descoberto na página do Android, **não verificado ao vivo** (inacessível daqui). **Verificado:** `bash -n` e detecção com Flutter/SDK simulados. **Não testado:** a instalação real.

### 4.23 Mapa web bloqueado pelo OpenStreetMap — versão 1.6.7
- Print do usuário: tiles com "Access blocked – App is not following the tile usage policy" (403) no painel público via túnel. Causa: `Referrer-Policy: no-referrer` no servidor (a política de tiles do OSM exige Referer). **Verificado:** o cabeçalho estava nos dois painéis (`main.py`, `painel.py`) e o 84º teste confere o novo valor. **Não verificado:** o carregamento real dos tiles (OSM inacessível daqui); confirmar recarregando a página com Ctrl+F5. O app Flutter não é afetado (já usa `userAgentPackageName`).

### 4.24 Broken pipe no instalador — versão 1.6.8
- Saída do usuário: o Flutter baixou o Dart SDK e compilou a ferramenta, mas terminou em `FileSystemException: writeFrom failed ... Broken pipe`. Causa: **bug meu** (`flutter --version | head -1`, versão 1.6.6). **Verificado:** reproduzido o padrão e a correção (captura em variável) com um `flutter` falso; o trecho de `java -version` recebeu a mesma correção. **Não testado:** Flutter real. Lição: nunca cortar a saída de `flutter` com `head` em pipe.

### 4.25 Android SDK sem plataformas — versão 1.6.9
- Saída do usuário (`flutter doctor -v`, Linux Mint 22.3): Flutter 3.47.7 / Dart 3.13.5 **OK**; Android toolchain ✗ (`~/Android/Sdk/platforms` vazio, "Unable to locate Android SDK"); Chrome e rede OK; Linux toolchain ✗ (clang, CMake, ninja, GTK: irrelevante para APK). Causa do item Android: o instalador instalava só `platform-tools` (**falha minha**). Correção: instala também a plataforma e o build-tools mais recentes. **Verificado:** o filtro com `sdkmanager` falso (ignora `-rc1`/`-ext5`, escolhe o maior número; caminho sem rede). **Não verificado:** o formato real de `sdkmanager --list` (assumi colunas separadas por `|`), se a plataforma mais nova é a que o Flutter/Gradle pede (o Gradle baixa o que faltar com as licenças aceitas) e se o passo 3 (cmdline-tools) já rodou na máquina do usuário.

### 4.26 Domínio fixo respira-amazonas.cloud — versão 1.7.0
- Pedido: "O aplicativo permanece sem ter conexão com o banco de dados, incapaz de enviar informações. Conecte-se agora a um domínio fixo: respira-amazonas.cloud". **Causa provável (não confirmada na máquina dele):** o app só envia se foi compilado com `API_BASE_URL` (o campo "alterar endereço" foi removido na 1.6.0), e o link do túnel rápido muda a cada início; um APK compilado com link antigo, ou sem link, não envia.
- **O agente NÃO consegue conectar ao domínio**: o sandbox não alcança `respira-amazonas.cloud` (proxy 403) e não tem a conta Cloudflare do usuário. Feito: serviço `tunnel_dominio` (perfil `dominio`), `TUNNEL_TOKEN`, `iniciar_servidor.sh` com token e conferência de `/health`, e URL padrão `https://respira-amazonas.cloud` nos scripts de compilação (`URL_SERVIDOR_PADRAO` em `tool/_ambiente.sh`; o Dart continua com padrão vazio para não quebrar `flutter test`). Comando do túnel conforme a documentação da Cloudflare (`cloudflared tunnel run --token` / `TUNNEL_TOKEN`; `--no-autoupdate` entre `tunnel` e `run`); a página oficial de criação não cita o comando do Docker, então o formato usado vem da página "run parameters".
- **Verificado:** fluxo do script com `docker` e `curl` simulados (token + domínio no ar, token + domínio fora do ar, sem token, token vindo do `.env`); 22 testes em `tool/`. **Não verificado:** túnel e domínio reais, DNS/propriedade do domínio na Cloudflare, HTTPS, e o envio real do app ao domínio. O usuário precisa criar o túnel e a rota no painel da Cloudflare e fornecer o token.

### 4.27 Nome do domínio corrigido — versão 1.7.1
- O usuário escreveu `respira-amazonas.cloud` no pedido; a zona real na Cloudflare é **`respirar-amazonas.cloud`** (print da tela de DNS). O nome sem "r" gerava `DNS_PROBE_FINISHED_NXDOMAIN`. **Erro de propagação meu:** usei o nome digitado sem conferir; ao receber um nome de domínio, pedir/conferir a grafia na fonte (painel do registrador). Todas as menções atuais foram trocadas; as seções 4.26 e o CHANGELOG da 1.7.0 ficam como histórico.
- **Registros DNS vistos no print:** `A respirar-amazonas.cloud → 2.57.91.91` (proxied) e `CNAME www → respirar-amazonas.cloud` (proxied); *DNS Setup: Full*. **Não verificado:** de quem é o IP 2.57.91.91 (provável página de estacionamento do registrador; não confirmei). O registro A do apex precisa ser removido para que a rota do túnel possa criar o CNAME do túnel no mesmo nome.

### 4.28 Painel completo e atualização — versão 1.8.0
- **Limite científico:** a qualidade do ar vem do CAMS via Open-Meteo, grade de ~45 km; **não existe valor por bairro**. Mostrar um número por bairro seria inventar precisão. O painel diz isso na tela. Bairros de Manaus continuam só no ranking de relatos do app.
- **Não verificado:** nomes das camadas NASA GIBS (reutilizados do app, sem acesso ao serviço), comportamento ao vivo de OpenTopoMap/Open-Meteo/INPE, formato de `current.time` do Open-Meteo, todo o Dart novo (`app_update.dart`, `stats_cache.dart`, `update_banner.dart`, `stats_screen.dart`) e o fluxo real de instalação do APK. Verificado: 130 testes do servidor, página no Chromium com dados fictícios (desktop e 390 px, sem rolagem horizontal).
- **Municípios:** `server/app/dados/municipios_am.csv` (62, coordenadas de sede) com procedência em `LEIAME.md`.
- **Atualização:** o app consulta `/app/versao` (sem dados pessoais). Sem loja, o Android exige confirmação do usuário; não prometer atualização silenciosa. Para forçar o aviso, defina `APP_VERSAO_MINIMA` no `.env`. Fluxo: `tool/gerar_apk.sh` (grava `dist/VERSION.txt`) e o servidor passa a anunciar a versão nova sem reiniciar.
- **Tela de sintomas:** regra de projeto: tela de dados nunca depende só da rede; mostrar local primeiro, servidor depois, cópia local em falha.

### 4.29 Alertas de qualidade do ar — versão 1.9.0
- **Decisão do usuário (20/10/2026):** "Gere notificações no celular com alertas sobre qualidade do ar". Limiares padrão (US AQI ≥101) e repetição de 12 h foram escolha minha, ajustável pelo usuário no app; **validar com a equipe de saúde**.
- **Fontes de medição real pesquisadas (sem integrar):** SELVA (UEA/MPAM, sensores PurpleAir de baixo custo, PM2,5; o site não mostra API, termos nem dados abertos e desaconselha uso científico/regulatório); IQAir (comercial). Sem autorização, **não raspar** esses dados. Caminho correto: pedir à UEA/MPAM (projeto EducAIR).
- **Pacotes (conferidos na documentação do pub.dev em 20/10/2026, não compilados):** `flutter_local_notifications` 22.3.2 (`initialize(settings:)`, `show(id:, title:, body:, notificationDetails:)`) e `workmanager` 0.10.10 (`initialize(callback)`, `registerPeriodicTask(..., frequency, constraints, existingWorkPolicy)`; mínimo 15 min). **Se o build do APK falhar por causa deles**, remova as duas linhas do `pubspec.yaml` e o uso em `lib/services/air_alert_*.dart`, `lib/main.dart` e `home_screen.dart`, e me envie o erro.
- **Não verificado:** compilação Dart, build Gradle com os plugins, entrega da notificação em aparelho real, comportamento do segundo plano com economia de bateria, permissão POST_NOTIFICATIONS no Android 13+.
- `RadioListTile` evitado de propósito (parâmetros obsoletos geram *info* no `flutter analyze`, que bloqueia `gerar_apk.sh`).

### 4.10 Pendências e dívidas conhecidas
- **Rodar `flutter pub get`, `flutter analyze` e `flutter test`** após a 1.2.0 e enviar a saída (todo o Dart novo é não compilado pelo agente).
- `git push origin v1.0.0 v1.1.0 v1.2.0` (tags locais).
- CIT: 0800 722 6001 e (92) 3305-4702 confirmados (20/10/2026); **reconfirmar por telefone antes de divulgar** (as fontes são páginas de terceiros e imprensa). O (92) 3305-4700 foi retirado.
- Fontes de saúde: todas as indicadas pela equipe foram localizadas e lidas em 20/10/2026 (ver 4.18). Restam ressalvas: SES-AM/FVS-RCP [9] e DGS [14] só via imprensa; CFMV não tem documento localizado (substituído pelo CRMV-AM [6]); OMS/OPAS [7] é de 1999 e voltada a governos.
- Revisão por profissional de saúde e médico-veterinário antes de publicar os textos de farmácia caseira e pets.
- Notificações push/locais do alerta roxo e alerta laranja (precisa de previsão de vento): decisão do usuário.
- Causa raiz da falha inicial da consulta ao INPE: aguardando o texto de “Detalhes técnicos”.
- Nome do app (alternativas sugeridas no PDF): decisão do usuário.
- Camadas GIBS e formato da resposta do Open-Meteo: conferir ao vivo.
- Limiares de pontuação (8 e 15): validar com a equipe de saúde.

---

## 5. Resumo para o agente (leia se estiver com pressa)

1. Português, detalhado, **sem inventar**; separar verificado de não verificado.
2. Dart não compila aqui: peça `flutter analyze` e `flutter test` e use os resultados reais.
3. Mudança pequena e rastreável ao pedido; registre no `CHANGELOG.md`; versão por `tool/versao.py`.
4. Sem Actions, sem APK no Git, sem segredos.
5. Tags não sobem do sandbox: avise o usuário.
6. Texto de saúde: rotule a verificação; sinalize o que pode causar dano.
7. **Termine sempre perguntando os próximos passos, com 2 a 4 escolhas e uma recomendada.**
