import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fire_hotspot.dart';
import '../models/fire_satellite.dart';
import 'api_config.dart';

/// Erro ao obter ou interpretar os dados do INPE.
///
/// [kind] separa a causa, para a tela mostrar uma mensagem clara.
class InpeException implements Exception {
  const InpeException(this.message, {this.kind = InpeErrorKind.other});
  final String message;
  final InpeErrorKind kind;
  @override
  String toString() => 'InpeException($kind): $message';
}

enum InpeErrorKind {
  /// O aparelho não conseguiu encontrar o servidor (DNS) ou não há rede.
  network,

  /// O servidor respondeu, mas com erro HTTP.
  server,

  /// A resposta chegou, mas não está no formato esperado.
  format,

  other,
}

/// Resultado de uma consulta: os focos e de onde eles vieram.
class FireResult {
  const FireResult({
    required this.hotspots,
    required this.fetchedAt,
    required this.fromCache,
  });

  final List<FireHotspot> hotspots;

  /// Quando os dados foram obtidos do INPE (ou quando foram salvos, se [fromCache]).
  final DateTime fetchedAt;

  /// `true` quando a rede falhou e os dados vêm da última resposta salva.
  final bool fromCache;
}

/// Janela temporal dos focos, cada uma com sua camada oficial do INPE.
///
/// Usa as camadas `todosats` (todos os satélites), para poder separar por satélite.
/// As camadas `satref` trazem apenas o satélite de referência.
enum FireWindow {
  // "Hoje" usa a camada de 48 h e filtra o dia local (Manaus) no cliente: a camada
  // `focos_hoje_*` do INPE costumava vir sem registros, enquanto a de 48 h sempre trazia focos.
  today('Hoje', 'dados_abertos:focos_48h_br_todosats', 'today'),
  last48h('Últimas 48 h', 'dados_abertos:focos_48h_br_todosats', 'last48h');

  const FireWindow(this.label, this.layer, this.apiName);

  final String label;

  /// Nome da camada no TerraBrasilis (WFS), conferido em GetCapabilities.
  final String layer;

  /// Nome usado no servidor próprio (`/focos?window=...`).
  final String apiName;

  /// Fuso de Manaus (UTC-4, sem horário de verão).
  static const manausOffset = Duration(hours: -4);

  /// Início do dia atual em Manaus, em UTC.
  static DateTime startOfTodayUtc([DateTime? now]) {
    final local = (now ?? DateTime.now()).toUtc().add(manausOffset);
    return DateTime.utc(local.year, local.month, local.day).subtract(manausOffset);
  }

  /// Aplica o recorte de tempo da janela (só "Hoje" recorta; 48 h já vem da camada).
  List<FireHotspot> filter(List<FireHotspot> all, [DateTime? now]) {
    if (this != FireWindow.today) return all;
    final start = startOfTodayUtc(now);
    return all.where((h) => !h.detectedAt.toUtc().isBefore(start)).toList();
  }
}

/// Abrangência geográfica da consulta.
enum FireScope {
  amazonas('Amazonas', 'amazonas'),
  brasil('Brasil', 'brasil');

  const FireScope(this.label, this.apiName);
  final String label;
  final String apiName;
}

/// Cliente dos focos de calor do INPE (TerraBrasilis, WFS 2.0.0, GeoJSON).
///
/// Duas formas de acesso:
/// 1. **Direta**: o app consulta o WFS do INPE (padrão).
/// 2. **Via servidor próprio**: se `API_BASE_URL` estiver definido na compilação, o app
///    consulta `$API_BASE_URL/focos`, que devolve a mesma resposta GeoJSON com cache.
///    Útil quando o aparelho não alcança o domínio do INPE. Ver `server/`.
///
/// Campos usados (conferidos em requisições reais): `data_hora_gmt`, `satelite`,
/// `estado`, `municipio`, `bioma`, `frp`, `longitude`, `latitude`, `risco_fogo`,
/// `numero_dias_sem_chuva`.
///
/// IMPORTANTE: pedimos só esses campos (`propertyName`) para reduzir o tamanho da
/// resposta. Nesse caso o INPE devolve `"geometry": null`; as coordenadas vêm de
/// `longitude` e `latitude`, que são propriedades.
///
/// Se a rede falhar, o app mostra a última resposta válida salva neste aparelho
/// (somente para o Amazonas; a consulta do Brasil inteiro é grande demais para o cache).
class InpeFireService {
  InpeFireService({http.Client? client, SharedPreferences? prefs, String? apiBaseUrl})
      : _client = client ?? http.Client(),
        _prefs = prefs,
        _apiBaseUrl = ApiConfig.normalize(apiBaseUrl ?? ApiConfig.baseUrl);

  final http.Client _client;
  SharedPreferences? _prefs;
  final String _apiBaseUrl;

