import '../logic/risk_assessment.dart';

/// Registro anonimizado de um ponto de risco.
///
/// Privacidade (LGPD): a coordenada é arredondada para 2 casas decimais
/// (~1,1 km), e o registro não contém identificador de usuário ou aparelho.
class SmokeReport {
  const SmokeReport({
    required this.timestamp,
    required this.lat,
    required this.lon,
    required this.level,
    required this.points,
  });

  final DateTime timestamp; // sempre em UTC
  final double lat;
  final double lon;
  final RiskLevel level;
  final int points;

  static double coarsen(double value) => (value * 100).round() / 100;

  factory SmokeReport.fromJson(Map<String, dynamic> j) => SmokeReport(
        timestamp: DateTime.parse(j['t'] as String).toUtc(),
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        level: RiskLevel.values.byName(j['level'] as String),
        points: j['points'] as int,
      );

  Map<String, dynamic> toJson() => {
        't': timestamp.toUtc().toIso8601String(),
        'lat': lat,
        'lon': lon,
        'level': level.name,
        'points': points,
      };
}
