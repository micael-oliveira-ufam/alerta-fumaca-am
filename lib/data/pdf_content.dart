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
const protectionCards = <InfoCardData>[
  InfoCardData(
    title: 'Qual máscara realmente protege contra a fumaça?',
    paragraphs: [
      'Máscaras de pano ou máscaras cirúrgicas comuns não protegem seus pulmões contra os '
          'elementos mais perigosos da fumaça. Elas deixam passar as micropartículas que '
          'causam danos à saúde.',
      'Para se proteger de verdade, utilize respiradores do tipo PFF2 ou N95. Eles têm '
          'vedação correta no rosto e um filtro capaz de reter impurezas microscópicas.',
    ],
    tip: 'Onde encontrar: farmácias comerciais, lojas de Equipamentos de Proteção '
        'Individual (EPI) e, em períodos de crise extrema, postos de distribuição '
        'indicados pela Secretaria de Saúde do município.',
    verification: Verification.partial,
    verificationNote: 'CDC e EPA (lidas) recomendam N95 ou P100 bem ajustado e a EPA diz que '
        'máscaras cirúrgicas e de papel não são recomendadas. A equivalência PFF2 = N95 e '
        'os locais de distribuição são do texto da equipe, não conferidos.',
    refs: [1, 2, 5],
  ),
  InfoCardData(
    title: 'Purificador vs. Umidificador: qual a diferença?',
    paragraphs: [],
    bulletsTitle: 'Entenda cada aparelho',
    bullets: [
      'Purificador de ar (com filtro HEPA): é o equipamento ideal. Ele limpa o ambiente, '
          'pois "captura" as micropartículas flutuantes dentro do cômodo.',
      'Umidificador de ar: não limpa o ar, mas aumenta a umidade do ambiente. Isso ajuda '
          'a manter as vias aéreas úmidas, auxiliando o próprio corpo (através do muco) a '
          'expelir a sujeira.',
    ],
    tip: 'Dica caseira: sem esses aparelhos, mantenha janelas e portas fechadas nos '
        'horários de maior fumaça. Para melhorar a umidade interna, espalhe toalhas '
        'molhadas e baldes com água pelos cômodos.',
    verification: Verification.partial,
    verificationNote: 'Purificador/filtro e ambiente fechado constam no CDC e na EPA '
        '(lidos). O papel do umidificador e a dica das toalhas molhadas e baldes são do '
        'texto da equipe: nenhuma fonte lida os confirma.',
    refs: [1, 2],
  ),
];

// ---------------------------------------------------------------- Tela 2
const symptomExplainers = <InfoCardData>[
  InfoCardData(
    title: 'Por que sinto dor de cabeça, tontura e cansaço?',
    paragraphs: [
      'A fumaça carrega monóxido de carbono (CO). Quando você o inala, esse gás "engana" '
          'o organismo e ocupa o lugar do oxigênio no seu sangue. Com menos oxigênio '
          'circulando, o cérebro e os músculos reagem causando dor, tontura e fadiga.',
    ],
    verification: Verification.partial,
    verificationNote: 'Dor de cabeça e fadiga constam entre os sintomas no CDC (lido). A '
        'explicação do mecanismo do CO é o texto da equipe; não consultei fonte para ela.',
    refs: [1, 4],
  ),
  InfoCardData(
    title: 'Por que sinto os olhos queimando, tosse seca e garganta arranhando?',
    paragraphs: [
      'A queima da mata libera gases irritantes (como acroleína e formaldeído). Em contato '
          'com a umidade natural dos olhos, nariz e boca, eles provocam inflamação imediata, '
          'lacrimejamento e tosse de defesa.',
    ],
    verification: Verification.partial,
    verificationNote: 'Irritação nos olhos e tosse constam no CDC (lido). A citação de '
        'acroleína e formaldeído é do texto da equipe, não conferida. A comparação com '
        '"ácido fraco" do original foi retirada por não ter fonte.',
    refs: [1, 4],
  ),
  InfoCardData(
    title: 'O perigo invisível: o que é o PM2,5?',
    paragraphs: [
      'É o material particulado fino: partículas de fuligem tão pequenas que passam pelas '
          'defesas do nariz e chegam fundo no pulmão. Isso aumenta o estresse do corpo, '
          'especialmente para quem já tem asma, bronquite ou problemas no coração.',
    ],
    verification: Verification.partial,
    verificationNote: 'Os grupos de risco (asma, DPOC, doença cardiovascular) constam no CDC '
        'e na EPA (lidos). Ajuste feito: o original diz que as partículas caem "diretamente '
        'na corrente sanguínea" e falam de risco "toxicológico a longo prazo"; não conferi '
        'essas frases e por isso não as repeti.',
    refs: [1, 2, 7],
  ),
];

