import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Local para o qual se consulta a qualidade do ar.
class AirPoint {
  const AirPoint(this.name, this.lat, this.lon);
  final String name;
  final double lat;
  final double lon;
}

/// Sedes de municípios do Amazonas consultadas por padrão.
///
/// As coordenadas são aproximadas (centro urbano, conferidas de memória, 2 casas
/// decimais). Como o modelo tem resolução de dezenas de km, uma diferença de poucos
/// quilômetros não altera o resultado. Revise antes de usar em pesquisa.
const amazonasAirPoints = <AirPoint>[
  AirPoint('Manaus', -3.12, -60.02),
  AirPoint('Manacapuru', -3.30, -60.62),
  AirPoint('Itacoatiara', -3.14, -58.44),
  AirPoint('Parintins', -2.63, -56.74),
  AirPoint('Coari', -4.09, -63.14),
  AirPoint('Tefé', -3.35, -64.71),
  AirPoint('Lábrea', -7.26, -64.80),
  AirPoint('Humaitá', -7.51, -63.02),
  AirPoint('Tabatinga', -4.23, -69.94),
];

/// Leitura de qualidade do ar de um local.
class AirReading {
  const AirReading({
    required this.point,
    required this.usAqi,
    required this.pm25,
    required this.pm10,
    required this.time,
  });

  final AirPoint point;

  /// Índice de qualidade do ar (padrão dos EUA), calculado pelo Open-Meteo a partir
  /// do modelo CAMS. NÃO é o IQAr oficial brasileiro.
  final int? usAqi;

  /// Material particulado fino (µg/m³).
  final double? pm25;

  /// Material particulado inalável (µg/m³).
  final double? pm10;

  /// Instante da estimativa (UTC), se informado.
  final DateTime? time;
}

/// Faixas do índice dos EUA (0 a 500), conforme a documentação do Open-Meteo
/// ("0–50 bom ... 300–500 perigoso") e a escala publicada pela EPA.
enum AirCategory {
  good('Boa'),
  moderate('Moderada'),
  unhealthySensitive('Ruim para grupos sensíveis'),
  unhealthy('Ruim'),
  veryUnhealthy('Muito ruim'),
  hazardous('Perigosa');

  const AirCategory(this.label);
  final String label;
}

AirCategory airCategoryOf(int usAqi) {
  if (usAqi <= 50) return AirCategory.good;
  if (usAqi <= 100) return AirCategory.moderate;
  if (usAqi <= 150) return AirCategory.unhealthySensitive;
  if (usAqi <= 200) return AirCategory.unhealthy;
  if (usAqi <= 300) return AirCategory.veryUnhealthy;
  return AirCategory.hazardous;
}

class AirQualityException implements Exception {
  const AirQualityException(this.message);
  final String message;
  @override
  String toString() => 'AirQualityException: $message';
}

/// Cliente da API de qualidade do ar do Open-Meteo (https://open-meteo.com/en/docs/air-quality-api).
///
/// ATENÇÃO — LIMITES CONHECIDOS:
/// - São ESTIMATIVAS DE MODELO (CAMS, Copernicus/ECMWF), não medições de estações.
///   Pela documentação, a resolução global é de ~45 km (0,4°), o que não distingue bairros.
/// - O uso gratuito é só para fins NÃO comerciais, e a atribuição é obrigatória
///   (CAMS e Open-Meteo). Conferir os termos antes de qualquer uso comercial.
/// - Esta integração foi escrita a partir da documentação. O ambiente de desenvolvimento não
///   conseguiu acessar o endpoint, então o formato de resposta NÃO foi conferido ao vivo
///   por nós. O parser é tolerante a campos ausentes e há testes com uma amostra sintética.
class AirQualityService {
  AirQualityService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const host = 'air-quality-api.open-meteo.com';
  static const path = '/v1/air-quality';
  static const currentVariables = 'pm2_5,pm10,us_aqi';

  Uri buildUri(List<AirPoint> points) => Uri.https(host, path, {
        'latitude': points.map((p) => p.lat.toString()).join(','),
        'longitude': points.map((p) => p.lon.toString()).join(','),
        'current': currentVariables,
        'timezone': 'GMT',
      });

  Future<List<AirReading>> fetch(
    List<AirPoint> points, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final http.Response response;
    try {
      response = await _client.get(buildUri(points)).timeout(timeout);
    } on SocketException {
      throw const AirQualityException('Sem conexão. Verifique o Wi-Fi ou os dados móveis.');
    } catch (_) {
      throw const AirQualityException('Não foi possível obter a qualidade do ar agora.');
    }
    if (response.statusCode != 200) {
      throw AirQualityException(
        'O serviço de qualidade do ar respondeu com erro (código ${response.statusCode}).',
      );
    }
    return parseAirQuality(utf8.decode(response.bodyBytes), points);
  }
}

/// Interpreta a resposta do Open-Meteo. Função pura, testável.
///
/// Com vários locais a API devolve uma lista (na ordem pedida); com um só, um objeto.
/// Campos ausentes ou nulos viram `null`: nada é inventado.
List<AirReading> parseAirQuality(String body, List<AirPoint> points) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    throw const AirQualityException('A resposta de qualidade do ar veio em formato inesperado.');
  }

  final List<dynamic> items;
  if (decoded is List) {
    items = decoded;
  } else if (decoded is Map<String, dynamic>) {
    if (decoded['error'] == true) {
      throw AirQualityException(
        'O serviço recusou a consulta: ${decoded['reason'] ?? 'motivo não informado'}.',
      );
    }
    items = [decoded];
  } else {
    throw const AirQualityException('A resposta de qualidade do ar veio em formato inesperado.');
  }

  if (items.length != points.length) {
    throw AirQualityException(
      'A resposta tem ${items.length} local(is), mas foram pedidos ${points.length}.',
    );
  }

  final readings = <AirReading>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final current = item is Map<String, dynamic> ? item['current'] : null;
    final map = current is Map<String, dynamic> ? current : const <String, dynamic>{};
    readings.add(AirReading(
      point: points[i],
      usAqi: (map['us_aqi'] as num?)?.round(),
      pm25: (map['pm2_5'] as num?)?.toDouble(),
      pm10: (map['pm10'] as num?)?.toDouble(),
      time: _parseUtc(map['time']),
    ));
  }
  return readings;
}

/// Com `timezone=GMT` o horário vem sem sufixo ("2026-10-19T22:00"); trata como UTC.
DateTime? _parseUtc(dynamic value) {
  if (value is! String) return null;
  final hasZone = value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value);
  return DateTime.tryParse(hasZone ? value : '${value}Z')?.toUtc();
}
