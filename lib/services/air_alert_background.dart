import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'air_alert_service.dart';
import 'api_config.dart';

const _taskName = 'respirar.qualidade_do_ar';

/// Ponto de entrada do processo de segundo plano (o Android o acorda de tempos em tempos).
@pragma('vm:entry-point')
void airAlertCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      await ApiConfig.load();
      await AirAlertService().check();
    } catch (_) {
      // Falhou: a próxima janela tenta de novo. Não pede reexecução imediata (poupa bateria).
    }
    return true;
  });
}

/// Liga ou desliga a checagem periódica em segundo plano (só Android).
///
/// LIMITES CONHECIDOS: o Android decide quando executar (mínimo de 15 min; aqui pedimos 1 h, já que o
/// modelo atualiza a cada hora) e a economia de bateria do fabricante pode adiar ou impedir a
/// execução. Por isso o app também confere ao ser aberto.
class AirAlertBackground {
  const AirAlertBackground._();

  static Future<void> sync({required bool enabled}) async {
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().initialize(airAlertCallbackDispatcher);
      if (enabled) {
        await Workmanager().registerPeriodicTask(
          _taskName,
          _taskName,
          frequency: const Duration(hours: 1),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        );
      } else {
        await Workmanager().cancelByUniqueName(_taskName);
      }
    } catch (_) {
      // Sem segundo plano o alerta continua funcionando ao abrir o app.
    }
  }
}