// ---------------------------------------------------------------- Tela 3
const homeCareCards = <InfoCardData>[
  InfoCardData(
    title: 'Hidratação das mucosas e vias aéreas',
    paragraphs: [
      'A água é sua primeira barreira de defesa. Beba líquidos constantemente.',
    ],
    bulletsTitle: 'Cuidados com nariz e olhos',
    bullets: [
      'Use soro fisiológico 0,9% para pingar nos olhos e fazer a lavagem nasal várias '
          'vezes ao dia. Isso remove fisicamente partículas presas nas mucosas.',
      'Inalação/nebulização: faça apenas com soro fisiológico, para ajudar a soltar o '
          'catarro e aliviar as vias respiratórias.',
    ],
    verification: Verification.teamText,
    verificationNote: 'Nenhuma fonte lida confirma lavagem nasal, colírio de soro ou '
        'nebulização com soro como medida contra fumaça. Em caso de olho muito irritado '
        'ou dor, procure atendimento.',
    refs: [4, 7, 8],
  ),
  InfoCardData(
    title: 'Alerta vermelho de farmácia',
    paragraphs: [
      'Nunca use remédios de bombinha, broncodilatadores ou corticoides no inalador por '
          'conta própria. O uso incorreto desses remédios pode sobrecarregar o coração. '
          'Use apenas com receita médica.',
    ],
    warning: 'Quem já tem prescrição (asma, DPOC) deve seguir a orientação do próprio médico.',
    verification: Verification.teamText,
    verificationNote: 'Texto da equipe. A prudência de não se automedicar é consenso geral, '
        'mas a frase sobre sobrecarga do coração não foi conferida em fonte.',
    refs: [4, 7, 8],
  ),
  InfoCardData(
    title: 'Alívio natural',
    paragraphs: [
      'Chás mornos (como camomila) e mel de abelha ajudam a criar uma película protetora '
          'que acalma a dor e a coceira na garganta.',
    ],
    warning: 'Mel somente para maiores de 1 ano. Nunca dê mel a bebês.',
    verification: Verification.teamText,
    verificationNote: 'Texto da equipe; não consultei fonte. A restrição do mel para '
        'menores de 1 ano é uma regra amplamente difundida, mas também não foi conferida '
        'aqui. Chá e mel aliviam o desconforto, não tratam intoxicação.',
    refs: [4, 7, 8],
  ),
];

// ---------------------------------------------------------------- Tela 4 (CIT)
const kCitHugvPhoneAlt = '(92) 3305-4700';
const kCitHugvPhoneAltDial = '9233054700';

const citIntro =
    'O CIT funciona dentro do Hospital Universitário Getúlio Vargas (HUGV) da Universidade '
    'Federal do Amazonas e orienta sobre envenenamentos e intoxicações, inclusive por fumaça '
    'ou poluentes. Você pode ligar para tirar dúvidas.';

const citWhenToCall = <String>[
  'Se você ou alguém próximo inalou muita fumaça e apresenta confusão mental, desmaio ou '
      'tontura extrema. Nesses casos, ligue primeiro para o SAMU (192).',
  'Crianças ou idosos com falta de ar contínua que não melhora após sair do ambiente '
      'enfumaçado.',
  'Casos de irritação extrema ou reações alérgicas graves causadas pela fuligem.',
];

/// Uso interno (não exibido no app): o que foi conferido e ajustado no texto do CIT.
const citVerificationNote =
    'O 0800 722 6001 foi informado pela equipe. O telefone (92) 3305-4700 consta na carta '
    'de serviços do HUGV, mas confirme os dois com o CIT antes de divulgar o app. '
    'Ajuste feito: o original não cita o SAMU em confusão/desmaio; acrescentei "ligue '
    'primeiro para o 192" por segurança. A expressão "autoridade máxima" do original foi '
    'retirada por não ter fonte.';

