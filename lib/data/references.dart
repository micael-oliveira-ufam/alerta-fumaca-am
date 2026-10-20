/// Referências do questionário e da orientação, com o que foi (e o que NÃO foi) verificado.
///
/// Regra deste arquivo: cada referência só afirma o que o desenvolvedor leu no
/// documento. O que é decisão do projeto (e não das fontes) fica marcado como tal.
class Reference {
  const Reference({
    required this.id,
    required this.citation,
    required this.url,
    required this.used,
    this.caveat,
  });

  final int id;

  /// Citação completa.
  final String citation;
  final String url;

  /// Para que o app usa esta fonte.
  final String used;

  /// Limite da verificação ou ressalva.
  final String? caveat;
}

const references = <Reference>[
  Reference(
    id: 1,
    citation: 'Centers for Disease Control and Prevention (CDC). Wildfire Smoke Exposure '
        'Poses Threat to At-Risk Populations. Health Alert Network (HAN) message '
        'CDCHAN-00495, 30 jun. 2023.',
    url: 'https://www.cdc.gov/han/2023/han00495.html',
    used: 'Lista de sintomas (tosse, falta de ar, chiado, dor no peito, palpitações, '
        'irritação nos olhos, dor de cabeça, fadiga); grupos de risco (asma, DPOC, doença '
        'cardiovascular, crianças, idosos, gestantes); N95 ou P100 ao sair em fumaça '
        'visível; ficar em ambiente fechado, com janelas e portas fechadas; purificador '
        'de ar ou cômodo de ar mais limpo.',
    caveat: 'O documento não traz uma lista de sinais de emergência: apenas orienta '
        '"buscar atendimento quando necessário".',
  ),
  Reference(
    id: 2,
    citation: 'U.S. Environmental Protection Agency (EPA). Wildfire Smoke: A Guide for '
        'Public Health Officials. EPA-452/R-21-901, set. 2021 (rev. 2019).',
    url: 'https://www.airnow.gov/sites/default/files/2021-09/wildfire-smoke-guide-forward_0.pdf',
    used: 'Grupos de maior risco, incluindo pessoas com doenças respiratórias ou '
        'cardiovasculares, crianças, idosos, gestantes, pessoas de menor condição '
        'socioeconômica e trabalhadores ao ar livre; reduzir a atividade e ficar em '
        'ambiente com ar filtrado; filtros MERV 13 ou superior e purificadores que não '
        'emitam ozônio; respirador N95 ou P100 bem ajustado ao rosto; máscaras cirúrgicas e '
        'de papel de uma tira não são recomendadas; respiradores não são feitos para crianças.',
    caveat: 'Lidos apenas a parte inicial, o sumário e o resumo executivo (o arquivo '
        'indicado é o trecho inicial do guia, via leitura automatizada), não os capítulos '
        'completos. Confira o guia completo no AirNow.',
  ),
  Reference(
    id: 3,
    citation: 'Ministério da Saúde (Brasil). Nota com orientações para evitar a exposição '
        'à fumaça intensa e à neblina de queimadas, ago. 2024.',
    url: 'https://agenciabrasil.ebc.com.br/saude/noticia/2024-08/confira-as-orientacoes-para-amenizar-efeitos-da-fumaca-na-saude',
    used: 'Contexto nacional de orientação à população sobre fumaça de queimadas.',
    caveat: 'NÃO consultei o texto original da nota: só localizei a divulgação na imprensa '
        '(Agência Brasil) e o conteúdo dessa matéria não foi lido. Nenhuma pergunta ou '
        'regra do app se apoia em um trecho específico desta fonte. Confira a nota '
        'oficial em gov.br/saude.',
  ),
];

/// Origem de cada pergunta: quais referências sustentam o item e o que é decisão do projeto.
class QuestionSource {
  const QuestionSource(this.question, this.refs, this.note, {this.projectOnly = false});

  final String question;
  final List<int> refs;
  final String note;

  /// `true` quando a pergunta é escolha do projeto, sem trecho específico nas fontes lidas.
  final bool projectOnly;
}

const questionSources = <QuestionSource>[
  QuestionSource(
    'Sintomas respiratórios (tosse, garganta, nariz, chiado, falta de ar)',
    [1, 2],
    'Tosse, falta de ar e chiado constam no CDC; irritação respiratória consta no resumo da EPA. '
        '"Garganta irritada" e "nariz entupido ou escorrendo" são descrições leigas de irritação '
        'das vias aéreas superiores, formuladas pelo projeto.',
  ),
  QuestionSource(
    'Olhos ardendo ou lacrimejando, dor de cabeça, cansaço',
    [1],
    'Irritação ocular, dor de cabeça e fadiga constam no CDC.',
  ),
  QuestionSource(
    'Dor ou aperto no peito, coração acelerado',
    [1],
    'Dor no peito e palpitações constam no CDC.',
  ),
  QuestionSource(
    'Tontura ou sensação de desmaio',
    [],
    'Sinal de alarme incluído pelo projeto; não consta na lista de sintomas do CDC lido.',
    projectOnly: true,
  ),
  QuestionSource(
    'Onde você está e se há fumaça visível',
    [1, 2],
    'Ficar em ambiente fechado e a fumaça visível como critério para usar proteção constam no CDC e na EPA.',
  ),
  QuestionSource(
    'Máscara usada',
    [1, 2],
    'N95/P100 (CDC e EPA); cirúrgica não recomendada (EPA). A pergunta usa "PFF2" por ser o '
        'nome brasileiro; a equivalência com N95 é uma suposição do projeto, não está nas fontes lidas.',
  ),
  QuestionSource(
    'Tempo ao ar livre e atividade física intensa',
    [2],
    'Reduzir a atividade durante a fumaça consta na EPA. Os cortes de 1 h e 4 h do tempo de '
        'exposição são escolha do projeto (provisórios).',
  ),
  QuestionSource(
    'Trabalho ao ar livre',
    [2],
    'Trabalhadores ao ar livre aparecem como grupo de maior risco no resumo da EPA.',
  ),
  QuestionSource(
    'Ar filtrado ou cômodo protegido',
    [1, 2],
    'Purificador de ar, cômodo de ar mais limpo e filtros MERV 13 constam no CDC e na EPA.',
  ),
  QuestionSource(
    'Idoso, gestante, criança, doença respiratória ou cardíaca crônica',
    [1, 2],
    'Grupos de risco listados nas duas fontes.',
  ),
  QuestionSource(
    'Imunidade reduzida',
    [],
    'Incluída pelo projeto por cautela; não aparece nos grupos de risco dos trechos lidos do CDC e da EPA.',
    projectOnly: true,
  ),
  QuestionSource(
    'Medicação à mão, medicação que não alivia, sintomas piorando',
    [1],
    'O CDC orienta buscar atendimento quando necessário. Usar "remédio não alivia" e "piorando" '
        'como gatilhos de alerta é critério do projeto.',
    projectOnly: true,
  ),
];

/// Aviso sobre a pontuação, exibido na tela de referências.
const scoringNotice =
    'A classificação em baixo, moderado, alto e emergência usa pontos por sintoma, tempo de '
    'exposição e perfil, com limiares (8 e 15 pontos) definidos pelo projeto. Eles NÃO vêm '
    'de uma escala clínica validada nem das fontes acima e não foram testados com pacientes. '
    'Trate o resultado como orientação educativa, não como diagnóstico.';
