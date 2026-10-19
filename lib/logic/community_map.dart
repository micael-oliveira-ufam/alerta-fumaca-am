import '../models/smoke_report.dart';
import '../services/api_client.dart' show MapCell;
import 'risk_assessment.dart';

/// Área (~1 km) do mapa da comunidade.
class CommunityCell {
  CommunityCell(this.lat, this.lon, {this.count = 0, this.worst = RiskLevel.low});

  /// Centro da célula, em graus com 2 casas decimais.
  final double lat;
  final double lon;
  int count;
  RiskLevel worst;
}

/// Agrupa registros locais por coordenada arredondada a 2 casas (~1,1 km).
///
/// As coordenadas dos registros já foram arredondadas na gravação. Agrupamos pelo valor
/// inteiro em centésimos de grau, e não por `floor(lat / 0.01)`: a divisão em ponto
/// flutuante pode cair do lado errado (ex.: -3.12 / 0.01 = -312.00000000000006), o que
/// separaria registros idênticos em células diferentes.
List<CommunityCell> aggregateReports(Iterable<SmokeReport> reports) {
  final cells = <String, CommunityCell>{};
  for (final r in reports) {
    final i = (r.lat * 100).round();
    final j = (r.lon * 100).round();
    final cell = cells.putIfAbsent('$i:$j', () => CommunityCell(i / 100, j / 100));
    cell.count++;
    if (r.level.index > cell.worst.index) cell.worst = r.level;
  }
  return cells.values.toList();
}

/// Converte as células devolvidas pelo servidor (já filtradas por mínimo de respostas).
List<CommunityCell> cellsFromServer(Iterable<MapCell> cells) => [
      for (final c in cells) CommunityCell(c.lat, c.lon, count: c.responses, worst: c.worst),
    ];
