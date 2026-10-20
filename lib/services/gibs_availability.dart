import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../logic/map_layers.dart';

/// Descobre em quais datas a NASA GIBS tem imagem de uma camada.
///
/// Método: para cada data recente, pede UM tile de referência (zoom 3, sobre Manaus) e
/// considera a data disponível se o servidor responder 200 com conteúdo. Não há lista fixa
/// de datas: a disponibilidade vem da própria resposta do serviço.
///
/// LIMITE: o comportamento real do serviço (códigos de resposta para datas sem imagem)
/// não pôde ser conferido no ambiente de desenvolvimento. Se o servidor devolver 200 com um
/// tile em branco para uma data sem dado, essa data aparecerá como disponível; o aviso de
/// tile com falha do mapa continua valendo como segunda proteção.
class GibsAvailability {
  GibsAvailability({http.Client? client, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _now;
  final Map<String, bool> _cache = {};

  /// Quantos dias para trás (a partir de hoje, UTC) são testados.
  static const lookbackDays = 10;

  /// Cidade de referência do tile de teste (Manaus).
  static const refLat = -3.12;
  static const refLon = -60.02;
  static const refZoom = 3;

  /// Índices (x, y) do tile Web Mercator que contém [lat]/[lon] no zoom [z].
  static ({int x, int y}) tileOf(double lat, double lon, int z) {
    final n = math.pow(2, z).toDouble();
    final x = ((lon + 180) / 360 * n).floor();
    final r = lat * math.pi / 180;
    final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor();
    return (x: x, y: y);
  }

  /// URL do tile de teste da camada [layer] na data [date] (AAAA-MM-DD).
  static Uri probeUri(GibsLayer layer, String date) {
    final t = tileOf(refLat, refLon, refZoom);
    final url = layer.urlTemplate(date)
        .replaceFirst('{z}', '$refZoom')
        .replaceFirst('{y}', '${t.y}')
        .replaceFirst('{x}', '${t.x}');
    return Uri.parse(url);
  }

  Future<bool> _has(GibsLayer layer, String date) async {
    final key = '${layer.id}|$date';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final r = await _client.get(probeUri(layer, date)).timeout(const Duration(seconds: 12));
      final ok = r.statusCode == 200 && r.bodyBytes.isNotEmpty;
      _cache[key] = ok;
      return ok;
    } catch (_) {
      return false; // falha de rede não é gravada: pode funcionar na próxima tentativa
    }
  }

  /// Dias para trás (0 = hoje UTC) em que TODAS as [layers] têm imagem, do mais recente
  /// ao mais antigo.
  Future<List<int>> availableDaysBack(Iterable<GibsLayer> layers) async {
    final list = layers.toList();
    final now = _now().toUtc();
    final days = List<int>.generate(lookbackDays + 1, (i) => i);
    final results = await Future.wait(days.map((d) async {
      final date = gibsDate(now, daysBack: d);
      for (final l in list) {
        if (!await _has(l, date)) return null;
      }
      return d;
    }));
    return results.whereType<int>().toList();
  }
}
