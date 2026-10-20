/// Conteúdo educativo vindo do documento "TEXTOS PARA ATUALIZAÇÃO DO APLICATIVO"
/// (equipe do projeto). Todo o texto fica EMBUTIDO no app (funciona sem internet).
///
/// O usuário vê só as REFERÊNCIAS de cada cartão. O campo [Verification] e a nota que o acompanha
/// são de uso interno (equipe e agente de IA): dizem o quanto cada afirmação foi conferida em
/// fonte lida pelo desenvolvedor e alimentam a lista de pendências no CLAUDE.md. Não são exibidos.
library;

import 'guidance_content.dart';

enum Verification {
  /// Conferido em fonte lida pelo desenvolvedor.
  checked('Conferido em fonte'),

  /// Parte conferida, parte não.
  partial('Parcialmente conferido'),

  /// Texto da equipe; a fonte indicada NÃO foi consultada.
  teamText('Texto da equipe, fonte não consultada');

  const Verification(this.label);
  final String label;
}

class InfoCardData {
  const InfoCardData({
    required this.title,
    required this.paragraphs,
    required this.verification,
    this.verificationNote,
    this.bullets = const [],
    this.bulletsTitle,
    this.tip,
    this.warning,
    this.refs = const [],
  });

  final String title;
  final List<String> paragraphs;
  final String? bulletsTitle;
  final List<String> bullets;

  /// Dica prática (destaque verde).
  final String? tip;

  /// Alerta (destaque vermelho).
  final String? warning;
  final Verification verification;
  final String? verificationNote;

  /// Números das referências em `references.dart` / [extraReferences].
  final List<int> refs;
}

// ---------------------------------------------------------------- Tela 1
// Validação de 20/10/2026: cada afirmação abaixo foi confrontada com fontes LIDAS (ver
// `extraReferences` e o CLAUDE.md, seção 4.18). As notas `verificationNote` são internas.
const protectionCards = <InfoCardData>[
  InfoCardData(
    title: 'Qual máscara realmente protege contra a fumaça?',
    paragraphs: [
      'Máscaras de pano ou cirúrgicas comuns protegem apenas contra partículas grossas e '
          'não filtram as partículas finas da fumaça, que são as mais perigosas.',
      'Para se proteger de verdade ao sair, utilize respiradores do tipo PFF2, N95 ou P100, '
          'bem ajustados ao rosto e mantidos limpos e secos.',
    ],
    tip: 'A recomendação prioritária continua sendo permanecer em ambiente interno, protegido '
        'da fumaça, com portas e janelas fechadas.',
    verification: Verification.checked,
    verificationNote: 'Conferido: Ministério da Saúde/VIGIAR (N95, PFF2 ou P100; limpas e secas; '
        'permanência em ambiente interno é prioritária), SES-AM/FVS-RCP via imprensa (pano e '
        'cirúrgica só para partículas grossas), OMS Europa (FFP2 ou N95), CDC e EPA (N95/P100; '
        'cirúrgica não recomendada). Removido o trecho sobre locais de distribuição, sem fonte.',
    refs: [1, 2, 8, 9, 11],
  ),
  InfoCardData(
    title: 'Purificador vs. Umidificador: qual a diferença?',
    paragraphs: [],
    bulletsTitle: 'Entenda cada aparelho',
    bullets: [
      'Purificador de ar: limpa o ar de um ambiente fechado, pois filtra as partículas do '
          'cômodo. Prefira modelos que não emitam ozônio.',
      'Umidificador de ar: não limpa a fumaça do ar; só aumenta a umidade, o que pode aliviar '
          'o ressecamento. Mantenha-o limpo.',
    ],
    tip: 'Sem esses aparelhos, mantenha janelas e portas fechadas nos horários de maior '
        'fumaça. Para aumentar a umidade, especialistas citam toalhas molhadas e baldes com '
        'água nos cômodos.',
    verification: Verification.partial,
    verificationNote: 'Conferido: purificador/ambiente fechado (CDC, EPA, MS/VIGIAR), sem '
        'ozônio (EPA). Umidificador e toalhas/baldes: só opiniões de especialistas em '
        'reportagens (CNN Brasil, Correio Braziliense; SES-DF orienta umidificador pela baixa '
        'umidade); nenhuma fonte oficial lida diz que ajudam contra a fumaça. "HEPA" foi '
        'retirado por não constar nas fontes lidas.',
    refs: [1, 2, 8, 16, 17],
  ),
];

