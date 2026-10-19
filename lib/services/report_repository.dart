import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/answer_record.dart';
import '../models/smoke_report.dart';

/// Abstração para o armazenamento de registros do mapa da comunidade.
///
/// A implementação [LocalReportRepository] guarda os dados apenas neste aparelho.
/// Com o servidor configurado (`API_BASE_URL`), o mapa coletivo vem de `GET /mapa`.
abstract class ReportRepository {
  Future<void> save(SmokeReport report);
  Future<List<SmokeReport>> recent({required Duration window});
}

class LocalReportRepository implements ReportRepository {
  static const _key = 'reports_v1';

  @override
  Future<void> save(SmokeReport report) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.add(jsonEncode(report.toJson()));
    await prefs.setStringList(_key, list);
  }

  @override
  Future<List<SmokeReport>> recent({required Duration window}) async {
    final prefs = await SharedPreferences.getInstance();
    final cutoff = DateTime.now().toUtc().subtract(window);
    final raw = prefs.getStringList(_key) ?? <String>[];
    return raw
        .map((s) => SmokeReport.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .where((r) => r.timestamp.isAfter(cutoff))
        .toList();
  }
}

/// Respostas completas do questionário, guardadas só neste aparelho (sem localização),
/// para as estatísticas locais dos sintomas.
class LocalAnswerStore {
  static const _key = 'answers_v1';

  /// Limite para o armazenamento não crescer sem controle.
  static const maxEntries = 500;

  Future<void> save(AnswerRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.add(jsonEncode(record.toJson()));
    final trimmed = list.length > maxEntries ? list.sublist(list.length - maxEntries) : list;
    await prefs.setStringList(_key, trimmed);
  }

  Future<List<AnswerRecord>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    final records = <AnswerRecord>[];
    for (final s in raw) {
      try {
        records.add(AnswerRecord.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // Registro corrompido: ignora e segue com os demais.
      }
    }
    return records;
  }
}

/// Registro dos consentimentos (LGPD). Cada finalidade tem sua própria chave.
class ConsentStore {
  /// Uso da localização para o mapa da comunidade neste aparelho.
  static const _locationKey = 'consent_localizacao_v1';

  /// Envio das respostas (dados de saúde) ao servidor. Ausente = nunca perguntado.
  static const _sendKey = 'consent_envio_v1';

  /// Incluir a localização aproximada (~1 km) nos envios ao servidor.
  static const _sendLocationKey = 'consent_envio_local_v1';

  /// Versão do termo de privacidade (LGPD) que a pessoa leu e aceitou.
  static const _termsKey = 'lgpd_termos_versao';

  /// Aceitar o termo só confirma a leitura; NÃO autoriza envio (isso é [_sendKey]).
  Future<bool> hasAcceptedTerms(String version) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_termsKey) == version;
  }

  Future<void> acceptTerms(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_termsKey, version);
  }

  Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_locationKey) ?? false;
  }

  Future<void> setConsent(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_locationKey, value);
  }

  /// `null` = o usuário ainda não decidiu; `true`/`false` = decisão tomada.
  Future<bool?> sendDecision() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sendKey);
  }

  Future<void> setSendDecision(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sendKey, value);
  }

  Future<bool> includeLocationInSend() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sendLocationKey) ?? false;
  }

  Future<void> setIncludeLocationInSend(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sendLocationKey, value);
  }
}