  static const host = 'terrabrasilis.dpi.inpe.br';
  static const path = '/queimadas/geoserver/ows';
  static const state = 'AMAZONAS';

  static const propertyNames = 'longitude,latitude,data_hora_gmt,satelite,municipio,'
      'estado,bioma,frp,risco_fogo,numero_dias_sem_chuva';

  /// Limite do cache em disco (caracteres do JSON). Acima disso, não salva.
  static const maxCachedChars = 1500000;

  /// Página pública do programa, para o usuário conferir a fonte.
  static final sourcePage = Uri.https(host, '/queimadas/');

  /// Filtro CQL do escopo e dos satélites. Os nomes vêm de [FireSatellite] (lista
  /// fechada), nunca de texto digitado, então não há injeção de CQL.
  static String cqlFilter(FireScope scope, Iterable<FireSatellite> satellites) {
    final parts = <String>[];
    if (scope == FireScope.amazonas) parts.add("estado='$state'");
    final names = FireSatellite.inpeNamesOf(satellites);
    if (names.isNotEmpty) {
      parts.add("satelite IN (${names.map((n) => "'$n'").join(',')})");
    }
    return parts.join(' AND ');
  }

  /// Consulta direta ao WFS do INPE.
  Uri buildUri(
    FireWindow window, {
    FireScope scope = FireScope.amazonas,
    Iterable<FireSatellite>? satellites,
  }) {
    final cql = cqlFilter(scope, satellites ?? FireSatellite.defaults());
    return Uri.https(host, path, {
      'service': 'WFS',
      'version': '2.0.0',
      'request': 'GetFeature',
      'typeName': window.layer,
      'outputFormat': 'application/json',
      'propertyName': propertyNames,
      if (cql.isNotEmpty) 'CQL_FILTER': cql,
    });
  }

  /// Endereço efetivo da consulta: o servidor próprio, se configurado, ou o INPE direto.
  Uri endpointFor(
    FireWindow window, {
    FireScope scope = FireScope.amazonas,
    Iterable<FireSatellite>? satellites,
  }) {
    final sats = satellites ?? FireSatellite.defaults();
    if (_apiBaseUrl.isEmpty) return buildUri(window, scope: scope, satellites: sats);
    return Uri.parse('$_apiBaseUrl/focos').replace(queryParameters: {
      'window': window.apiName,
      'scope': scope.apiName,
      'satellites': FireSatellite.inpeNamesOf(sats).join(','),
    });
  }