// ---------------------------------------------------------------- Tela 2
const symptomExplainers = <InfoCardData>[
  InfoCardData(
    title: 'Por que sinto dor de cabeça, tontura e cansaço?',
    paragraphs: [
      'A fumaça contém monóxido de carbono (CO). Ao ser inalado, o CO se liga à hemoglobina '
          'do sangue no lugar do oxigênio e reduz o oxigênio que chega aos tecidos. Por isso '
          'podem surgir dor de cabeça, tontura e fraqueza.',
    ],
    verification: Verification.checked,
    verificationNote: 'Conferido: mecanismo e sintomas do CO no Manual MSD (afinidade pela '
        'hemoglobina, menor oferta de oxigênio, cefaleia, tontura, fraqueza); dor de cabeça e '
        'fadiga como sintomas da fumaça no CDC. O Manual MSD trata a fumaça de incêndio como '
        'fonte de CO. "Cérebro e músculos" do texto original foi retirado.',
    refs: [1, 15],
  ),
  InfoCardData(
    title: 'Por que sinto os olhos queimando, tosse seca e garganta arranhando?',
    paragraphs: [
      'A fumaça é uma mistura de gases e partículas que irrita os olhos, o nariz e a '
          'garganta. Isso causa ardência, lacrimejamento, coriza e tosse seca.',
    ],
    verification: Verification.checked,
    verificationNote: 'Conferido: irritação nos olhos, nariz e garganta e tosse seca '
        '(MS/VIGIAR, SES-AM/FVS-RCP via imprensa, CDC). Retirados os nomes acroleína e '
        'formaldeído: nenhuma fonte lida os cita.',
    refs: [1, 8, 9],
  ),
  InfoCardData(
    title: 'O perigo invisível: o que é o PM2,5?',
    paragraphs: [
      'É o material particulado fino: partículas tão pequenas que conseguem chegar às '
          'regiões profundas do pulmão. Segundo a EPA, é a maior ameaça da fumaça à saúde, '
          'especialmente para quem tem asma, DPOC ou problemas no coração.',
    ],
    verification: Verification.checked,
    verificationNote: 'Conferido: EPA (ficha EPA-452/F-26-012: "biggest threat"); grupos de '
        'risco no CDC e na EPA; chegada aos alvéolos pela fala de um pneumologista no '
        'Metrópoles. "Estresse do corpo" e "bronquite" do original foram retirados.',
    refs: [1, 2, 18, 20],
  ),
];

// ---------------------------------------------------------------- Tela 3
const homeCareCards = <InfoCardData>[
  InfoCardData(
    title: 'Hidratação das mucosas e vias aéreas',
    paragraphs: [
      'Beber líquidos constantemente ajuda a manter as vias respiratórias úmidas e mais '
          'protegidas.',
    ],
    bulletsTitle: 'Cuidados com nariz e olhos',
    bullets: [
      'Nariz: médicos recomendam a lavagem nasal com soro fisiológico 0,9%, várias vezes ao '
          'dia, para remover partículas das mucosas.',
      'Olhos: se houver só irritação, lave com soro fisiológico ou use lágrima artificial. '
          'Se houver dor ou piora, procure atendimento.',
    ],
    verification: Verification.partial,
    verificationNote: 'Conferido: hidratação (MS/VIGIAR; SES-AM via imprensa). Soro nasal e '
        'ocular: orientação de médicos citados em reportagens (CNN Brasil: infectologista e '
        'oftalmologista; Correio Braziliense: otorrinolaringologista); nenhuma fonte '
        'oficial lida cita. REMOVIDA a nebulização com soro (sem fonte).',
    refs: [8, 9, 16, 17],
  ),
  InfoCardData(
    title: 'Alerta vermelho de farmácia',
    paragraphs: [
      'Quem tem asma, DPOC ou outra doença respiratória deve seguir o plano de tratamento do '
          'seu médico e manter os medicamentos prescritos à mão. Não use por conta própria '
          'remédios de bombinha, broncodilatadores ou corticoides sem prescrição.',
    ],
    warning: 'Se os sintomas piorarem, procure atendimento médico.',
    verification: Verification.partial,
    verificationNote: 'Conferido: seguir o plano de tratamento e manter medicamentos à mão '
        '(ASBAI, MS/VIGIAR, DGS Portugal via imprensa). "Não usar sem prescrição" é prudência '
        'geral, sem fonte lida que o diga para a fumaça. Retirada a frase "sobrecarrega o '
        'coração", sem fonte.',
    refs: [5, 8, 14],
  ),
  InfoCardData(
    title: 'Alívio natural',
    paragraphs: [
      'Chás mornos e mel podem trazer conforto à garganta irritada. Eles não tratam os '
          'efeitos da fumaça.',
    ],
    warning: 'Mel somente para maiores de 1 ano. Nunca dê mel a bebês.',
    verification: Verification.partial,
    verificationNote: 'Conferido: mel e menores de 1 ano (Anvisa, via Portal Médico do CFM, '
        '2008: risco de botulismo). O conforto à garganta é senso comum, sem fonte lida; a '
        '"película protetora" do original foi retirada.',
    refs: [13],
  ),
];

