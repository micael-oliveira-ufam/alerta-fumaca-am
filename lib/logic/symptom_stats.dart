import 'risk_assessment.dart';
import '../models/answer_record.dart';

/// De onde vêm os números mostrados.
enum StatsSource { server, local }

/// Estatística de um sintoma. Definições idênticas às do servidor (`server/app/stats.py`):
/// - `reports`: respostas em que a gravidade foi >= 1;
/// - `percent`: reports / total de respostas do período * 100 (1 casa decimal);
/// - `meanSeverity`: média da gravidade entre quem relatou (1 a 3; 2 casas), ou `null`.
class SymptomStat {
  const SymptomStat({
    required this.id,
    required this.reports,
    required this.percent,
    required this.mild,
    required this.moderate,
    required this.intense,
    required this.meanSeverity,
  });

  final String id;
  final int reports;
  final double percent;
  final int mild;
  final int moderate;
  final int intense;
  final double? meanSeverity;

  factory SymptomStat.fromServerJson(Map<String, dynamic> j) => SymptomStat(
        id: j['sintoma'] as String,
        reports: (j['relatos'] as num).toInt(),
        percent: (j['percentual'] as num).toDouble(),
        mild: (j['leve'] as num).toInt(),
        moderate: (j['moderado'] as num).toInt(),
        intense: (j['intenso'] as num).toInt(),
        meanSeverity: (j['gravidade_media'] as num?)?.toDouble(),
      );
}

class StatsSnapshot {
  const StatsSnapshot({
    required this.source,
    required this.periodDays,
    required this.totalResponses,
    required this.sufficient,
    required this.minimumToDisclose,
    required this.levels,
    required this.symptoms,
  });

  final StatsSource source;
  final int periodDays;
  final int totalResponses;

  /// `false` quando há poucas respostas para divulgar detalhes (privacidade).
  final bool sufficient;
  final int minimumToDisclose;

  /// Respostas por nível de risco (chaves = `RiskLevel.name`).
  final Map<String, int> levels;

  /// Do mais para o menos relatado.
  final List<SymptomStat> symptoms;

  factory StatsSnapshot.fromServerJson(Map<String, dynamic> j) {
    final levels = <String, int>{
      for (final level in RiskLevel.values) level.name: 0,
    };
    for (final e in (j['niveis'] as Map<String, dynamic>).entries) {
      levels[e.key] = (e.value as num).toInt();
    }
    return StatsSnapshot(
      source: StatsSource.server,
      periodDays: (j['periodo_dias'] as num).toInt(),
      totalResponses: (j['total_respostas'] as num).toInt(),
      sufficient: j['suficiente'] as bool,
      minimumToDisclose: (j['minimo_para_divulgar'] as num).toInt(),
      levels: levels,
      symptoms: [
        for (final s in j['sintomas'] as List<dynamic>)
          SymptomStat.fromServerJson(s as Map<String, dynamic>),
      ],
    );
  }
}

double _round(double value, int decimals) {
  var factor = 1.0;
  for (var i = 0; i < decimals; i++) {
    factor *= 10;
  }
  return (value * factor).round() / factor;
}

/// Estatísticas calculadas só com as respostas deste aparelho.
///
/// Não há mínimo para divulgar: os dados são da própria pessoa e não saem do aparelho.
StatsSnapshot computeLocalStats(
  List<AnswerRecord> records, {
  int days = 30,
  DateTime? now,
}) {
  final since = (now ?? DateTime.now()).toUtc().subtract(Duration(days: days));
  final inPeriod = records.where((r) => !r.timestamp.isBefore(since)).toList();
  final total = inPeriod.length;

  final levels = <String, int>{for (final level in RiskLevel.values) level.name: 0};
  for (final r in inPeriod) {
    levels[r.level.name] = (levels[r.level.name] ?? 0) + 1;
  }

  final ids = <String>{for (final r in inPeriod) ...r.severities.keys};
  final stats = <SymptomStat>[];
  for (final id in ids) {
    var mild = 0, moderate = 0, intense = 0, sum = 0;
    for (final r in inPeriod) {
      final severity = r.severities[id] ?? 0;
      if (severity == 1) mild++;
      if (severity == 2) moderate++;
      if (severity == 3) intense++;
      if (severity >= 1) sum += severity;
    }
    final reports = mild + moderate + intense;
    stats.add(SymptomStat(
      id: id,
      reports: reports,
      percent: total == 0 ? 0 : _round(100 * reports / total, 1),
      mild: mild,
      moderate: moderate,
      intense: intense,
      meanSeverity: reports == 0 ? null : _round(sum / reports, 2),
    ));
  }
  stats.sort((a, b) {
    final byReports = b.reports.compareTo(a.reports);
    return byReports != 0 ? byReports : a.id.compareTo(b.id);
  });

  return StatsSnapshot(
    source: StatsSource.local,
    periodDays: days,
    totalResponses: total,
    sufficient: total > 0,
    minimumToDisclose: 1,
    levels: levels,
    symptoms: stats,
  );
}
