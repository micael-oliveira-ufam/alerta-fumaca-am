import 'package:respirar_amazonas/logic/fire_stats.dart';
import 'package:respirar_amazonas/models/fire_hotspot.dart';
import 'package:respirar_amazonas/models/fire_satellite.dart';
import 'package:flutter_test/flutter_test.dart';

FireHotspot _h({
  double lat = -3.1,
  double lon = -60.0,
  String state = 'AMAZONAS',
  String municipality = 'MANAUS',
  String satellite = 'NOAA-20',
  String biome = 'Amazônia',
  DateTime? at,
}) =>
    FireHotspot(
      lat: lat,
      lon: lon,
      detectedAt: at ?? DateTime.utc(2026, 10, 19, 12),
      state: state,
      municipality: municipality,
      satellite: satellite,
      biome: biome,
    );

void main() {
  group('FireSummary', () {
    final hotspots = [
      _h(satellite: 'NOAA-20', municipality: 'MANAUS'),
      _h(satellite: 'NOAA-20', municipality: 'MANAUS'),
      _h(satellite: 'AQUA_M-T', municipality: 'COARI', at: DateTime.utc(2026, 10, 19, 18, 30)),
      _h(satellite: 'NPP-375D', municipality: 'COARI'),
      _h(satellite: 'NPP-375', state: 'PARÁ', municipality: 'ALTAMIRA'),
      _h(satellite: 'GOES-19', state: 'MATO GROSSO', municipality: 'SINOP', biome: 'Cerrado'),
    ];
    final summary = FireSummary(hotspots);

    test('totais e parcela do Amazonas', () {
      expect(summary.total, 6);
      expect(summary.amazonasCount, 4);
      expect(summary.amazonasSharePercent, 66.7); // 4/6
    });

    test('contagem por família de satélite (variantes do Suomi NPP somam juntas)', () {
      expect(summary.bySatellite[FireSatellite.noaa20], 2);
      expect(summary.bySatellite[FireSatellite.modis], 1);
      expect(summary.bySatellite[FireSatellite.suomi], 2); // NPP-375 + NPP-375D
      expect(summary.bySatellite[FireSatellite.noaa21], isNull);
      // GOES-19 não pertence a nenhuma família suportada.
      expect(summary.bySatellite.values.fold<int>(0, (a, b) => a + b), 5);
    });

    test('ranking de municípios do Amazonas ordenado, com desempate alfabético', () {
      final ranking = FireSummary.ranked(summary.byMunicipalityAmazonas);
      expect(ranking.map((e) => '${e.key}:${e.value}'), ['COARI:2', 'MANAUS:2']);
    });

    test('ranking de estados com limite', () {
      final ranking = FireSummary.ranked(summary.byState, limit: 1);
      expect(ranking.single.key, 'AMAZONAS');
      expect(ranking.single.value, 4);
    });

    test('detecção mais recente', () {
      expect(summary.lastDetection, DateTime.utc(2026, 10, 19, 18, 30));
    });

    test('lista vazia não gera divisão por zero', () {
      final empty = FireSummary(const []);
      expect(empty.total, 0);
      expect(empty.amazonasSharePercent, isNull);
      expect(empty.lastDetection, isNull);
    });

    test('rótulos vazios viram "Não informado"', () {
      final s = FireSummary([_h(biome: '  ')]);
      expect(s.byBiome.keys.single, 'Não informado');
    });
  });

  group('aggregateGrid', () {
    test('cada foco cai em exatamente uma célula (a soma é preservada)', () {
      final points = [
        _h(lat: -3.10, lon: -60.10),
        _h(lat: -3.20, lon: -60.20), // mesma célula de 0,5°
        _h(lat: -3.60, lon: -60.10), // célula vizinha
        _h(lat: 2.10, lon: -55.10),
      ];
      final cells = aggregateGrid(points);
      expect(cells.fold<int>(0, (sum, c) => sum + c.count), points.length);
      expect(cells, hasLength(3));
    });

    test('centro da célula fica no meio do quadrado', () {
      final cells = aggregateGrid([_h(lat: -3.10, lon: -60.10)]);
      // floor(-3.10/0.5) = -7  ->  centro = (-7 + 0,5) * 0,5 = -3,25
      expect(cells.single.lat, closeTo(-3.25, 1e-9));
      expect(cells.single.lon, closeTo(-60.25, 1e-9));
    });

    test('raio cresce com a contagem e tem piso', () {
      expect(gridRadius(1), 5);
      expect(gridRadius(10), closeTo(9, 1e-9));
      expect(gridRadius(100), closeTo(13, 1e-9));
      expect(gridRadius(0), 5); // contagem inválida não gera log de zero
    });
  });
}