// ---------------------------------------------------------------- Tela 4 (CIT)
/// Telefone local do CIT/AM: Abracit e lista de CIATox do Ministério da Saúde trazem
/// (92) 3305-4702. O (92) 3305-4700 (usado antes) NÃO foi confirmado e foi retirado.
const kCitHugvPhoneAlt = '(92) 3305-4702';
const kCitHugvPhoneAltDial = '9233054702';

const citIntro =
    'O CIT funciona no Hospital Universitário Getúlio Vargas (HUGV) da Universidade Federal '
    'do Amazonas e atende 24 horas, de forma gratuita. Orienta sobre intoxicações e exposição '
    'a substâncias químicas. Um profissional avalia o caso e diz se é possível acompanhar em '
    'casa ou se é preciso procurar atendimento.';

const citWhenToCall = <String>[
  'Se houver confusão mental, desmaio, tontura extrema ou falta de ar contínua, ligue '
      'primeiro para o SAMU (192).',
  'Para tirar dúvidas sobre exposição a substâncias tóxicas. Não é preciso ter certeza de '
      'que houve intoxicação para ligar.',
];

/// Uso interno (não exibido no app): o que foi conferido no texto do CIT.
const citVerificationNote =
    'CONFIRMADO em 20/10/2026: 0800 722 6001 (Abracit, lista de CIATox do Ministério da Saúde, '
    'matéria de A Crítica de 30/08/2026), 24 h, gratuito. Telefone local (92) 3305-4702 '
    '(Abracit e Ministério). O (92) 3305-4700 NÃO foi confirmado e foi substituído. A lista '
    'do Ministério não traz data nem horário; a matéria de A Crítica não cita fumaça entre '
    'as situações atendidas, por isso "inclusive por fumaça" foi retirado.';

