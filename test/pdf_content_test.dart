import 'package:alerta_fumaca_am/data/guidance_content.dart';
import 'package:alerta_fumaca_am/data/pdf_content.dart';
import 'package:alerta_fumaca_am/data/references.dart';
import 'package:alerta_fumaca_am/services/air_quality_service.dart';
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
