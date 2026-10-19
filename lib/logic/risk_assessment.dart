/// Motor de triagem de risco por fumaça.
///
/// ATENÇÃO: os pesos e limiares abaixo são PROVISÓRIOS. Eles são um modelo de
/// triagem educativa, não um instrumento clínico validado. Antes de uso real,
/// devem ser revisados por profissionais de saúde e calibrados com dados
/// locais (ex.: ILMD/Fiocruz Amazônia). Todos os valores estão centralizados
/// aqui para que a revisão seja auditável e os testes em `test/` reflitam
/// exatamente o que foi decidido.
library;

enum Consequence { respiratory, ocular, cardiovascular, neurological, general }

enum RiskLevel { low, moderate, high, emergency }

enum Exposure { under1h, between1and4h, over4h }

class SymptomItem {
  const SymptomItem(this.id, this.label, this.consequence, {this.redFlag = false});

  final String id;
  final String label;
  final Consequence consequence;

  /// Sinal que, em intensidade máxima, exige atendimento imediato.
  final bool redFlag;
}

const symptomItems = <SymptomItem>[
  SymptomItem('cough', 'Tosse', Consequence.respiratory),
  SymptomItem('throat', 'Irritação ou dor na garganta', Consequence.respiratory),
  SymptomItem('nose', 'Coriza ou nariz irritado', Consequence.respiratory),
  SymptomItem('wheeze', 'Chiado no peito', Consequence.respiratory),
  SymptomItem('dyspnea', 'Falta de ar', Consequence.respiratory, redFlag: true),
  SymptomItem('eyes', 'Olhos ardendo, vermelhos ou lacrimejando', Consequence.ocular),
  SymptomItem('chest', 'Aperto ou dor no peito', Consequence.cardiovascular, redFlag: true),
  SymptomItem('palpitation', 'Palpitações ou batimentos irregulares', Consequence.cardiovascular),
  SymptomItem('headache', 'Dor de cabeça', Consequence.neurological),
  SymptomItem('dizzy', 'Tontura ou confusão', Consequence.neurological, redFlag: true),
  SymptomItem('fatigue', 'Cansaço fora do normal', Consequence.general),
];

/// Pontos adicionais por tempo de exposição ao ar livre no dia.
const exposurePoints = <Exposure, int>{
  Exposure.under1h: 0,
  Exposure.between1and4h: 2,
  Exposure.over4h: 4,
};

/// Pontos somados quando o perfil inclui algum grupo vulnerável.
const vulnerablePoints = 3;

/// Limiares sobre o total de pontos (provisórios).
const moderateThreshold = 8;
const highThreshold = 15;

class Profile {
  const Profile({
    this.elderly = false,
    this.pregnant = false,
    this.child = false,
    this.chronicRespiratory = false,
    this.chronicCardiac = false,
  });

  final bool elderly;
  final bool pregnant;
  final bool child;
  final bool chronicRespiratory;
  final bool chronicCardiac;

  bool get vulnerable =>
      elderly || pregnant || child || chronicRespiratory || chronicCardiac;
}

class RiskResult {
  const RiskResult({
    required this.level,
    required this.points,
    required this.consequences,
  });

  final RiskLevel level;
  final int points;

  /// Categorias com soma de severidade >= 2 (efeitos predominantes).
  final Set<Consequence> consequences;
}

/// Avalia o risco a partir das severidades (0 = nenhum, 1 = leve,
/// 2 = moderado, 3 = intenso) de cada item de [symptomItems].
///
/// Regras:
/// 1. Qualquer sinal de alerta (redFlag) em intensidade 3 => EMERGÊNCIA.
/// 2. Falta de ar moderada (>= 2) em quem tem doença respiratória ou
///    cardíaca crônica => EMERGÊNCIA.
/// 3. Caso contrário, pontos = soma das severidades + exposição
///    + (vulnerável ? [vulnerablePoints] : 0), classificados pelos limiares.
RiskResult assess({
  required Map<String, int> severities,
  required Exposure exposure,
  required Profile profile,
}) {
  for (final item in symptomItems) {
    final s = severities[item.id] ?? 0;
    if (s < 0 || s > 3) {
      throw ArgumentError.value(s, item.id, 'Severidade deve estar entre 0 e 3');
    }
  }

  var symptomSum = 0;
  var redFlagSevere = false;
  final totals = {for (final c in Consequence.values) c: 0};

  for (final item in symptomItems) {
    final s = severities[item.id] ?? 0;
    symptomSum += s;
    totals[item.consequence] = totals[item.consequence]! + s;
    if (item.redFlag && s == 3) redFlagSevere = true;
  }

  final dyspneaInChronicDisease = (severities['dyspnea'] ?? 0) >= 2 &&
      (profile.chronicRespiratory || profile.chronicCardiac);

  final emergency = redFlagSevere || dyspneaInChronicDisease;

  final points = symptomSum +
      exposurePoints[exposure]! +
      (profile.vulnerable ? vulnerablePoints : 0);

  final level = emergency
      ? RiskLevel.emergency
      : points >= highThreshold
          ? RiskLevel.high
          : points >= moderateThreshold
              ? RiskLevel.moderate
              : RiskLevel.low;

  final consequences = {
    for (final entry in totals.entries)
      if (entry.value >= 2) entry.key,
  };

  return RiskResult(level: level, points: points, consequences: consequences);
}
