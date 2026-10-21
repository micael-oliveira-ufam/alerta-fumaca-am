import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../data/app_info.dart';
import '../logic/risk_assessment.dart';
import '../logic/symptom_stats.dart';
import '../models/smoke_context.dart';
import '../logic/air_alert.dart';
import '../logic/app_update.dart';
import '../models/smoke_report.dart';
import 'api_config.dart';

/// Erro de comunicação com o servidor próprio.
///
/// [permanent] = o servidor recusou o conteúdo (ex.: 422); reenviar o mesmo envio não adianta.
class ApiException implements Exception {
  const ApiException(this.message, {this.permanent = false});
  final String message;
  final bool permanent;
  @override
  String toString() => 'ApiException(permanent: $permanent): $message';
}

/// Célula do mapa coletivo devolvida pelo servidor (~1 km, já com mínimo de respostas).
class MapCell {
  const MapCell({
    required this.lat,
    required this.lon,
    required this.responses,
    required this.worst,
  });

  final double lat;
  final double lon;
  final int responses;
  final RiskLevel worst;

  factory MapCell.fromJson(Map<String, dynamic> j) => MapCell(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        responses: (j['respostas'] as num).toInt(),
        worst: RiskLevel.values.byName(j['pior_nivel'] as String),
      );
}

/// Bairro de Manaus com respostas suficientes (devolvido por `GET /bairros`).
class NeighborhoodStat {
  const NeighborhoodStat({required this.name, required this.responses, required this.high});

  final String name;
  final int responses;

  /// Respostas com nível alto ou de emergência.
  final int high;

  factory NeighborhoodStat.fromJson(Map<String, dynamic> j) => NeighborhoodStat(
        name: j['bairro'] as String,
        responses: (j['respostas'] as num).toInt(),
        high: (j['alto_ou_emergencia'] as num).toInt(),
      );
}

class NeighborhoodsData {
  const NeighborhoodsData({required this.items, required this.minimum, required this.source});

  /// Interpreta o JSON de `GET /bairros`. Lança se o formato for inesperado.
  factory NeighborhoodsData.fromJson(Map<String, dynamic> map) => NeighborhoodsData(
        items: [
          for (final b in map['bairros'] as List<dynamic>) NeighborhoodStat.fromJson(b as Map<String, dynamic>),
        ],
        minimum: (map['minimo_por_bairro'] as num).toInt(),
        source: map['fonte'] as String,
      );

  /// Do mais para o menos afetado (mais respostas).
  final List<NeighborhoodStat> items;
  final int minimum;
  final String source;
}

/// UUID v4 aleatório, gerado para CADA envio (não para cada aparelho).
/// Serve só para o reenvio após falha de rede não duplicar o registro no servidor.
String newSubmissionId({Random? random}) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // versão 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante RFC 4122
  String hex(int from, int to) =>
      bytes.sublist(from, to).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Monta o JSON do envio. Função pura, testável.
///
/// Privacidade: não há nome, telefone, IP, identificador de aparelho ou conta. A
/// coordenada, se houver, é arredondada a 2 casas (~1,1 km) aqui E no servidor.
Map<String, dynamic> buildAnswerPayload({
  required String submissionId,
  required DateTime recordedAt,
  required RiskResult result,
  required Exposure exposure,
  required Profile profile,
  required Map<String, int> severities,
  double? lat,
  double? lon,
  SmokeContext? context,
  String appVersion = kAppVersion,
}) {
  final withLocation = lat != null && lon != null;
  final contexto = context?.toPayload() ?? const <String, dynamic>{};
  return {
    'submission_id': submissionId,
    'registrado_em': recordedAt.toUtc().toIso8601String(),
    if (withLocation) 'lat': SmokeReport.coarsen(lat),
    if (withLocation) 'lon': SmokeReport.coarsen(lon),
    'nivel': result.level.name,
    'pontos': result.points,
    'exposicao': exposure.name,
    'perfil': {
      'idoso': profile.elderly,
      'gestante': profile.pregnant,
      'crianca': profile.child,
      'doenca_respiratoria': profile.chronicRespiratory,
      'doenca_cardiaca': profile.chronicCardiac,
    },
    'sintomas': {for (final item in symptomItems) item.id: severities[item.id] ?? 0},
    'app_version': appVersion,
    if (contexto.isNotEmpty) 'contexto': contexto,
  };
}

