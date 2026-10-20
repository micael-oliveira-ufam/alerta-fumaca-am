import 'package:respirar_amazonas/data/guidance_content.dart';
import 'package:respirar_amazonas/data/pdf_content.dart';
import 'package:respirar_amazonas/data/references.dart';
import 'package:respirar_amazonas/services/air_quality_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final allCards = [...protectionCards, ...symptomExplainers, ...homeCareCards, ...petCards];

  test('todo cartão não conferido traz nota explicando o limite da verificação', () {
    for (final c in allCards) {
      if (c.verification != Verification.checked) {
        expect(c.verificationNote, isNotNull, reason: c.title);
        expect(c.verificationNote!.trim(), isNotEmpty, reason: c.title);
      }
    }
  });

  test('referências citadas nos cartões existem e os números não se repetem', () {
    final ids = [...references.map((r) => r.id), ...extraReferences.map((r) => r.id)];
    expect(ids.toSet().length, ids.length);
    for (final c in allCards) {
      for (final r in c.refs) {
        expect(ids, contains(r), reason: c.title);
      }
    }
  });

  test('todo cartão de saúde e todo mito traz ao menos uma referência', () {
    for (final c in allCards) {
      expect(c.refs, isNotEmpty, reason: c.title);
    }
    for (final m in myths) {
      expect(m.refs, isNotEmpty, reason: m.claim);
    }
  });

  test('toda referência extra traz o texto interno de verificação e nome curto', () {
    for (final r in extraReferences) {
      expect(r.status.trim(), isNotEmpty, reason: '${r.id}');
      expect(referenceShort[r.id], isNotNull, reason: '${r.id}');
    }
  });

  test('o telefone local do CIT é o confirmado (3305-4702), não o 4700', () {
    expect(kCitHugvPhoneAlt, '(92) 3305-4702');
    expect(kCitHugvPhoneAltDial, '9233054702');
  });

  test('alerta roxo começa onde a faixa "muito ruim" começa', () {
    expect(airCategoryOf(alertPurpleMinAqi), AirCategory.veryUnhealthy);
    expect(airCategoryOf(alertPurpleMinAqi - 1), AirCategory.unhealthy);
  });

  test('telefones de discagem correspondem aos exibidos', () {
    expect(kCitPhoneDisplay.replaceAll(' ', ''), kCitPhoneDial);
    expect(kCitHugvPhoneAlt.replaceAll(RegExp(r'[^0-9]'), ''), kCitHugvPhoneAltDial);
  });

  test('"quando ligar" manda ligar primeiro ao SAMU em confusão/desmaio', () {
    final first = citWhenToCall.first;
    expect(first, contains('confusão'));
    expect(first, contains(kSamuNumber));
  });

  test('os três mitos do documento são marcados como mito', () {
    expect(myths, hasLength(3));
    expect(myths.every((m) => !m.verdict), isTrue);
  });

  test('o aviso offline não promete mapas ou envio sem internet', () {
    expect(offlineNotice, contains('precisam de internet'));
  });
}