// ---------------------------------------------------------------- Pets
const petCards = <InfoCardData>[
  InfoCardData(
    title: 'Como a fumaça afeta cães e gatos?',
    paragraphs: [
      'Assim como nós, os animais inalam o material particulado (PM2,5) e os gases tóxicos '
          'da fumaça. Cães de focinho curto (braquicefálicos, como Pugs, Bulldogs e Shih '
          'Tzus) e gatos podem sofrer mais rápido, pois já têm dificuldade natural de respirar.',
    ],
    bulletsTitle: 'Sinais de alerta',
    bullets: [
      'Tosse seca (como se estivesse engasgado) ou espirros frequentes.',
      'Respiração muito rápida, ofegante ou cansaço extremo ao menor esforço.',
      'Olhos vermelhos, lacrimejando ou com muita secreção.',
      'Gato respirando com a boca aberta: emergência veterinária.',
    ],
    verification: Verification.partial,
    verificationNote: 'A AVMA (lida) apoia manter o animal dentro de casa e consultar o veterinário diante de '
        'tosse, respiração difícil, secreção nasal, cansaço e irritação nos olhos. A parte sobre '
        'raças de focinho curto e o gato de boca aberta é do texto da equipe, não encontrada '
        'nessa página.',
    refs: [6, 10],
  ),
  InfoCardData(
    title: 'Como proteger o seu pet em casa?',
    paragraphs: [],
    bullets: [
      'Água sempre fresca: troque a água das vasilhas várias vezes ao dia. A fuligem que cai '
          'no pote contamina a água e o animal pode beber menos.',
      'Reduza os passeios nos dias de pico de fumaça: o esforço faz o animal puxar mais ar '
          'poluído.',
      'Mantenha o pet dentro de casa, no cômodo mais fechado e protegido.',
      'Umidificação: use umidificador ou coloque toalhas molhadas e bacias de água perto de '
          'onde ele dorme.',
    ],
    verification: Verification.partial,
    verificationNote: 'Ficar dentro de casa e reduzir exercício e passeios seguem a AVMA (lida). Água '
        'trocada várias vezes e umidificação são do texto da equipe; a AVMA lida não os cita '
        '(só recomenda água fresca para rebanhos).',
    refs: [6, 10],
  ),
  InfoCardData(
    title: 'Limpeza e manejo seguro',
    paragraphs: [],
    bullets: [
      'Olhos e nariz: se estiverem vermelhos ou irritados pela fuligem, limpe com delicadeza '
          'usando gaze limpa embebida em soro fisiológico 0,9%. Nunca use colírios humanos '
          'sem orientação profissional.',
      'Pano úmido: a fuligem fica presa nos pelos. Passar um pano úmido no corpo ao fim do '
          'dia ajuda a remover e evita que o animal lamba a sujeira.',
    ],
    warning: 'Jamais medique o animal por conta própria com xaropes, antialérgicos ou '
        'bombinhas de uso humano. A dose errada pode ser fatal. Se os sintomas persistirem, '
        'procure um médico-veterinário.',
    verification: Verification.teamText,
    verificationNote: 'Texto da equipe; a AVMA lida não trata de limpeza dos olhos nem de '
        'medicação humana. A recomendação de não medicar sem veterinário é prudência geral.',
    refs: [6, 10],
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
    'Mito. O leite não neutraliza as toxinas respiratórias nem o monóxido de carbono no '
        'sangue. Beba água; ela é o líquido essencial.',
    Verification.teamText,
    'Texto da equipe; não encontrei fonte que trate do leite. O trecho sobre soro '
        'fisiológico "hidratar as vias aéreas" do original foi retirado, por não ter fonte.',
    refs: [9],
  ),
  MythData(
    'Dá para lavar a máscara PFF2/N95 e reutilizar?',
    false,
    'Mito. Molhar ou passar álcool pode destruir a capacidade de filtragem eletrostática, '
        'deixando-a como um pano comum. Se estiver suja de fuligem ou úmida, descarte.',
    Verification.teamText,
    'Texto da equipe; não consultei a nota da ASBAI nem fabricante. Confira a orientação '
        'do fabricante e da Anvisa.',
    refs: [5, 9],
  ),
  MythData(
    'Queimar casca de laranja ou borra de café em casa tira o cheiro de fumaça?',
    false,
    'Mito. Qualquer queima dentro de casa cria mais fumaça e piora a qualidade do ar do '
        'ambiente fechado. Para o cheiro, purifique o ar ou ventile quando a fumaça externa '
        'permitir; nunca queime mais coisas.',
    Verification.partial,
    'O CDC (lido) orienta evitar fontes internas de fumaça. A afirmação específica sobre '
        'casca de laranja e borra de café é do texto da equipe. Ajuste: o original cita só '
        'aumento de monóxido de carbono, que mantive fora por não ter fonte.',
    refs: [1, 9],
  ),
];

