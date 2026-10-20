import '../logic/risk_assessment.dart';

/// Textos de orientação. Conteúdo educativo geral; não substitui
/// orientação médica. As ações por nível de risco são critério do projeto (não de escala
/// clínica validada): revisar com profissionais de saúde antes de publicar.
const kDisclaimer =
    'Este aplicativo oferece orientação geral e triagem educativa. '
    'Não substitui avaliação médica. Em caso de piora, procure atendimento.';

const kSamuNumber = '192';
const kBombeirosNumber = '193';

/// Centro de Informações Toxicológicas do Amazonas (Manaus).
///
/// CONFIRMADO em 20/10/2026: o 0800 722 6001 consta no Abracit, na lista de CIATox do
/// Ministério da Saúde e em A Crítica (30/08/2026), com atendimento 24 h e gratuito.
/// Reconfirme periodicamente: um número errado em caso de intoxicação pode causar dano.
const kCitName = 'Centro de Informações Toxicológicas do Amazonas';
const kCitPhoneDisplay = '0800 722 6001';
const kCitPhoneDial = '08007226001';

const severityLabels = ['Nenhum', 'Leve', 'Moderado', 'Intenso'];

String levelLabel(RiskLevel l) => switch (l) {
      RiskLevel.low => 'Risco baixo',
      RiskLevel.moderate => 'Risco moderado',
      RiskLevel.high => 'Risco alto',
      RiskLevel.emergency => 'Procure atendimento agora',
    };

String consequenceLabel(Consequence c) => switch (c) {
      Consequence.respiratory => 'Vias respiratórias',
      Consequence.ocular => 'Olhos',
      Consequence.cardiovascular => 'Coração e circulação',
      Consequence.neurological => 'Cabeça e sistema nervoso',
      Consequence.general => 'Sinais gerais (cansaço)',
    };

const levelActions = <RiskLevel, List<String>>{
  RiskLevel.low: [
    'Acompanhe a qualidade do ar pelos canais oficiais de saúde e meio ambiente.',
    'Nas horas de maior fumaça, prefira ambientes internos com portas e janelas fechadas.',
    'Mantenha a hidratação com água em intervalos regulares.',
  ],
  RiskLevel.moderate: [
    'Evite atividade física intensa e ao ar livre.',
    'Se precisar sair, use máscara PFF2/N95 bem ajustada ao rosto. Máscaras de tecido não filtram adequadamente partículas finas.',
    'Feche portas e janelas. Se tiver purificador de ar, use-o no ambiente onde você fica.',
    'Se tiver asma ou DPOC, mantenha a medicação de controle e tenha o broncodilatador prescrito por perto.',
    'Não queime lixo nem use velas ou incensos em ambientes fechados.',
    'Observe os sintomas. Se piorarem, procure uma Unidade Básica de Saúde (UBS).',
  ],
  RiskLevel.high: [
    'Permaneça em ambiente interno, com a casa o mais vedada possível.',
    'Não faça esforço físico ao ar livre.',
    'Procure uma unidade de saúde nas próximas horas, mesmo sem sintomas graves.',
    'Gestantes, idosos e crianças devem evitar qualquer exposição e buscar orientação médica.',
    'Mantenha a medicação de uso contínuo sem interrupção, salvo orientação do médico.',
  ],
  RiskLevel.emergency: [
    'Ligue $kSamuNumber (SAMU) ou vá agora ao pronto-socorro mais próximo.',
    'Se houver falta de ar ou tontura intensa, não dirija. Peça ajuda a alguém.',
    'Leve a lista dos medicamentos em uso e a informação de quando os sintomas começaram.',
    'Se houver risco imediato, ligue $kBombeirosNumber (Bombeiros) ou 192.',
  ],
};
