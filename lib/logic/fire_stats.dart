import 'dart:math' as math;

import '../models/fire_hotspot.dart';
import '../models/fire_satellite.dart';
import '../services/inpe_fire_service.dart' show InpeFireService;

/// Resumo dos focos de uma consulta. Só contagens e somas dos dados recebidos;
/// nenhum valor é estimado nem interpolado.
class FireSummary {
  FireSummary(this.hotspots) {
    for (final h in hotspots) {
      final family = h.family;
      if (family != null) {
        bySatellite[family] = (bySatellite[family] ?? 0) + 1;
      }
      _inc(byState, _label(h.state));
      _inc(byBiome, _label(h.biome));
      if (h.state == InpeFireService.state) {
        amazonasCount++;
        _inc(byMunicipalityAmazonas, _label(h.municipality));
      }
      final last = lastDetection;
      if (last == null || h.detectedAt.isAfter(last)) lastDetection = h.detectedAt;
    }
  }

  final List<FireHotspot> hotspots;

  /// Focos por família de satélite (apenas as famílias suportadas).
  final Map<FireSatellite, int> bySatellite = {};
  final Map<String, int> byState = {};
  final Map<String, int> byBiome = {};
  final Map<String, int> byMunicipalityAmazonas = {};

  int amazonasCount = 0;

  /// Detecção mais recente (UTC), ou `null` se não há focos.
  DateTime? lastDetection;

  int get total => hotspots.length;

  /// Parcela do Amazonas no total, em %, ou `null` se não há focos.
  double? get amazonasSharePercent =>
      total == 0 ? null : (1000 * amazonasCount / total).round() / 10;

  /// Entradas ordenadas do maior para o menor (empate: ordem alfabética).
  static List<MapEntry<String, int>> ranked(Map<String, int> counts, {int? limit}) {
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return limit == null || entries.length <= limit ? entries : entries.sublist(0, limit);
  }

  static void _inc(Map<String, int> map, String key) => map[key] = (map[key] ?? 0) + 1;

  static String _label(String value) => value.trim().isEmpty ? 'Não informado' : value.trim();
}

/// Célula de uma grade regular, para desenhar muitos focos sem sobrecarregar o mapa.
class GridCell {
  GridCell(this.lat, this.lon);

  /// Centro da célula.
  final double lat;
  final double lon;
  int count = 0;
}

/// Agrupa focos em células de [cellDegrees] graus (0,5° ≈ 55 km no equador).
///
/// É uma agregação apenas visual: cada foco cai em exatamente uma célula e a soma
/// das contagens é igual ao número de focos.
List<GridCell> aggregateGrid(Iterable<FireHotspot> hotspots, {double cellDegrees = 0.5}) {
  final cells = <String, GridCell>{};
  for (final h in hotspots) {
    final i = (h.lat / cellDegrees).floor();
    final j = (h.lon / cellDegrees).floor();
    final cell = cells.putIfAbsent(
      '$i:$j',
      () => GridCell((i + 0.5) * cellDegrees, (j + 0.5) * cellDegrees),
    );
    cell.count++;
  }
  return cells.values.toList();
}

/// Raio (px) do círculo de uma célula, crescendo devagar com a contagem.
/// Escala de exibição, sem significado quantitativo além de "mais focos = maior".
double gridRadius(int count) => 5 + 4 * math.log(count < 1 ? 1 : count) / math.ln10;
