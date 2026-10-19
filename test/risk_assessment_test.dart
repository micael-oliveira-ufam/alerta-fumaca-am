import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_fumaca_am/logic/risk_assessment.dart';

Map<String, int> none() => {for (final i in symptomItems) i.id: 0};

void main() {
  test('sem sintomas, exposição baixa e sem perfil vulnerável => baixo, 0 pontos', () {
    final r = assess(
      severities: none(),
      exposure: Exposure.under1h,
      profile: const Profile(),
    );
    expect(r.level, RiskLevel.low);
    expect(r.points, 0);
    expect(r.consequences, isEmpty);
  });

  test('dor no peito intensa => emergência, independentemente da soma', () {
    final s = none()..['chest'] = 3;
    final r = assess(
      severities: s,
      exposure: Exposure.under1h,
      profile: const Profile(),
    );
    expect(r.level, RiskLevel.emergency);
  });

  test('falta de ar moderada com doença respiratória crônica => emergência', () {
    final s = none()..['dyspnea'] = 2;
    final r = assess(
      severities: s,
      exposure: Exposure.under1h,
      profile: const Profile(chronicRespiratory: true),
    );
    expect(r.level, RiskLevel.emergency);
  });

  test('falta de ar moderada SEM doença crônica não dispara emergência automática', () {
    final s = none()..['dyspnea'] = 2;
    final r = assess(
      severities: s,
      exposure: Exposure.under1h,
      profile: const Profile(),
    );
    expect(r.level, isNot(RiskLevel.emergency));
  });

  test('grupo vulnerável adiciona exatamente vulnerablePoints', () {
    final base = assess(
      severities: none(),
      exposure: Exposure.between1and4h,
      profile: const Profile(),
    );
    final vuln = assess(
      severities: none(),
      exposure: Exposure.between1and4h,
      profile: const Profile(elderly: true),
    );
    expect(vuln.points - base.points, vulnerablePoints);
  });

  test('soma moderada resulta em risco moderado', () {
    // cough 3 + throat 3 + wheeze 2 = 8; exposição 1–4h = 2; total = 10
    final s = none()
      ..['cough'] = 3
      ..['throat'] = 3
      ..['wheeze'] = 2;
    final r = assess(
      severities: s,
      exposure: Exposure.between1and4h,
      profile: const Profile(),
    );
    expect(r.points, 10);
    expect(r.level, RiskLevel.moderate);
    expect(r.consequences, contains(Consequence.respiratory));
  });

  test('soma alta resulta em risco alto', () {
    // eyes 3 + cough 3 + throat 3 + headache 3 + fatigue 3 = 15; exposição >4h = 4; total = 19
    final s = none()
      ..['eyes'] = 3
      ..['cough'] = 3
      ..['throat'] = 3
      ..['headache'] = 3
      ..['fatigue'] = 3;
    final r = assess(
      severities: s,
      exposure: Exposure.over4h,
      profile: const Profile(),
    );
    expect(r.points, 19);
    expect(r.level, RiskLevel.high);
  });

  test('severidade fora de 0–3 é rejeitada', () {
    final s = none()..['cough'] = 4;
    expect(
      () => assess(
        severities: s,
        exposure: Exposure.under1h,
        profile: const Profile(),
      ),
      throwsArgumentError,
    );
  });
}