  /// Preferências são opcionais: se falharem, o app segue sem cache.
  Future<SharedPreferences?> _preferences() async {
    try {
      return _prefs ??= await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// Busca os focos. Em falha de rede, devolve a última resposta salva (se houver).
  Future<FireResult> fetch(
    FireWindow window, {
    FireScope scope = FireScope.amazonas,
    Set<FireSatellite>? satellites,
    Duration timeout = const Duration(seconds: 30),
    int retries = 2,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    final sats = satellites ?? FireSatellite.defaults();
    final onlyState = scope == FireScope.amazonas ? state : null;
    try {
      final body = await _downloadWithRetry(
        endpointFor(window, scope: scope, satellites: sats),
        timeout: timeout,
        retries: retries,
        retryDelay: retryDelay,
      );
      final hotspots = window.filter(parseFeatureCollection(body, onlyState: onlyState));
      final now = DateTime.now().toUtc();
      if (scope == FireScope.amazonas) await _writeCache(window, sats, body, now);
      return FireResult(hotspots: hotspots, fetchedAt: now, fromCache: false);
    } on InpeException catch (e) {
      final canUseCache = scope == FireScope.amazonas &&
          (e.kind == InpeErrorKind.network || e.kind == InpeErrorKind.server);
      if (canUseCache) {
        final cached = await _readCache(window, sats);
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  /// Repete a consulta em falhas de rede ou do servidor (ex.: primeira conexão lenta ou
  /// um DNS que ainda não respondeu). Espera [retryDelay] vezes o número da tentativa.
  /// Erros de formato não são repetidos: a resposta chegou, só não é o esperado.
  Future<String> _downloadWithRetry(
    Uri uri, {
    required Duration timeout,
    required int retries,
    required Duration retryDelay,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await _download(uri, timeout);
      } on InpeException catch (e) {
        final retryable = e.kind == InpeErrorKind.network || e.kind == InpeErrorKind.server;
        if (!retryable || attempt >= retries) rethrow;
        attempt++;
        await Future<void>.delayed(retryDelay * attempt);
      }
    }
  }

  Future<String> _download(Uri uri, Duration timeout) async {
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on SocketException {
      throw const InpeException(
        'Sem conexão com o servidor dos focos de calor. Verifique o Wi-Fi ou os dados móveis.',
        kind: InpeErrorKind.network,
      );
    } catch (e) {
      // Inclui ClientException (que envolve erros de DNS), TimeoutException e afins.
      throw const InpeException(
        'Não foi possível obter os focos de calor agora. Tente novamente em instantes.',
        kind: InpeErrorKind.network,
      );
    }
    if (response.statusCode != 200) {
      throw InpeException(
        'O servidor dos focos respondeu com erro (código ${response.statusCode}). Tente mais tarde.',
        kind: InpeErrorKind.server,
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  static String _cacheKey(FireWindow w) => 'inpe_cache_v2_${w.name}';

  static String _satKey(Iterable<FireSatellite> sats) => FireSatellite.inpeNamesOf(sats).join(',');

  Future<void> _writeCache(
    FireWindow window,
    Set<FireSatellite> sats,
    String body,
    DateTime savedAt,
  ) async {
    if (body.length > maxCachedChars) return;
    final prefs = await _preferences();
    if (prefs == null) return;
    try {
      await prefs.setString(
        _cacheKey(window),
        jsonEncode({'savedAt': savedAt.toIso8601String(), 'sats': _satKey(sats), 'body': body}),
      );
    } catch (_) {
      // Falha ao salvar o cache não deve afetar a consulta.
    }
  }

  Future<FireResult?> _readCache(FireWindow window, Set<FireSatellite> sats) async {
    final prefs = await _preferences();
    if (prefs == null) return null;
    try {
      final raw = prefs.getString(_cacheKey(window));
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      // Só reaproveita se foi salvo com a mesma seleção de satélites.
      if (map['sats'] != _satKey(sats)) return null;
      final savedAt = DateTime.parse(map['savedAt'] as String).toUtc();
      final hotspots = window.filter(parseFeatureCollection(map['body'] as String, onlyState: state));
      return FireResult(hotspots: hotspots, fetchedAt: savedAt, fromCache: true);
    } catch (_) {
      return null; // cache ausente, corrompido ou indisponível: ignora
    }
  }
}

/// Converte a resposta GeoJSON do WFS em focos. Função pura, testável.
///
/// A posição vem da geometria `Point` quando existe; senão, dos campos
/// `longitude`/`latitude` das propriedades (caso em que o INPE devolve `geometry: null`).
/// Feições sem posição válida ou sem data são ignoradas. Se [onlyState] for informado,
/// feições de outros estados também são descartadas.
List<FireHotspot> parseFeatureCollection(String body, {String? onlyState}) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    throw const InpeException(
      'Os focos de calor chegaram em formato inesperado.',
      kind: InpeErrorKind.format,
    );
  }
  if (decoded is! Map<String, dynamic> || decoded['type'] != 'FeatureCollection') {
    throw const InpeException(
      'Os focos de calor chegaram em formato inesperado.',
      kind: InpeErrorKind.format,
    );
  }
  final features = decoded['features'];
  if (features is! List) return const [];

  final hotspots = <FireHotspot>[];
  for (final feature in features) {
    final hotspot = _parseFeature(feature);
    if (hotspot == null) continue;
    if (onlyState != null && hotspot.state != onlyState) continue;
    hotspots.add(hotspot);
  }
  return hotspots;
}

FireHotspot? _parseFeature(dynamic feature) {
  if (feature is! Map<String, dynamic>) return null;
  final props = feature['properties'];
  if (props is! Map<String, dynamic>) return null;

  final position = _position(feature['geometry'], props);
  if (position == null) return null;

  final detectedAt = DateTime.tryParse(props['data_hora_gmt'] as String? ?? '');
  if (detectedAt == null) return null;

  return FireHotspot(
    lat: position.lat,
    lon: position.lon,
    detectedAt: detectedAt.toUtc(),
    state: (props['estado'] as String?) ?? '',
    municipality: (props['municipio'] as String?) ?? '',
    satellite: (props['satelite'] as String?) ?? '',
    biome: (props['bioma'] as String?) ?? '',
    frp: (props['frp'] as num?)?.toDouble(),
    daysWithoutRain: (props['numero_dias_sem_chuva'] as num?)?.toInt(),
    fireRisk: (props['risco_fogo'] as num?)?.toDouble(),
  );
}

({double lat, double lon})? _position(dynamic geometry, Map<String, dynamic> props) {
  if (geometry is Map<String, dynamic> && geometry['type'] == 'Point') {
    final coords = geometry['coordinates'];
    // GeoJSON usa [longitude, latitude].
    if (coords is List && coords.length >= 2) {
      final lon = (coords[0] as num?)?.toDouble();
      final lat = (coords[1] as num?)?.toDouble();
      if (lon != null && lat != null) return (lat: lat, lon: lon);
    }
  }
  final lon = (props['longitude'] as num?)?.toDouble();
  final lat = (props['latitude'] as num?)?.toDouble();
  if (lon != null && lat != null) return (lat: lat, lon: lon);
  return null;
}
