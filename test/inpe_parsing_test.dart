import 'package:alerta_fumaca_am/models/fire_hotspot.dart';
import 'package:alerta_fumaca_am/models/fire_satellite.dart';
import 'package:alerta_fumaca_am/services/inpe_fire_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Amostra no formato do WFS do INPE. O primeiro foco reproduz o caso real em que, ao pedir
/// só algumas propriedades (`propertyName`), o INPE devolve `"geometry": null` e a posição
/// fica em `longitude`/`latitude`. O segundo tem geometria Point.
const _sample = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "focos_48h_br_todosats.1",
      "geometry": null,
      "properties": {
        "longitude": -60.0217,
        "latitude": -3.119,
        "data_hora_gmt": "2026-10-17T19:19:00Z",
        "satelite": "NOAA-20",
        "estado": "AMAZONAS",
        "municipio": "MANAUS",
        "bioma": "Amazônia",
        "frp": 12.5,
        "risco_fogo": 1,
        "numero_dias_sem_chuva": 5
      }
    },
    {
      "type": "Feature",
      "geometry": {"type": "Point", "coordinates": [-50.06847, -14.74798]},
      "properties": {
        "data_hora_gmt": "2026-10-17T19:19:00Z",
        "satelite": "AQUA_M-T",
        "estado": "GOIÁS",
        "municipio": "CRIXÁS",
        "bioma": "Cerrado",
        "frp": 10.6
      }
    },
    {
      "type": "Feature",
      "geometry": null,
      "properties": {"data_hora_gmt": "2026-10-17T19:19:00Z", "estado": "AMAZONAS"}
    }
  ]
}
''';

void main() {
  group('interpretação do GeoJSON', () {
    test('lê a posição das propriedades quando a geometria é null', () {
      final manaus = parseFeatureCollection(_sample, onlyState: 'AMAZONAS').single;
      expect(manaus.lon, closeTo(-60.0217, 1e-9));
      expect(manaus.lat, closeTo(-3.119, 1e-9));
    });

    test('lê a geometria Point como [longitude, latitude]', () {
      final goias = parseFeatureCollection(_sample, onlyState: 'GOIÁS').single;
      expect(goias.lon, closeTo(-50.06847, 1e-9));
      expect(goias.lat, closeTo(-14.74798, 1e-9));
    });

    test('ignora feição sem posição e sem filtro de estado mantém os demais', () {
      final all = parseFeatureCollection(_sample);
      expect(all, hasLength(2)); // a terceira feição não tem posição
    });

    test('com filtro, descarta focos de outros estados', () {
      final list = parseFeatureCollection(_sample, onlyState: 'AMAZONAS');
      expect(list, hasLength(1));
      expect(list.single.state, 'AMAZONAS');
    });

    test('converte data_hora_gmt para UTC', () {
      final h = parseFeatureCollection(_sample, onlyState: 'AMAZONAS').single;
      expect(h.detectedAt.isUtc, isTrue);
      expect(h.detectedAt, DateTime.utc(2026, 10, 17, 19, 19));
    });

    test('lê FRP, dias sem chuva e risco de fogo; classifica a intensidade de exibição', () {
      final h = parseFeatureCollection(_sample, onlyState: 'AMAZONAS').single;
      expect(h.frp, 12.5);
      expect(h.daysWithoutRain, 5);
      expect(h.fireRisk, 1.0);
      expect(h.intensity, FireIntensity.medium);
    });

    test('campos opcionais ausentes viram null (nada é inventado)', () {
      final goias = parseFeatureCollection(_sample, onlyState: 'GOIÁS').single;
      expect(goias.daysWithoutRain, isNull);
      expect(goias.fireRisk, isNull);
    });

    test('associa o satélite à família', () {
      final list = parseFeatureCollection(_sample);
      expect(list[0].family, FireSatellite.noaa20);
      expect(list[1].family, FireSatellite.modis);
    });

    test('rejeita resposta que não é FeatureCollection', () {
      expect(
        () => parseFeatureCollection('{"type":"ServiceException"}'),
        throwsA(isA<InpeException>()),
      );
      expect(() => parseFeatureCollection('<html>'), throwsA(isA<InpeException>()));
    });
  });

  group('famílias de satélites', () {
    test('nomes do INPE por família (conferidos no servidor)', () {
      expect(FireSatellite.modis.inpeNames, ['AQUA_M-T', 'TERRA_M-T']);
      expect(FireSatellite.noaa20.inpeNames, ['NOAA-20']);
      expect(FireSatellite.suomi.inpeNames, ['NPP-375', 'NPP-375D']);
      expect(FireSatellite.noaa21.inpeNames, ['NOAA-21']);
    });

    test('padrão = MODIS, NOAA-20 e Suomi NPP', () {
      expect(
        FireSatellite.defaults(),
        {FireSatellite.modis, FireSatellite.noaa20, FireSatellite.suomi},
      );
    });

    test('satélite desconhecido não pertence a nenhuma família', () {
      expect(FireSatellite.fromInpeName('GOES-19'), isNull);
    });

    test('lista de nomes é ordenada e sem repetição', () {
      expect(
        FireSatellite.inpeNamesOf(FireSatellite.values),
        ['AQUA_M-T', 'NOAA-20', 'NOAA-21', 'NPP-375', 'NPP-375D', 'TERRA_M-T'],
      );
    });
  });

  group('consulta', () {
    test('URL direta: camada todosats, filtro de estado e de satélites', () {
      final service = InpeFireService(apiBaseUrl: '');
      final today = service.buildUri(FireWindow.today);
      expect(today.host, 'terrabrasilis.dpi.inpe.br');
      expect(today.queryParameters['typeName'], 'dados_abertos:focos_hoje_br_todosats');
      expect(
        today.queryParameters['CQL_FILTER'],
        "estado='AMAZONAS' AND satelite IN ('AQUA_M-T','NOAA-20','NPP-375','NPP-375D','TERRA_M-T')",
      );
      expect(today.queryParameters['outputFormat'], 'application/json');
      expect(today.queryParameters['propertyName'], startsWith('longitude,latitude'));

      final h48 = service.buildUri(FireWindow.last48h);
      expect(h48.queryParameters['typeName'], 'dados_abertos:focos_48h_br_todosats');
    });

    test('escopo Brasil não filtra por estado', () {
      final service = InpeFireService(apiBaseUrl: '');
      final uri = service.buildUri(
        FireWindow.today,
        scope: FireScope.brasil,
        satellites: {FireSatellite.noaa20},
      );
      expect(uri.queryParameters['CQL_FILTER'], "satelite IN ('NOAA-20')");
    });

    test('com servidor próprio, usa /focos com janela, escopo e satélites', () {
      final service = InpeFireService(apiBaseUrl: 'https://api.exemplo.com.br/');
      final uri = service.endpointFor(
        FireWindow.last48h,
        scope: FireScope.brasil,
        satellites: {FireSatellite.suomi, FireSatellite.modis},
      );
      expect(uri.host, 'api.exemplo.com.br');
      expect(uri.path, '/focos');
      expect(uri.queryParameters, {
        'window': 'last48h',
        'scope': 'brasil',
        'satellites': 'AQUA_M-T,NPP-375,NPP-375D,TERRA_M-T',
      });
    });

    test('sem servidor próprio, usa o INPE direto', () {
      final uri = InpeFireService(apiBaseUrl: '').endpointFor(FireWindow.today);
      expect(uri.host, 'terrabrasilis.dpi.inpe.br');
    });
  });
}
