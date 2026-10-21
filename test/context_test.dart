import 'package:respirar_amazonas/data/pdf_content.dart' show extraReferences;
import 'package:respirar_amazonas/data/references.dart';
import 'package:respirar_amazonas/logic/context_advice.dart';
import 'package:respirar_amazonas/logic/risk_assessment.dart';
import 'package:respirar_amazonas/models/smoke_context.dart';
import 'package:respirar_amazonas/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payload({SmokeContext? context}) => buildAnswerPayload(
      submissionId: '11111111-1111-4111-8111-111111111111',
      recordedAt: DateTime.utc(2026, 10, 19, 22),
      result: const RiskResult(level: RiskLevel.low, points: 1, consequences: {}),
      exposure: Exposure.under1h,
      profile: const Profile(),
      severities: {'cough': 1},
      context: context,
    );

void main() {
  group('SmokeContext', () {
    test('vazio não gera campo "contexto" no envio', () {
      expect(const SmokeContext().isEmpty, isTrue);
      expect(_payload().containsKey('contexto'), isFalse);
      expect(_payload(context: const SmokeContext()).containsKey('contexto'), isFalse);
    });

    test('só envia o que foi respondido, com os nomes que a API valida', () {
      final p = _payload(
        context: const SmokeContext(
          place: Place.homeOpen,
          visibleSmoke: true,
          mask: MaskUse.respirator,
          worsening: false,
        ),
      );
      expect(p['contexto'], {
        'local': 'casa_janelas_abertas',
        'fumaca_visivel': true,
        'mascara': 'pff2_n95',
        'piorando': false,
      });
    });

    test('todos os valores de enum correspondem aos aceitos pelo servidor', () {
      expect(Place.values.map((e) => e.wire), ['ar_livre', 'casa_janelas_abertas', 'casa_janelas_fechadas']);
      expect(MaskUse.values.map((e) => e.wire), ['nao_saiu', 'nao', 'cirurgica_pano', 'pff2_n95']);
    });

    test('os 10 campos do contexto existem no payload completo', () {
      const full = SmokeContext(
        place: Place.outdoors,
        visibleSmoke: true,
        mask: MaskUse.none,
        outdoorExercise: true,
        cleanAir: false,
        outdoorWork: true,
        immune: false,
        medsAtHand: true,
        medsNotWorking: false,
        worsening: true,
      );
      expect(full.toPayload().keys.toSet(), {
        'local',
        'fumaca_visivel',
        'mascara',
        'atividade_fisica_ar_livre',
        'ar_filtrado',
        'trabalho_ar_livre',
        'imunologica',
        'medicacao_a_mao',
        'medicacao_nao_alivia',
        'piorando',
      });
    });
  });

  group('cuidados por contexto', () {
    test('medicação que não alivia gera alerta urgente', () {
      final tips = contextTips(const SmokeContext(medsNotWorking: true), const Profile());
      expect(tips.first.urgent, isTrue);
    });

    test('janelas abertas: orienta fechar', () {
      final tips = contextTips(const SmokeContext(place: Place.homeOpen), const Profile());
      expect(tips.single.text, contains('Feche janelas'));
    });

    test('máscara cirúrgica na fumaça cita a EPA', () {
      final tips = contextTips(
        const SmokeContext(mask: MaskUse.surgicalOrCloth, visibleSmoke: true),
        const Profile(),
      );
      expect(tips.any((t) => t.refs.contains(2)), isTrue);
    });

    test('sem respostas: nenhum cuidado extra', () {
      expect(contextTips(const SmokeContext(), const Profile()), isEmpty);
    });

    test('medicação à mão só importa para quem tem doença crônica', () {
      const ctx = SmokeContext(medsAtHand: false);
      expect(contextTips(ctx, const Profile()), isEmpty);
      expect(contextTips(ctx, const Profile(chronicRespiratory: true)), hasLength(1));
    });

    test('contexto não altera a classificação de risco', () {
      final r = assess(
        severities: {'cough': 1},
        exposure: Exposure.under1h,
        profile: const Profile(),
      );
      // assess() não recebe o contexto: o mesmo resultado independe das respostas extras.
      expect(r.level, RiskLevel.low);
    });
  });

  group('referências', () {
    test('toda pergunta cita referências existentes', () {
      // As perguntas citam as fontes numeradas de `references` e as de `extraReferences` (de 4 em diante).
      final ids = {...references.map((r) => r.id), ...extraReferences.map((r) => r.id)};
      for (final q in questionSources) {
        for (final id in q.refs) {
          expect(ids, contains(id), reason: q.question);
        }
        if (q.refs.isEmpty) {
          expect(q.projectOnly, isTrue, reason: '${q.question}: sem fonte deve ser marcada do projeto');
        }
      }
    });

    test('a nota do Ministério da Saúde declara que o texto original não foi lido', () {
      final ms = references.firstWhere((r) => r.id == 3);
      expect(ms.caveat, contains('NÃO consultei'));
    });
  });
}