// ---------------------------------------------------------------- Pets
const petCards = <InfoCardData>[
  InfoCardData(
    title: 'Como a fumaça afeta cães e gatos?',
    paragraphs: [
      'Assim como nós, cães e gatos respiram as partículas e os gases da fumaça. Animais '
          'idosos, filhotes e os que têm doenças cardíacas ou respiratórias correm maior risco.',
    ],
    bulletsTitle: 'Sinais de alerta',
    bullets: [
      'Tosse intensa ou secreção no nariz.',
      'Respiração difícil, muito rápida ou cansaço extremo.',
      'Olhos vermelhos, irritados ou lacrimejando.',
      'Fraqueza, desorientação, desmaio ou língua e gengivas arroxeadas ou muito pálidas: '
          'emergência veterinária.',
    ],
    verification: Verification.checked,
    verificationNote: 'Conferido: AVMA (tosse, respiração difícil, secreção nasal, cansaço, '
        'irritação nos olhos) e CRMV-AM via A Crítica (grupos de maior risco; sinais de '
        'alerta e emergência). REMOVIDOS: raças de focinho curto e gato de boca aberta, '
        'sem fonte lida.',
    refs: [6, 10],
  ),
  InfoCardData(
    title: 'Como proteger o seu pet em casa?',
    paragraphs: [],
    bullets: [
      'Mantenha o pet dentro de casa, com portas e janelas fechadas nos períodos de mais '
          'fumaça. Se possível, use um ambiente com ar filtrado.',
      'Evite passeios e exercícios ao ar livre nos períodos críticos. Se ele precisar sair, '
          'que seja pelo menor tempo possível.',
      'Deixe água fresca sempre disponível.',
      'Fechar as frestas com pano molhado e usar umidificador podem ajudar como medida '
          'complementar.',
      'Se o animal foi exposto à fumaça, leve-o para um local com ar mais limpo.',
    ],
    verification: Verification.checked,
    verificationNote: 'Conferido: AVMA (dentro de casa, janelas fechadas, evitar exercício) '
        'e CRMV-AM via A Crítica (portas e janelas fechadas, ar filtrado, evitar passeios, '
        'água fresca, retirar para ar mais limpo). Frestas com pano molhado e umidificador: '
        'veterinária (CRMV-RJ) no Patas da Casa, como ajuda complementar.',
    refs: [6, 10, 19],
  ),
  InfoCardData(
    title: 'Cuidados e medicação',
    paragraphs: [],
    bullets: [
      'Olhos e nariz irritados fazem parte dos sinais de alerta: leve o animal ao '
          'veterinário em vez de aplicar produtos por conta própria.',
    ],
    warning: 'Não medique o animal por conta própria: corticoides, broncodilatadores e '
        'antibióticos não devem ser usados sem avaliação profissional. Se os sintomas '
        'persistirem, procure um médico-veterinário.',
    verification: Verification.checked,
    verificationNote: 'Conferido: CRMV-AM via A Crítica (não medicar sem avaliação; cita '
        'corticoides, broncodilatadores e antibióticos). REMOVIDOS: limpeza dos olhos com '
        'soro, pano úmido no corpo e menção a xaropes/antialérgicos, sem fonte lida.',
    refs: [6],
  ),
];

// ---------------------------------------------------------------- Fato ou Fake
class MythData {
  const MythData(this.claim, this.verdict, this.explanation, this.verification, this.note,
      {required this.refs});

  final String claim;

  /// `true` = verdade, `false` = mito.
  final bool verdict;
  final String explanation;
  final Verification verification;

  /// Uso interno (não exibido): o que foi conferido.
  final String note;
  final List<int> refs;
}

const myths = <MythData>[
  MythData(
    'Tomar leite "corta" o efeito da fumaça no corpo?',
    false,
    'Mito. O leite não é antídoto do monóxido de carbono e não há estudo científico que '
        'mostre utilidade contra a fumaça. Beba água.',
    Verification.partial,
    'Conferido na nota da DGS (Portugal), lida só pela notícia da Lusa em O Minho '
        '(29/07/2025), não no original; não é fonte brasileira. Hidratação: MS/VIGIAR.',
    refs: [14, 8],
  ),
  MythData(
    'Dá para lavar a máscara PFF2/N95 e reutilizar?',
    false,
    'Mito. O fabricante 3M não recomenda nenhum tipo de limpeza ou desinfecção dos '
        'respiradores descartáveis, e máscaras úmidas ou sujas devem ser descartadas.',
    Verification.checked,
    'Conferido no boletim técnico da 3M (maio/2020, revisão 2). Retirado "o álcool destrói '
        'a filtragem eletrostática": o boletim não trata de álcool no respirador. Fonte do '
        'fabricante, não de órgão regulador.',
    refs: [12, 8],
  ),
  MythData(
    'Queimar casca de laranja ou borra de café em casa tira o cheiro de fumaça?',
    false,
    'Mito. Qualquer queima dentro de casa produz mais fumaça no ambiente. Evite velas, '
        'incenso, fogão a gás ou a lenha, fritura e cigarro, e ventile só quando a fumaça '
        'de fora permitir.',
    Verification.partial,
    'Conferido: ASBAI (evitar velas, fogão a gás ou lenha, fritura, fumo) e DGS (não usar '
        'fontes de combustão em casa; velas, incenso, tabaco). Nenhuma fonte lida cita casca '
        'de laranja ou borra de café; a inclusão é uma extensão lógica do princípio.',
    refs: [5, 14],
  ),
];

const mythsReferenceNote =
    'Referências: ASBAI, DGS (Portugal), 3M e Ministério da Saúde (VIGIAR).';

// ---------------------------------------------------------------- Alertas
const alertPurpleTitle = 'Alerta de fumaça intensa';
const alertPurpleText =
    'A qualidade do ar atingiu níveis severos na sua região neste momento. Feche portas e '
    'janelas imediatamente e use sua máscara PFF2/N95 se precisar sair.';

