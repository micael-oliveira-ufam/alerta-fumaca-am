import 'dart:io';

import 'package:respirar_amazonas/models/fire_satellite.dart';
import 'package:respirar_amazonas/services/inpe_fire_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cabeçalho observado nos arquivos diários dos Dados Abertos do INPE (20/10/2026).
const _header = 'id,lat,lon,data_hora_gmt,satelite,municipio,estado,pais,municipio_id,estado_id,pais_id,'
    'numero_dias_sem_chuva,precipitacao,risco_fogo,bioma,frp';

String _row(
  String when, {
  String lat = '-7.2',
  String lon = '-64.8',
  String sat = 'NOAA-20',
  String city = 'Lábrea',
  String state = 'AMAZONAS',
  String days = '9',
  String risk = '0.8',
  String frp = '12.5',
}) =>
    'x,$lat,$lon,$when,$sat,$city,$state,Brasil,1,13,33,$days,0.0,$risk,Amazônia,$frp';

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final now = DateTime.utc(2026, 10, 20, 12);

  group('csvFeatures', () {
    test('converte, filtra estado, satélite e janela', () {
      final csv = [
        _header,
        _row('2026-10-20 10:00:00'),
        _row('2026-10-20 10:05:00', state: 'PARÁ'),
        _row('2026-10-20 10:10:00', sat: 'GOES-19'),
        _row('2026-10-17 10:00:00'),
        _row('2026-10-20 23:00:00'),
        _row('2026-10-20 10:00:00', lat: 'abc'),
        'linha curta',
      ].join('\n');
      final f = InpeFireService.csvFeatures(csv, nowUtc: now, satelliteNames: {'NOAA-20'});
      expect(f, hasLength(1));
      final p = f.single['properties'] as Map<String, dynamic>;
      expect(p['latitude'], -7.2);
      expect(p['longitude'], -64.8);
      expect(p['estado'], 'AMAZONAS');
      expect(p['municipio'], 'LÁBREA');
      expect(p['satelite'], 'NOAA-20');
      expect(p['frp'], 12.5);
      expect(p['numero_dias_sem_chuva'], 9);
      expect(DateTime.parse(p['data_hora_gmt'] as String), DateTime.utc(2026, 10, 20, 10));
    });

    test('valor sentinela -999 vira nulo e escopo Brasil não filtra estado', () {
      final csv = [_header, _row('2026-10-20 10:00:00', state: 'Pará', risk: '-999', days: '-999')].join('\n');
      final f = InpeFireService.csvFeatures(csv, nowUtc: now, onlyAmazonas: false);
      expect(f, hasLength(1));
      final p = f.single['properties'] as Map<String, dynamic>;
      expect(p['risco_fogo'], isNull);
      expect(p['numero_dias_sem_chuva'], isNull);
      expect(p['estado'], 'PARÁ');
    });

    test('aceita ponto e vírgula com vírgula decimal e estado em caixa mista', () {
      final csv = [
        _header.replaceAll(',', ';'),
        'x;-7,2;-64,8;2026-10-20 10:00:00;NOAA-20;Lábrea;Amazonas;Brasil;1;13;33;9;0,0;0,8;Amazônia;12,5',
      ].join('\n');
      final f = InpeFireService.csvFeatures(csv, nowUtc: now);
      expect(f, hasLength(1));
      expect((f.single['properties'] as Map<String, dynamic>)['frp'], 12.5);
    });

    test('arquivo vazio ou cabeçalho inesperado lança erro de formato', () {
      expect(
        () => InpeFireService.csvFeatures('', nowUtc: now),
        throwsA(isA<InpeException>().having((e) => e.kind, 'kind', InpeErrorKind.format)),
      );
      expect(
        () => InpeFireService.csvFeatures('a,b,c\n1,2,3', nowUtc: now),
        throwsA(isA<InpeException>().having((e) => e.kind, 'kind', InpeErrorKind.format)),
      );
    });
  });

  group('endereços e dias', () {
    test('csvUri segue o padrão focos_diario_br_AAAAMMDD.csv', () {
      final uri = InpeFireService.csvUri(DateTime.utc(2026, 10, 5));
      expect(uri.host, 'dataserver-coids.inpe.br');
      expect(uri.path, '/queimadas/queimadas/focos/csv/diario/Brasil/focos_diario_br_20261005.csv');
    });

    test('dias que cobrem cada janela', () {
      expect(InpeFireService.csvDays(FireWindow.last48h, now), hasLength(3));
      expect(InpeFireService.csvDays(FireWindow.today, now), [DateTime.utc(2026, 10, 20)]);
      // Antes das 04:00 UTC o dia de Manaus começou no dia UTC anterior.
      expect(InpeFireService.csvDays(FireWindow.today, DateTime.utc(2026, 10, 20, 2)),
          [DateTime.utc(2026, 10, 20), DateTime.utc(2026, 10, 19)]);
    });
  });

  group('download pelo aparelho', () {
    test('baixa os CSV, ignora 404 e entrega os focos', () async {
      final recent = _stamp(DateTime.now().toUtc().subtract(const Duration(hours: 1)));
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        final today = InpeFireService.csvUri(DateTime.now().toUtc()).path;
        if (request.url.path == today) {
          return http.Response([_header, _row(recent)].join('\n'), 200);
        }
        return http.Response('nao encontrado', 404);
      });
      final service = InpeFireService(client: client, apiBaseUrl: '', phoneDownload: true);
      final result = await service.fetch(FireWindow.last48h, satellites: {FireSatellite.noaa20});
      expect(result.fromCache, isFalse);
      expect(result.hotspots, hasLength(1));
      expect(result.hotspots.single.municipality, 'LÁBREA');
      expect(hosts.toSet(), {'dataserver-coids.inpe.br'});
    });

    test('sem servidor próprio e sem rede, relança o erro', () async {
      final client = MockClient((_) async => throw const SocketException('sem rede'));
      final service = InpeFireService(client: client, apiBaseUrl: '', phoneDownload: true);
      await expectLater(
        service.fetch(FireWindow.last48h),
        throwsA(isA<InpeException>().having((e) => e.kind, 'kind', InpeErrorKind.network)),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('se o download do INPE falha e há servidor próprio, usa o servidor', () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        if (request.url.host == 'dataserver-coids.inpe.br') throw const SocketException('sem rota');
        return http.Response('{"type":"FeatureCollection","features":[]}', 200);
      });
      final service =
          InpeFireService(client: client, apiBaseUrl: 'https://api.exemplo.com.br', phoneDownload: true);
      final result = await service.fetch(FireWindow.last48h, retryDelay: Duration.zero);
      expect(result.hotspots, isEmpty);
      expect(hosts, contains('api.exemplo.com.br'));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
