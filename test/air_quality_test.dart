import 'package:alerta_fumaca_am/services/air_quality_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// ATENÇÃO: estas amostras são SINTÉTICAS, escritas a partir da documentação do Open-Meteo
/// (o ambiente de desenvolvimento não conseguiu acessar o endpoint). Elas testam o parser,
/// não a fidelidade ao serviço real. Os números não são medições.
const _points = [
  AirPoint('Manaus', -3.12, -60.02),
  AirPoint('Tefé', -3.35, -64.71),
];

const _list = '''
[
  {"latitude": -3.12, "longitude": -60.02, "current_units": {"pm2_5": "μg/m³"},
   "current": {"time": "2026-10-19T22:00", "interval": 3600, "pm2_5": 21.4, "pm10": 30.0, "us_aqi": 72}},
  {"latitude": -3.35, "longitude": -64.71,
   "current": {"time": "2026-10-19T22:00", "pm2_5": null, "pm10": 12.5, "us_aqi": null}}
]
''';

void main() {
  group('parseAirQuality', () {
    test('lista (vários locais) na ordem pedida', () {
      final r = parseAirQuality(_list, _points);
      expect(r, hasLength(2));
      expect(r[0].point.name, 'Manaus');
      expect(r[0].usAqi, 72);
      expect(r[0].pm25, 21.4);
      expect(r[0].pm10, 30.0);
    });

    test('valores nulos viram null (nada é inventado)', () {
      final tefe = parseAirQuality(_list, _points)[1];
      expect(tefe.usAqi, isNull);
      expect(tefe.pm25, isNull);
      expect(tefe.pm10, 12.5);
    });

    test('horário sem fuso é tratado como UTC (timezone=GMT)', () {
      final t = parseAirQuality(_list, _points)[0].time!;
      expect(t.isUtc, isTrue);
      expect(t, DateTime.utc(2026, 10, 19, 22));
    });

    test('objeto único (um local)', () {
      const single = '{"current": {"time": "2026-10-19T22:00", "us_aqi": 40.4, "pm2_5": 5.0}}';
      final r = parseAirQuality(single, [_points.first]);
      expect(r.single.usAqi, 40); // arredondado
    });

    test('resposta de erro do serviço', () {
      expect(
        () => parseAirQuality('{"error": true, "reason": "limite excedido"}', [_points.first]),
        throwsA(isA<AirQualityException>().having((e) => e.message, 'message', contains('limite'))),
      );
    });

    test('quantidade de locais diferente da pedida', () {
      expect(() => parseAirQuality(_list, [_points.first]), throwsA(isA<AirQualityException>()));
    });

    test('corpo que não é JSON', () {
      expect(() => parseAirQuality('<html>', _points), throwsA(isA<AirQualityException>()));
    });

    test('local sem bloco "current" gera leitura vazia, sem falhar', () {
      final r = parseAirQuality('[{"latitude": 1}]', [_points.first]);
      expect(r.single.usAqi, isNull);
      expect(r.single.time, isNull);
    });
  });

  group('categorias do índice (faixas dos EUA)', () {
    test('limites das faixas', () {
      expect(airCategoryOf(0), AirCategory.good);
      expect(airCategoryOf(50), AirCategory.good);
      expect(airCategoryOf(51), AirCategory.moderate);
      expect(airCategoryOf(100), AirCategory.moderate);
      expect(airCategoryOf(101), AirCategory.unhealthySensitive);
      expect(airCategoryOf(150), AirCategory.unhealthySensitive);
      expect(airCategoryOf(151), AirCategory.unhealthy);
      expect(airCategoryOf(200), AirCategory.unhealthy);
      expect(airCategoryOf(201), AirCategory.veryUnhealthy);
      expect(airCategoryOf(300), AirCategory.veryUnhealthy);
      expect(airCategoryOf(301), AirCategory.hazardous);
      expect(airCategoryOf(500), AirCategory.hazardous);
    });
  });

  group('URL', () {
    test('pede os locais em listas e as variáveis atuais', () {
      final uri = AirQualityService().buildUri(_points);
      expect(uri.host, 'air-quality-api.open-meteo.com');
      expect(uri.path, '/v1/air-quality');
      expect(uri.queryParameters['latitude'], '-3.12,-3.35');
      expect(uri.queryParameters['longitude'], '-60.02,-64.71');
      expect(uri.queryParameters['current'], 'pm2_5,pm10,us_aqi');
      expect(uri.queryParameters['timezone'], 'GMT');
    });

    test('a lista padrão tem Manaus em primeiro e coordenadas dentro do Amazonas', () {
      expect(amazonasAirPoints.first.name, 'Manaus');
      for (final p in amazonasAirPoints) {
        expect(p.lat, inInclusiveRange(-10, 3));
        expect(p.lon, inInclusiveRange(-74, -56));
      }
    });
  });
}