const mythsReferenceNote =
    'Referência: Secretaria de Estado de Saúde do Amazonas (SES-AM) e Fundação de Vigilância em '
    'Saúde (FVS-AM), boletins e notas de esclarecimento sobre mitos durante a estiagem e a fumaça.';

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
    'Universidade Federal do Amazonas (UFAM) / Hospital Universitário Getúlio Vargas '
        '(HUGV). Centro de Informação Toxicológica (CIT).',
    'Apresentação e contato do CIT.',
    'A carta de serviços do HUGV traz o telefone (92) 3305-4700. O 0800 722 6001 e os '
        '"protocolos de manejo" citados pela equipe NÃO foram confirmados.',
  ),
  ExtraReference(
    5,
    'Associação Brasileira de Alergia e Imunologia (ASBAI). Notas técnicas sobre máscaras '
        'faciais (N95/PFF2) durante crises de poluição.',
    'Máscaras faciais (N95/PFF2) durante a fumaça.',
    'NÃO consultada. As afirmações sobre máscaras no app se apoiam no CDC e na EPA.',
  ),
  ExtraReference(
    6,
    'Conselho Federal de Medicina Veterinária (CFMV). Notas técnicas sobre poluição e '
        'fumaça de queimadas em animais de companhia.',
    'Cuidados com animais de companhia durante a fumaça.',
    'NÃO consultada.',
  ),
  ExtraReference(
    7,
    'Organização Pan-Americana da Saúde (OPAS) / OMS. Orientações sobre efeitos das '
        'queimadas na saúde e manejo de PM2,5.',
    'Queimadas, PM2,5 e saúde.',
    'NÃO consultada.',
  ),
  ExtraReference(
    8,
    'Ministério da Saúde. Programa VIGIAR: vigilância em saúde de populações expostas a '
        'poluentes atmosféricos.',
    'Vigilância em saúde e poluição do ar.',
    'NÃO consultada. Veja também a nota do Ministério da Saúde na fonte [3] (lida apenas '
        'pela divulgação na imprensa).',
  ),
  ExtraReference(
    9,
    'Secretaria de Estado de Saúde do Amazonas (SES-AM) / Fundação de Vigilância em Saúde '
        '(FVS-AM). Boletins sobre mitos e condutas na estiagem e fumaça.',
    'Seção "Fato ou Fake?".',
    'NÃO consultada.',
  ),
  ExtraReference(
    10,
    'American Veterinary Medical Association (AVMA). Pet safety during wildfires / smoke.',
    'Seção "E os nossos Pets?".',
    'Página "Wildfire smoke and animals" lida: manter pets dentro de casa com janelas '
        'fechadas, sair só para necessidades rápidas, evitar exercício intenso, e lista sinais '
        '(tosse, respiração difícil, secreção nasal, cansaço, irritação e lacrimejamento dos '
        'olhos). Não menciona raças de focinho curto, água para pets (só para rebanhos), '
        'limpeza dos olhos nem remédios humanos.',
    url: 'https://www.avma.org/resources/pet-owners/emergencycare/wildfire-smoke-and-animals',
  ),
];

/// Nome curto de cada referência (números de `references.dart` e de [extraReferences]).
const referenceShort = <int, String>{
  1: 'CDC, alerta HAN 00495 (2023)',
  2: 'EPA, guia de fumaça de incêndios (EPA-452/R-21-901)',
  3: 'Ministério da Saúde, nota sobre fumaça (2024)',
  4: 'UFAM/HUGV, Centro de Informação Toxicológica',
  5: 'ASBAI, notas técnicas sobre máscaras',
  6: 'CFMV, fumaça e animais de companhia',
  7: 'OPAS/OMS, queimadas e saúde',
  8: 'Ministério da Saúde, programa VIGIAR',
  9: 'SES-AM / FVS-AM, boletins sobre mitos',
  10: 'AVMA, Wildfire smoke and animals',
};
