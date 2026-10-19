import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Situação final de uma tentativa de obter a localização.
enum LocationStatus {
  ok,

  /// O GPS do aparelho está desligado.
  serviceDisabled,

  /// O usuário negou a permissão nesta vez.
  denied,

  /// O usuário negou a permissão de forma permanente (precisa ir às configurações).
  deniedForever,

  /// O app não declara a permissão de localização no manifesto da plataforma
  /// (AndroidManifest.xml / Info.plist). O sistema nunca chega a perguntar ao usuário.
  permissionNotDeclared,

  /// Não foi possível obter a posição (tempo esgotado ou erro).
  unavailable,
}

class LocationOutcome {
  const LocationOutcome(this.status, [this.position, this.detail]);

  final LocationStatus status;
  final Position? position;

  /// Texto técnico do erro, apenas para diagnóstico.
  final String? detail;
}

/// Obtém a posição do usuário. A permissão é pedida ao sistema operacional;
/// a explicação ao usuário é responsabilidade da tela, que a mostra antes.
class LocationService {
  /// `true` se a permissão já foi concedida (sem abrir nenhum diálogo).
  Future<bool> hasPermission() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  /// Pede a permissão (se necessário) e obtém a posição atual.
  Future<LocationOutcome> requestAndGetPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationOutcome(LocationStatus.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationOutcome(LocationStatus.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const LocationOutcome(LocationStatus.denied);
      }

      final position = await Geolocator.getCurrentPosition(
        // Precisão "média" já basta para centralizar o mapa e economiza bateria.
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationOutcome(LocationStatus.ok, position);
    } on TimeoutException catch (e) {
      return LocationOutcome(LocationStatus.unavailable, null, '$e');
    } catch (e) {
      // O geolocator lança PermissionDefinitionsNotFoundException quando o
      // manifesto não declara ACCESS_FINE/COARSE_LOCATION.
      if ('${e.runtimeType}'.contains('PermissionDefinitionsNotFound')) {
        return LocationOutcome(LocationStatus.permissionNotDeclared, null, '$e');
      }
      return LocationOutcome(LocationStatus.unavailable, null, '$e');
    }
  }

  /// Atalho usado pelo envio de registros: retorna a posição ou `null`.
  Future<Position?> currentPosition() async {
    final outcome = await requestAndGetPosition();
    return outcome.status == LocationStatus.ok ? outcome.position : null;
  }
}
