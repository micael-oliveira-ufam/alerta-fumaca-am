import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Resultado de uma tentativa de envio.
enum SyncResult {
  /// O servidor não está configurado: nada é enviado (modo local).
  notConfigured,

  /// Entregue ao servidor.
  sent,

  /// Sem conexão ou servidor indisponível: guardado para nova tentativa.
  queued,

  /// O servidor recusou o conteúdo: não será reenviado.
  rejected,
}

/// Envia respostas ao servidor e mantém uma fila de reenvio local.
///
/// Se a rede falhar, o envio fica na fila (neste aparelho) e é tentado de novo no
/// próximo envio ou ao abrir as estatísticas. O reenvio é seguro: o `submission_id`
/// faz o servidor ignorar duplicatas.
class AnswerSync {
  AnswerSync({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  static const _key = 'pending_answers_v1';
  static const maxQueue = 200;

  bool get isConfigured => _api.isConfigured;

  Future<SyncResult> send(Map<String, dynamic> payload) async {
    if (!_api.isConfigured) return SyncResult.notConfigured;
    await flush(); // entrega primeiro o que ficou pendente
    try {
      await _api.postAnswer(payload);
      return SyncResult.sent;
    } on ApiException catch (e) {
      if (e.permanent) return SyncResult.rejected;
      await _enqueue(payload);
      return SyncResult.queued;
    }
  }

  /// Quantidade de envios aguardando.
  Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const <String>[]).length;
  }

  /// Tenta entregar a fila. Para na primeira falha de rede (evita esperar vários tempos
  /// limite seguidos). Retorna quantos foram entregues.
  Future<int> flush() async {
    if (!_api.isConfigured) return 0;
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_key) ?? <String>[];
    if (pending.isEmpty) return 0;

    var delivered = 0;
    final remaining = <String>[];
    var stop = false;
    for (final raw in pending) {
      if (stop) {
        remaining.add(raw);
        continue;
      }
      try {
        await _api.postAnswer(jsonDecode(raw) as Map<String, dynamic>);
        delivered++;
      } on ApiException catch (e) {
        if (e.permanent) continue; // recusado em definitivo: descarta
        remaining.add(raw);
        stop = true;
      } catch (_) {
        continue; // item ilegível na fila: descarta
      }
    }
    await prefs.setStringList(_key, remaining);
    return delivered;
  }

  Future<void> _enqueue(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.add(jsonEncode(payload));
    final trimmed = list.length > maxQueue ? list.sublist(list.length - maxQueue) : list;
    await prefs.setStringList(_key, trimmed);
  }
}