/// Limite do índice dos EUA a partir do qual o aplicativo mostra o alerta roxo.
/// 201 é o início da faixa "muito ruim" (ver `airCategoryOf`). O rótulo "roxo"
/// segue a cor dessa faixa na escala dos EUA; a escolha do limiar para o app é do projeto.
const alertPurpleMinAqi = 201;

const alertOrangeText =
    'Mudança de vento: previsão de chegada de nuvem de fumaça nas próximas 2 horas. '
    'Organize a umidificação do seu ambiente.';
const alertOrangeStatus =
    'O alerta laranja precisa de previsão de vento/trajetória da fumaça e de notificações '
    'push. Isso NÃO está implementado: o app não tem fonte de previsão nem serviço de push.';

const offlineNotice =
    'Orientações, triagem e telefones de emergência (SAMU $kSamuNumber e CIT) ficam '
    'embutidos no aplicativo e abrem sem internet. Mapas, focos do INPE, qualidade do ar e '
    'envio de respostas ao servidor precisam de internet.';

// ---------------------------------------------------------------- Referências extras
class ExtraReference {
  const ExtraReference(this.id, this.citation, this.used, this.status, {this.url});

  final int id;
  final String citation;
  final String used;

  /// O que foi (ou não) verificado nesta fonte.
  final String status;
  final String? url;
}

