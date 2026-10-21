import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Últimos números recebidos do servidor, guardados neste aparelho.
///
/// Serve para a tela de estatísticas mostrar algo útil quando o servidor ou o banco estiverem
/// fora do ar. São os mesmos dados agregados e públicos que o servidor já devolveu; nada novo.
class CachedStats {
  const CachedStats({required this.stats, required this.neighborhoods, required this.savedAt, required this.days});

  final Map<String, dynamic> stats;
  final Map<String, dynamic>? neighborhoods;
  final DateTime savedAt;
  final int days;
}

class StatsCache {
  static const _key = 'stats_cache_v1';

  Future<void> save({
    required int days,
    required Map<String, dynamic> stats,
    Map<String, dynamic>? neighborhoods,
    DateTime? now,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'dias': days,
          'salvo_em': (now ?? DateTime.now()).toUtc().toIso8601String(),
          'estatisticas': stats,
          'bairros': neighborhoods,
        }),
      );
    } catch (_) {
      // guardar é um favor: falhar aqui não pode atrapalhar a tela
    }
  }

  /// `null` se não houver cópia ou se ela estiver ilegível.
  Future<CachedStats?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      return parseCached(raw);
    } catch (_) {
      return null;
    }
  }

  /// Interpreta o texto guardado. Pública para teste.
  static CachedStats? parseCached(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(m['salvo_em'] as String);
      return CachedStats(
        stats: Map<String, dynamic>.from(m['estatisticas'] as Map),
        neighborhoods: m['bairros'] == null ? null : Map<String, dynamic>.from(m['bairros'] as Map),
        savedAt: savedAt,
        days: (m['dias'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}
