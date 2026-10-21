import 'package:respirar_amazonas/logic/air_alert.dart';
import 'package:flutter_test/flutter_test.dart';

AirAlertReading reading(int? aqi, {bool stale = false, double? pm25 = 68.9}) => AirAlertReading(
      municipalityName: 'Manaus',
      usAqi: aqi,
      pm25: pm25,
      pm10: 115.4,
      modelTime: null,
      stale: stale,
    );

void main() {
  final now = DateTime.utc(2026, 10, 20, 20);
  const on = AirAlertSettings(enabled: true);

  group('decideAlert', () {
    test('desligado nunca avisa', () {
      expect(
        decideAlert(settings: const AirAlertSettings(), reading: reading(200), state: const AirAlertState(), now: now),
        AlertAction.none,
      );
    });
    test('abaixo do limiar não avisa', () {
      expect(decideAlert(settings: on, reading: reading(100), state: const AirAlertState(), now: now), AlertAction.none);
    });
    test('no limiar avisa pela primeira vez', () {
      expect(decideAlert(settings: on, reading: reading(101), state: const AirAlertState(), now: now), AlertAction.notify);
    });
    test('não repete a mesma categoria dentro de 12 h', () {
      final state = AirAlertState(lastCategoryIndex: 2, lastNotifiedAt: now.subtract(const Duration(hours: 3)));
      expect(decideAlert(settings: on, reading: reading(120), state: state, now: now), AlertAction.none);
    });
    test('categoria pior avisa de novo', () {
      final state = AirAlertState(lastCategoryIndex: 2, lastNotifiedAt: now.subtract(const Duration(hours: 1)));
      expect(decideAlert(settings: on, reading: reading(160), state: state, now: now), AlertAction.notify);
    });
    test('repete depois de 12 h com o índice ainda alto', () {
      final state = AirAlertState(lastCategoryIndex: 2, lastNotifiedAt: now.subtract(const Duration(hours: 13)));
      expect(decideAlert(settings: on, reading: reading(120), state: state, now: now), AlertAction.notify);
    });
    test('voltar abaixo do limiar zera o estado; sem estado, nada', () {
      final state = AirAlertState(lastCategoryIndex: 2, lastNotifiedAt: now);
      expect(decideAlert(settings: on, reading: reading(40), state: state, now: now), AlertAction.reset);
      expect(decideAlert(settings: on, reading: reading(40), state: const AirAlertState(), now: now), AlertAction.none);
    });
    test('dado desatualizado ou sem índice não alarma', () {
      expect(decideAlert(settings: on, reading: reading(200, stale: true), state: const AirAlertState(), now: now), AlertAction.none);
      expect(decideAlert(settings: on, reading: reading(null), state: const AirAlertState(), now: now), AlertAction.none);
    });
  });

  group('configurações', () {
    test('ida e volta', () {
      const s = AirAlertSettings(enabled: true, municipalityCode: 1303403, municipalityName: 'Parintins', threshold: 151);
      final back = AirAlertSettings.fromJson(s.toJson());
      expect(back.municipalityCode, 1303403);
      expect(back.threshold, 151);
      expect(back.enabled, isTrue);
    });
    test('valores inválidos voltam ao padrão', () {
      final s = AirAlertSettings.fromJson({'ativo': 'sim', 'codigo': 5, 'nome': '', 'limiar': 7});
      expect(s.enabled, isFalse);
      expect(s.municipalityCode, kDefaultAlertMunicipalityCode);
      expect(s.municipalityName, 'Manaus');
      expect(s.threshold, kDefaultAlertThreshold);
    });
  });

  test('mensagem diz que é estimativa e cita o município', () {
    final m = alertMessage(reading(151));
    expect(m.title, contains('Manaus'));
    expect(m.title, contains('Ruim'));
    expect(m.body, contains('Estimativa de modelo'));
    expect(m.body, contains('68,9'));
  });

  group('decideFireAlert', () {
    FireAlertReading fire(int n, {bool stale = false, double? nearest = 12.3, DateTime? last}) => FireAlertReading(
          municipalityName: 'Manaus',
          radiusKm: 50,
          count24h: n,
          count48h: n + 2,
          nearestKm: nearest,
          lastDetectionUtc: last,
          stale: stale,
        );
    const fireOn = AirAlertSettings(fireEnabled: true);

    test('desligado ou desatualizado não avisa', () {
      expect(decideFireAlert(settings: const AirAlertSettings(), reading: fire(9), state: const FireAlertState(), now: now), AlertAction.none);
      expect(decideFireAlert(settings: fireOn, reading: fire(9, stale: true), state: const FireAlertState(), now: now), AlertAction.none);
    });
    test('primeira detecção avisa; zero focos não avisa e zera o estado', () {
      expect(decideFireAlert(settings: fireOn, reading: fire(1), state: const FireAlertState(), now: now), AlertAction.notify);
      expect(decideFireAlert(settings: fireOn, reading: fire(0), state: const FireAlertState(), now: now), AlertAction.none);
      final st = FireAlertState(lastCount: 3, lastNotifiedAt: now);
      expect(decideFireAlert(settings: fireOn, reading: fire(0), state: st, now: now), AlertAction.reset);
    });
    test('só repete com crescimento forte ou depois de 24 h', () {
      final st = FireAlertState(lastCount: 4, lastNotifiedAt: now.subtract(const Duration(hours: 2)));
      expect(decideFireAlert(settings: fireOn, reading: fire(6), state: st, now: now), AlertAction.none); // +2
      expect(decideFireAlert(settings: fireOn, reading: fire(9), state: st, now: now), AlertAction.notify); // +5 e >=150%
      final velho = FireAlertState(lastCount: 4, lastNotifiedAt: now.subtract(const Duration(hours: 25)));
      expect(decideFireAlert(settings: fireOn, reading: fire(4), state: velho, now: now), AlertAction.notify);
    });
    test('mensagem: horário de Manaus e ressalva de que não é incêndio confirmado', () {
      final m = fireMessage(fire(7, last: DateTime.utc(2026, 10, 20, 19, 40)));
      expect(m.title, contains('Manaus'));
      expect(m.body, contains('7 focos de calor'));
      expect(m.body, contains('15:40'));
      expect(m.body, contains('12,3 km'));
      expect(m.body, contains('não incêndios confirmados'));
      expect(fireMessage(fire(1)).body, contains('1 foco de calor'));
    });
    test('configurações de focos: ida e volta e valores inválidos', () {
      const s = AirAlertSettings(fireEnabled: true, fireRadiusKm: 25);
      final back = AirAlertSettings.fromJson(s.toJson());
      expect(back.fireEnabled, isTrue);
      expect(back.fireRadiusKm, 25);
      expect(AirAlertSettings.fromJson({'foco_raio': 7}).fireRadiusKm, kDefaultFireRadius);
      expect(const AirAlertSettings(fireEnabled: true).anyEnabled, isTrue);
      expect(const AirAlertSettings().anyEnabled, isFalse);
    });
  });
}
