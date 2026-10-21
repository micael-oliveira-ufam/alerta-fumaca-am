import 'package:respirar_amazonas/data/lgpd_terms.dart';
import 'package:respirar_amazonas/screens/lgpd_screen.dart';
import 'package:respirar_amazonas/services/report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('aceite é por versão: outra versão exige novo aceite', () async {
    final store = ConsentStore();
    expect(await store.hasAcceptedTerms(kLgpdTermsVersion), isFalse);
    await store.acceptTerms(kLgpdTermsVersion);
    expect(await store.hasAcceptedTerms(kLgpdTermsVersion), isTrue);
    expect(await store.hasAcceptedTerms('999'), isFalse);
  });

  test('aceitar o termo NÃO autoriza envio nem localização', () async {
    final store = ConsentStore();
    await store.acceptTerms(kLgpdTermsVersion);
    expect(await store.sendDecision(), isNull);
    expect(await store.includeLocationInSend(), isFalse);
    expect(await store.hasConsent(), isFalse);
  });

  test('o termo declara os pontos essenciais', () {
    final text = kLgpdSections.expand((s) => [s.title, ...s.paragraphs]).join('\n');
    for (final needle in ['art. 11', 'sensível', 'não podem ser localizados', 'opcional', '3 respostas']) {
      expect(text, contains(needle));
    }
  });

  testWidgets('botão só habilita após marcar a caixa e chama o aceite', (tester) async {
    BuildContext? received;
    await tester.pumpWidget(MaterialApp(home: LgpdScreen(onAccepted: (c) => received = c)));
    FilledButton button() => tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(button().onPressed, isNotNull);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(received, isNotNull);
    expect(await ConsentStore().hasAcceptedTerms(kLgpdTermsVersion), isTrue);
  });

  testWidgets('modo leitura não mostra aceite', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LgpdScreen(onlyRead: true)));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
  });
}
