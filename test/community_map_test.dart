import 'package:alerta_fumaca_am/logic/community_map.dart';
import 'package:alerta_fumaca_am/logic/risk_assessment.dart';
import 'package:alerta_fumaca_am/models/smoke_report.dart';
import 'package:alerta_fumaca_am/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

SmokeReport _r(double lat, double lon, RiskLevel level) => SmokeReport(
      timestamp: DateTime.utc(2026, 10, 19),
      lat: SmokeReport.coarsen(lat),
      lon: SmokeReport.coarsen(lon),
      level: level,
      points: 5,
    );

void main() {
  test('registros com a mesma coordenada arredondada ficam na MESMA célula', () {
    // Regressão: floor(-3.12 / 0.01) cai em -313 ou -312 conforme o ponto flutuante,
    // o que separava registros idênticos. Aqui o agrupamento é pelo valor arredondado.
    final cells = aggregateReports([
      _r(-3.119, -60.021, RiskLevel.low),
      _r(-3.121, -60.019, RiskLevel.moderate),
      _r(-3.122, -60.018, RiskLevel.low),
    ]);
    expect(cells, hasLength(1));
    expect(cells.single.count, 3);
    expect(cells.single.lat, -3.12);
    expect(cells.single.lon, -60.02);
  });

  test('guarda o pior nível da célula', () {
    final cells = aggregateReports([
      _r(-3.12, -60.02, RiskLevel.low),
      _r(-3.12, -60.02, RiskLevel.high),
      _r(-3.12, -60.02, RiskLevel.moderate),
    ]);
    expect(cells.single.worst, RiskLevel.high);
  });

  test('áreas diferentes geram células diferentes', () {
    final cells = aggregateReports([
      _r(-3.12, -60.02, RiskLevel.low),
      _r(-3.13, -60.02, RiskLevel.low),
    ]);
    expect(cells, hasLength(2));
  });

  test('células do servidor são repassadas sem alteração', () {
    final cells = cellsFromServer(const [
      MapCell(lat: -3.12, lon: -60.02, responses: 4, worst: RiskLevel.emergency),
    ]);
    expect(cells.single.count, 4);
    expect(cells.single.worst, RiskLevel.emergency);
  });
}