/// Cliente HTTP do servidor próprio (ver `server/`).
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, this.timeout = const Duration(seconds: 20)})
      : _client = client ?? http.Client(),
        _baseUrl = ApiConfig.normalize(baseUrl ?? ApiConfig.baseUrl);

  final http.Client _client;
  final String _baseUrl;
  final Duration timeout;

  bool get isConfigured => _baseUrl.isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: query);

  /// Envia uma resposta. Sucesso = 201 (novo) ou 200 (já existia: reenvio idempotente).
  Future<void> postAnswer(Map<String, dynamic> payload) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            _uri('/respostas'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } on SocketException {
      throw const ApiException('Sem conexão com o servidor.');
    } catch (_) {
      throw const ApiException('Não foi possível falar com o servidor agora.');
    }
    if (response.statusCode == 200 || response.statusCode == 201) return;
    // 4xx (exceto 429) = conteúdo recusado: não adianta reenviar o mesmo envio.
    final permanent = response.statusCode >= 400 &&
        response.statusCode < 500 &&
        response.statusCode != 429;
    throw ApiException(
      'O servidor recusou o envio (código ${response.statusCode}).',
      permanent: permanent,
    );
  }

  /// Confere se o endereço é mesmo um servidor do RespirAR Amazonas: `/health` deve devolver
  /// `{"status":"ok","version":...}` e o banco estar acessível. Devolve a versão da API.
  Future<String> checkHealth() async {
    final body = await _getJson('/health', const {});
    if (body is Map<String, dynamic> && body['status'] == 'ok') {
      return (body['version'] as String?) ?? '?';
    }
    throw const ApiException('Este endereço não parece ser um servidor do RespirAR Amazonas.');
  }

  /// JSON bruto de `GET /estatisticas` (usado também para guardar a cópia local).
  Future<Map<String, dynamic>> fetchStatsJson({int days = 30}) async {
    final body = await _getJson('/estatisticas', {'dias': '$days'});
    if (body is! Map<String, dynamic>) {
      throw const ApiException('As estatísticas vieram em formato inesperado.');
    }
    return body;
  }

  Future<StatsSnapshot> fetchStats({int days = 30}) async {
    final body = await fetchStatsJson(days: days);
    try {
      return StatsSnapshot.fromServerJson(body);
    } catch (_) {
      throw const ApiException('As estatísticas vieram em formato inesperado.');
    }
  }

  Future<Map<String, dynamic>> fetchNeighborhoodsJson({int days = 30}) async {
    final body = await _getJson('/bairros', {'dias': '$days'});
    if (body is! Map<String, dynamic>) {
      throw const ApiException('Os bairros vieram em formato inesperado.');
    }
    return body;
  }

  Future<NeighborhoodsData> fetchNeighborhoods({int days = 30}) async {
    final body = await fetchNeighborhoodsJson(days: days);
    try {
      return NeighborhoodsData.fromJson(body);
    } catch (_) {
      throw const ApiException('Os bairros vieram em formato inesperado.');
    }
  }

  /// Leitura compacta de um município (`GET /app/ar`), para os alertas de qualidade do ar.
  Future<AirAlertReading> fetchAirReading(int municipalityCode) async {
    final body = await _getJson('/app/ar', {'cod': '$municipalityCode'});
    try {
      return AirAlertReading.fromJson(body as Map<String, dynamic>);
    } catch (_) {
      throw const ApiException('A leitura de qualidade do ar veio em formato inesperado.');
    }
  }

  /// Municípios do Amazonas com código IBGE, a partir da lista que o servidor já publica.
  Future<List<({int code, String name})>> fetchAirMunicipalities() async {
    final body = await _getJson('/publico/qualidade-ar', const {});
    try {
      final list = (body as Map<String, dynamic>)['municipios'] as List<dynamic>;
      final result = [
        for (final m in list)
          (code: (m['codigo_ibge'] as num).toInt(), name: m['municipio'] as String),
      ]..sort((a, b) => a.name.compareTo(b.name));
      return result;
    } catch (_) {
      throw const ApiException('A lista de municípios veio em formato inesperado.');
    }
  }

  /// Versão do app publicada no servidor (`GET /app/versao`).
  Future<AppUpdate> fetchAppUpdate() async {
    final body = await _getJson('/app/versao', const {});
    try {
      return AppUpdate.fromJson(body as Map<String, dynamic>);
    } catch (_) {
      throw const ApiException('A informação de versão veio em formato inesperado.');
    }
  }

  Future<List<MapCell>> fetchMap({int hours = 72}) async {
    final body = await _getJson('/mapa', {'horas': '$hours'});
    try {
      return [
        for (final c in (body as Map<String, dynamic>)['celulas'] as List<dynamic>)
          MapCell.fromJson(c as Map<String, dynamic>),
      ];
    } catch (_) {
      throw const ApiException('O mapa coletivo veio em formato inesperado.');
    }
  }

  Future<dynamic> _getJson(String path, Map<String, String> query) async {
    final http.Response response;
    try {
      response = await _client.get(_uri(path, query)).timeout(timeout);
    } on SocketException {
      throw const ApiException('Sem conexão com o servidor.');
    } catch (_) {
      throw const ApiException('Não foi possível falar com o servidor agora.');
    }
    if (response.statusCode != 200) {
      throw ApiException('O servidor respondeu com erro (código ${response.statusCode}).');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const ApiException('Resposta do servidor em formato inesperado.');
    }
  }
}
