import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/air_alert.dart';
import 'api_client.dart';

/// Guarda, neste aparelho, a configuração dos alertas e o último aviso enviado.
class AirAlertStore {
  static const _settingsKey = 'air_alert_settings_v1';
  static const _stateKey = 'air_alert_state_v1';

  Future<AirAlertSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_settingsKey);
      if (raw == null) return const AirAlertSettings();
      return AirAlertSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AirAlertSettings();
    }
  }

  Future<void> saveSettings(AirAlertSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<AirAlertState> loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_stateKey);
      if (raw == null) return const AirAlertState();
      return AirAlertState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AirAlertState();
    }
  }

  Future<void> saveState(AirAlertState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(state.toJson()));
  }

  static const _fireStateKey = 'fire_alert_state_v1';

  Future<FireAlertState> loadFireState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_fireStateKey);
      if (raw == null) return const FireAlertState();
      return FireAlertState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const FireAlertState();
    }
  }

  Future<void> saveFireState(FireAlertState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fireStateKey, jsonEncode(state.toJson()));
  }
}

/// Notificações locais do Android (o app não usa Firebase nem envia dados a terceiros).
class AirAlertNotifier {
  AirAlertNotifier._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channelId = 'qualidade_do_ar';
  static const _channelName = 'Qualidade do ar';
  static const airNotificationId = 4101;
  static const fireNotificationId = 4102;

  /// Pode ser chamado várias vezes (também no processo de segundo plano).
  static Future<void> init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    _ready = true;
  }

  /// Pede a permissão de notificações (Android 13+). `true` se concedida.
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  static Future<bool> permissionGranted() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  static Future<void> show({required int id, required String title, required String body}) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Avisos de qualidade do ar e de focos de calor perto do município escolhido.',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      ),
    );
    await _plugin.show(id: id, title: title, body: body, notificationDetails: details);
  }
}

/// Resultado de uma checagem (usado pela tela para explicar o que aconteceu).
class AirCheckResult {
  const AirCheckResult({this.reading, required this.action, this.error});

  final AirAlertReading? reading;
  final AlertAction action;
  final String? error;
}

class FireCheckResult {
  const FireCheckResult({this.reading, required this.action, this.error});

  final FireAlertReading? reading;
  final AlertAction action;
  final String? error;
}

/// Consulta o servidor, decide e, se for o caso, notifica. Nunca lança.
class AirAlertService {
  AirAlertService({ApiClient? api, AirAlertStore? store})
      : _api = api ?? ApiClient(timeout: const Duration(seconds: 15)),
        _store = store ?? AirAlertStore();

  final ApiClient _api;
  final AirAlertStore _store;

  static const _notConnected = 'O app não está conectado ao servidor do projeto.';

  /// Roda as checagens que estão ligadas (qualidade do ar e/ou focos). Usada em segundo plano.
  Future<void> checkAll({DateTime? now}) async {
    final settings = await _store.loadSettings();
    if (settings.enabled) await check(now: now);
    if (settings.fireEnabled) await checkFire(now: now);
  }

  Future<AirCheckResult> check({DateTime? now, bool force = false}) async {
    try {
      final settings = await _store.loadSettings();
      if (!settings.enabled && !force) return const AirCheckResult(action: AlertAction.none);
      if (!_api.isConfigured) return const AirCheckResult(action: AlertAction.none, error: _notConnected);
      final reading = await _api.fetchAirReading(settings.municipalityCode);
      final state = await _store.loadState();
      final when = now ?? DateTime.now().toUtc();
      final action = decideAlert(
        settings: settings.copyWith(enabled: true),
        reading: reading,
        state: state,
        now: when,
      );
      if (action == AlertAction.notify && settings.enabled) {
        final message = alertMessage(reading);
        await AirAlertNotifier.show(id: AirAlertNotifier.airNotificationId, title: message.title, body: message.body);
        final category = reading.usAqi == null ? null : airCategoryIndex(reading.usAqi!);
        await _store.saveState(AirAlertState(lastCategoryIndex: category, lastNotifiedAt: when));
      } else if (action == AlertAction.reset) {
        await _store.saveState(const AirAlertState());
      }
      return AirCheckResult(reading: reading, action: settings.enabled ? action : AlertAction.none);
    } on ApiException catch (e) {
      return AirCheckResult(action: AlertAction.none, error: e.message);
    } catch (_) {
      return const AirCheckResult(action: AlertAction.none, error: 'Não foi possível verificar agora.');
    }
  }

  Future<FireCheckResult> checkFire({DateTime? now, bool force = false}) async {
    try {
      final settings = await _store.loadSettings();
      if (!settings.fireEnabled && !force) return const FireCheckResult(action: AlertAction.none);
      if (!_api.isConfigured) return const FireCheckResult(action: AlertAction.none, error: _notConnected);
      final reading = await _api.fetchFireReading(settings.municipalityCode, settings.fireRadiusKm);
      final state = await _store.loadFireState();
      final when = now ?? DateTime.now().toUtc();
      final action = decideFireAlert(
        settings: settings.copyWith(fireEnabled: true),
        reading: reading,
        state: state,
        now: when,
      );
      if (action == AlertAction.notify && settings.fireEnabled) {
        final message = fireMessage(reading);
        await AirAlertNotifier.show(id: AirAlertNotifier.fireNotificationId, title: message.title, body: message.body);
        await _store.saveFireState(FireAlertState(lastCount: reading.count24h, lastNotifiedAt: when));
      } else if (action == AlertAction.reset) {
        await _store.saveFireState(const FireAlertState());
      }
      return FireCheckResult(reading: reading, action: settings.fireEnabled ? action : AlertAction.none);
    } on ApiException catch (e) {
      return FireCheckResult(action: AlertAction.none, error: e.message);
    } catch (_) {
      return const FireCheckResult(action: AlertAction.none, error: 'Não foi possível verificar agora.');
    }
  }
}