const extraReferences = <ExtraReference>[
  ExtraReference(
    4,
    'Centro de Informações Toxicológicas do Amazonas (CIT/AM), Hospital Universitário '
        'Getúlio Vargas (UFAM). Contatos: Abracit; Ministério da Saúde (lista de CIATox); '
        'A Crítica (30/08/2026).',
    'Telefones, horário e funcionamento do CIT.',
    'LIDAS 3 fontes em 20/10/2026: 0800 722 6001 e (92) 3305-4702 confirmados; 24 h '
        '(Abracit e A Crítica). (92) 3305-4700 NÃO confirmado.',
    url: 'https://abracit.org.br/centros/amazonas-manaus/',
  ),
  ExtraReference(
    5,
    'Associação Brasileira de Alergia e Imunologia (ASBAI), Comissão de Biodiversidade, '
        'Poluição e Clima. Queimadas na Amazônia durante a estação seca de 2023 '
        '(posicionamento).',
    'Ambiente interno, fontes de fumaça dentro de casa, plano de tratamento da asma, grupos de risco.',
    'LIDO em 20/10/2026 (sem data de publicação). Cita N95 (não PFF2). Não trata de soro '
        'nasal, hidratação, umidificador nem purificador.',
    url: 'https://asbai.org.br/wp-content/uploads/2024/04/POSICIONAMENTO-ASBAI-Quein-MUP-LR-EG-1.pdf',
  ),
  ExtraReference(
    6,
    'Conselho Regional de Medicina Veterinária do Amazonas (CRMV-AM), vice-presidente '
        'Márcio Nogueira, em: Fumaça das queimadas também ameaça a saúde de cães e gatos. '
        'A Crítica, 26/09/2026.',
    'Cuidados com cães e gatos durante a fumaça.',
    'LIDA em 20/10/2026, via imprensa. SUBSTITUI a indicação do CFMV: a busca não encontrou '
        'documento do CFMV sobre fumaça. Não trata de raças de focinho curto.',
    url: 'https://www.acritica.com/geral/fumaca-das-queimadas-tambem-ameaca-a-saude-de-c-es-e-gatos-1.416099',
  ),
  ExtraReference(
    7,
    'Organização Mundial da Saúde (OMS) / OPAS. Guías de salud para incendios de vegetación. '
        'Documento de orientación. 1999.',
    'Orientação geral sobre permanência em ambientes internos e grupos sensíveis.',
    'LIDO em 20/10/2026 (hospedado pela OPAS). Voltado a governos; não detalha máscaras, '
        'hidratação, umidificador, soro nasal nem animais.',
    url: 'https://www.paho.org/sites/default/files/2020-09/1999-oms-guias-incendios-vegetacion.pdf',
  ),
  ExtraReference(
    8,
    'Ministério da Saúde, Secretaria de Vigilância em Saúde e Ambiente. Queimadas e '
        'incêndios florestais: alerta de risco sanitário e recomendações para a população '
        '(2ª ed.). Programa VIGIAR.',
    'Máscaras N95/PFF2/P100, hidratação, permanência em ambiente fechado, grupos de risco e sintomas.',
    'LIDA em 20/10/2026 (gov.br). Não trata de soro fisiológico nem de animais.',
    url: 'https://www.gov.br/saude/pt-br/composicao/svsa/saude-ambiental/vigiar/publicacoes/queimadas-e-incendios-florestais-alerta-de-risco-sanitario-e-recomendacoes-para-a-populacao',
  ),
  ExtraReference(
    9,
    'Secretaria de Estado de Saúde do Amazonas (SES-AM) e Fundação de Vigilância em Saúde '
        'Dra. Rosemary Costa Pinto (FVS-RCP). Orientações de saúde para reduzir os impactos da '
        'fumaça (Comitê de Enfrentamento à Estiagem, 18/09/2024).',
    'Sintomas, hidratação, máscaras e redução da exposição.',
    'LIDA só pela matéria da imprensa (Rede Onda Digital, 19/09/2024), não o documento '
        'original. Não trata de mitos, leite, soro nem animais.',
    url: 'https://redeondadigital.com.br/amazonas/confira-orientacoes-de-saude-para-reduzir-impactos-da-fumaca',
  ),
  ExtraReference(
    10,
    'American Veterinary Medical Association (AVMA). Wildfire smoke and animals.',
    'Pets dentro de casa, sinais de alerta, evitar exercício.',
    'LIDA. Não menciona raças de focinho curto, água para pets (só rebanhos), limpeza dos '
        'olhos nem remédios humanos.',
    url: 'https://www.avma.org/resources/pet-owners/emergencycare/wildfire-smoke-and-animals',
  ),
  ExtraReference(
    11,
    'OMS Europa. Public health advice during the wildfires: how to protect your health and '
        'keep safe (perguntas e respostas, 16/06/2023).',
    'Respirador FFP2/N95 bem ajustado; permanecer em ambiente interno com janelas fechadas.',
    'LIDA em 20/10/2026. Não menciona hidratação, umidificador, purificador doméstico nem animais.',
    url: 'https://www.who.int/europe/news-room/questions-and-answers/item/public-health-advice-during-the-wildfires--how-to-protect-your-health-and-keep-safe',
  ),
  ExtraReference(
    12,
    '3M do Brasil, Divisão de Segurança Pessoal. Reuso de respiradores descartáveis. '
        'Boletim técnico, maio/2020, rev. 2.',
    'Respirador úmido ou sujo deve ser descartado; sem limpeza ou desinfecção.',
    'LIDO em 20/10/2026. Fonte do fabricante, não de órgão regulador.',
    url: 'https://multimedia.3m.com/mws/media/1825756O/reuso-respiradores-descartaveis.pdf',
  ),
  ExtraReference(
    13,
    'Anvisa recomenda que menores de um ano não consumam mel (Portal Médico do CFM, 20/08/2008).',
    'Mel só para maiores de 1 ano (risco de botulismo).',
    'LIDA em 20/10/2026 (notícia de 2008 que cita a Anvisa).',
    url: 'https://portal.cfm.org.br/noticias/menores-de-um-ano-devem-evitar-o-consumo-de-mel/',
  ),
  ExtraReference(
    14,
    'Direção-Geral da Saúde (DGS, Portugal), nota sobre intoxicação por fumo, em: DGS diz o '
        'que fazer se estiver exposto ao fumo (O Minho/Lusa, 29/07/2025).',
    'Leite não é antídoto; não usar fontes de combustão em casa; manter a medicação habitual.',
    'LIDA só pela notícia, não no original. Fonte portuguesa, não brasileira.',
    url: 'https://ominho.pt/dgs-diz-o-que-fazer-em-caso-de-exposicao-ao-fumo-e-alerta-ingerir-leite-em-caso-de-intoxicacao-e-um-mito/',
  ),
  ExtraReference(
    15,
    'Manual MSD (versão para profissionais). Intoxicação por monóxido de carbono.',
    'Mecanismo do CO (hemoglobina, oxigênio nos tecidos) e sintomas.',
    'LIDO em 20/10/2026. Trata a fumaça de incêndio como fonte de CO.',
    url: 'https://www.msdmanuals.com/pt/profissional/lesões-intoxicação/intoxicação/intoxicação-por-monóxido-de-carbono',
  ),
  ExtraReference(
    16,
    'CNN Brasil. Queimadas: veja os riscos da fumaça à saúde e como se proteger '
        '(26/08/2024, atualizada em 12/09/2024). Especialistas: pneumologista, oftalmologista e infectologista.',
    'Soro fisiológico no nariz e nos olhos; toalhas molhadas e baldes de água.',
    'LIDA em 20/10/2026. Opinião de especialistas em reportagem, não documento oficial.',
    url: 'https://www.cnnbrasil.com.br/saude/queimadas-veja-os-riscos-da-fumaca-a-saude-e-como-se-proteger/',
  ),
  ExtraReference(
    17,
    'Correio Braziliense. Todo cuidado na hora de respirar fumaça de queimada, alertam '
        'médicos (26/08/2024). Cita a SES-DF e pneumologistas e otorrinolaringologista.',
    'Lavagem nasal com soro fisiológico; umidificador limpo; toalhas úmidas e baldes.',
    'LIDA em 20/10/2026. Reportagem, não documento oficial.',
    url: 'https://www.correiobraziliense.com.br/cidades-df/2024/08/6927530-todo-cuidado-na-hora-de-respirar-fumaca-de-queimada-alertam-medicos.html',
  ),
  ExtraReference(
    18,
    'Metrópoles. Fumaça de queimadas pode alcançar alvéolos e entrar na corrente sanguínea '
        '(07/10/2026). Pneumologista e alergista.',
    'Partículas finas chegam aos alvéolos.',
    'LIDA em 20/10/2026. Reportagem, não documento oficial.',
    url: 'https://www.metropoles.com/saude/fumaca-de-queimadas-pode-alcancar-alveolos-e-entrar-na-corrente-sanguinea',
  ),
  ExtraReference(
    19,
    'Patas da Casa. Veterinária responde: qual o efeito das fumaças de queimadas na saúde dos '
        'pets? (26/08/2024). Renata Bloomfield, CRMV-RJ 12084.',
    'Fechar frestas com pano molhado e umidificador como ajuda complementar para pets.',
    'LIDA em 20/10/2026. Reportagem, não documento oficial.',
    url: 'https://www.patasdacasa.com.br/noticia/veterinaria-responde-qual-o-efeito-das-fumacas-de-queimadas-na-saude-dos-pets',
  ),
  ExtraReference(
    20,
    'U.S. EPA. Basics of Wildfire Smoke Exposure (ficha EPA-452/F-26-012, sem data no texto).',
    'PM2,5 como a maior ameaça da fumaça à saúde.',
    'LIDA em 20/10/2026. Não cita monóxido de carbono, hidratação nem umidificador.',
    url: 'https://www.epa.gov/system/files/documents/2026-06/wildfire-smoke-and-health-factsheet.pdf',
  ),
];

