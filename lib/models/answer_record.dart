import '../logic/risk_assessment.dart';

/// Resposta completa do questionário guardada neste aparelho.
///
/// Não contém localização nem identificador: serve apenas para as estatísticas
/// locais dos sintomas e para reenvio ao servidor, se o usuário consentiu.
class AnswerRecord {
  const AnswerRecord({
    required this.timestamp,
    required this.severities,
    required this.level,
    required this.points,
  });

  /// Sempre em UTC.
  final DateTime timestamp;

  /// Gravidade (0 a 3) por identificador de sintoma (ver `symptomItems`).
  final Map<String, int> severities;
  final RiskLevel level;
  final int points;

  factory AnswerRecord.fromJson(Map<String, dynamic> j) => AnswerRecord(
        timestamp: DateTime.parse(j['t'] as String).toUtc(),
        severities: {
          for (final e in (j['s'] as Map<String, dynamic>).entries) e.key: e.value as int,
        },
        level: RiskLevel.values.byName(j['level'] as String),
        points: j['points'] as int,
      );

  Map<String, dynamic> toJson() => {
        't': timestamp.toUtc().toIso8601String(),
        's': severities,
        'level': level.name,
        'points': points,
      };
}
