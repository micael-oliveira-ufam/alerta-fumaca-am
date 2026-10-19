import 'package:alerta_fumaca_am/logic/risk_assessment.dart';
import 'package:alerta_fumaca_am/logic/symptom_stats.dart';
import 'package:alerta_fumaca_am/models/answer_record.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 19, 12);

AnswerRecord _r(
  Map<String, int> severities, {
  RiskLevel level = RiskLevel.moderate,
  DateTime? at,
}) =>
    AnswerRecord(
      timestamp: at ?? _now.subtract(const Duration(hours: 1)),
      severities: severities,
      level: level,
      points: 5,
    );

void main() {
  // Mesmo cenário do teste do servidor (server/tests/test_estatisticas.py): os dois
  // cálculos devem produzir exatamente os mesmos números.
  final records = [
    _r({'cough': 3, 'headache': 2}),
    _r({'cough': 2, 'headache': 1}),
    _r({'cough': 2}),
    _r({'cough': 1}),
    _r({'cough': 1}),
    _r({'cough': 0, 'eyes': 0}),
  ];

  group('estatísticas locais', () {
    final stats = computeLocalStats(records, now: _now);
    SymptomStat byId(String id) => stats.symptoms.firstWhere((s) => s.id == id);

    test('totais e origem', () {
      expect(stats.source, StatsSource.local);
      expect(stats.totalResponses, 6);
      expect(stats.sufficient, isTrue);
    });

    test('tosse: 5 relatos, 83,3 %, distribuição e gravidade média', () {
      final cough = byId('cough');
      expect(cough.reports, 5);
      expect(cough.percent, 83.3);
      expect((cough.mild, cough.moderate, cough.intense), (2, 2, 1));
      expect(cough.meanSeverity, 1.8);
    });

    test('dor de cabeça: 2 relatos, 33,3 %, média 1,5', () {
      final headache = byId('headache');
      expect(headache.reports, 2);
      expect(headache.percent, 33.3);
      expect(headache.meanSeverity, 1.5);
    });

    test('sintoma só com gravidade 0 aparece, mas sem média', () {
      final eyes = byId('eyes');
      expect(eyes.reports, 0);
      expect(eyes.meanSeverity, isNull);
    });

    test('ordenado do mais para o menos relatado', () {
      final ids = stats.symptoms.map((s) => s.id).toList();
      expect(ids.indexOf('cough'), lessThan(ids.indexOf('headache')));
      expect(ids.indexOf('headache'), lessThan(ids.indexOf('eyes')));
    });
  });

  group('período e níveis', () {
    test('respostas fora da janela não entram', () {
      final old = _r({'cough': 3}, at: _now.subtract(const Duration(days: 40)));
      final stats = computeLocalStats([...records, old], days: 30, now: _now);
      expect(stats.totalResponses, 6);
      expect(computeLocalStats([...records, old], days: 90, now: _now).totalResponses, 7);
    });

    test('distribuição por nível de risco', () {
      final stats = computeLocalStats([
        _r({'cough': 1}, level: RiskLevel.low),
        _r({'cough': 1}, level: RiskLevel.low),
        _r({'cough': 1}, level: RiskLevel.emergency),
      ], now: _now);
      expect(stats.levels['low'], 2);
      expect(stats.levels['emergency'], 1);
      expect(stats.levels['high'], 0);
    });

    test('sem respostas: insuficiente, sem divisão por zero', () {
      final stats = computeLocalStats(const [], now: _now);
      expect(stats.totalResponses, 0);
      expect(stats.sufficient, isFalse);
      expect(stats.symptoms, isEmpty);
    });
  });

  group('resposta do servidor', () {
    // Mesmo formato que o FastAPI devolve em GET /estatisticas.
    final json = <String, dynamic>{
      'periodo_dias': 30,
      'total_respostas': 6,
      'suficiente': true,
      'minimo_para_divulgar': 5,
      'niveis': {'low': 0, 'moderate': 1, 'high': 5, 'emergency': 0},
      'sintomas': [
        {
          'sintoma': 'cough',
          'relatos': 6,
          'percentual': 100.0,
          'leve': 0,
          'moderado': 1,
          'intenso': 5,
          'gravidade_media': 2.83,
        },
        {
          'sintoma': 'dyspnea',
          'relatos': 0,
          'percentual': 0.0,
          'leve': 0,
          'moderado': 0,
          'intenso': 0,
          'gravidade_media': null,
        },
      ],
      'serie': [],
    };

    test('interpreta todos os campos', () {
      final stats = StatsSnapshot.fromServerJson(json);
      expect(stats.source, StatsSource.server);
      expect(stats.totalResponses, 6);
      expect(stats.levels['high'], 5);
      expect(stats.symptoms.first.id, 'cough');
      expect(stats.symptoms.first.meanSeverity, 2.83);
      expect(stats.symptoms.last.meanSeverity, isNull);
    });

    test('estatística insuficiente do servidor mantém o aviso de privacidade', () {
      final stats = StatsSnapshot.fromServerJson({
        'periodo_dias': 30,
        'total_respostas': 2,
        'suficiente': false,
        'minimo_para_divulgar': 5,
        'niveis': {'low': 0, 'moderate': 0, 'high': 0, 'emergency': 0},
        'sintomas': [],
        'serie': [],
      });
      expect(stats.sufficient, isFalse);
      expect(stats.minimumToDisclose, 5);
      expect(stats.symptoms, isEmpty);
    });
  });
}