/// Nome curto de cada referência (números de `references.dart` e de [extraReferences]).
const referenceShort = <int, String>{
  1: 'CDC, alerta HAN 00495 (2023)',
  2: 'EPA, guia de fumaça de incêndios',
  3: 'Ministério da Saúde, nota sobre fumaça (2024)',
  4: 'CIT/AM (HUGV-UFAM)',
  5: 'ASBAI, queimadas na Amazônia',
  6: 'CRMV-AM, cães e gatos na fumaça',
  7: 'OMS/OPAS, guia de incêndios de vegetação',
  8: 'Ministério da Saúde, VIGIAR',
  9: 'SES-AM / FVS-RCP, orientações sobre a fumaça',
  10: 'AVMA, Wildfire smoke and animals',
  11: 'OMS Europa, conselhos durante incêndios',
  12: '3M, reuso de respiradores',
  13: 'Anvisa, mel e menores de 1 ano',
  14: 'DGS (Portugal), fumo e leite',
  15: 'Manual MSD, monóxido de carbono',
  16: 'CNN Brasil, riscos da fumaça',
  17: 'Correio Braziliense, cuidados na fumaça',
  18: 'Metrópoles, PM2,5 nos alvéolos',
  19: 'Patas da Casa, pets e fumaça',
  20: 'EPA, Basics of Wildfire Smoke Exposure',
};
