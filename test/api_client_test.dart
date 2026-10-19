import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:alerta_fumaca_am/logic/risk_assessment.dart';
import 'package:alerta_fumaca_am/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _payload({double? lat, double? lon}) => buildAnswerPayload(
      submissionId: '11111111-1111-4111-8111-111111111111',
      recordedAt: DateTime.utc(2026, 10, 19, 22),
      result: const RiskResult(level: RiskLevel.high, points: 17, consequences: {}),
      exposure: Exposure.over4h,
      profile: const Profile(pregnant: true, chronicRespiratory: true),
      severities: {'cough': 3, 'dyspnea': 2},
      lat: lat,
      lon: lon,
    );

void main() {
  group('buildAnswerPayload', () {
    test('usa os nomes de campos e valores que a API valida', () {
      final p = _payload();
      expect(p['submission_id'], '11111111-1111-4111-8111-111111111111');
      expect(p['registrado_em'], '2026-10-19T22:00:00.000Z');
      expect(p['nivel'], 'high');
      expect(p['pontos'], 17);
      expect(p['exposicao'], 'over4h');
      expect(p['perfil'], {
        'idoso': false,
        'gestante': true,
        'crianca': false,
        'doenca_respiratoria': true,
        'doenca_cardiaca': false,
      });
    });

    test('envia TODOS os sintomas do questionário, com 0 para os não marcados', () {
      final sintomas = _payload()['sintomas'] as Map<String, dynamic>;
      expect(sintomas.length, symptomItems.length);
      expect(sintomas['cough'], 3);
      expect(sintomas['dyspnea'], 2);
      expect(sintomas['eyes'], 0);
    });

    test('sem localização: não inclui lat/lon', () {
      final p = _payload();
      expect(p.containsKey('lat'), isFalse);
      expect(p.containsKey('lon'), isFalse);
    });

    test('com localização: arredonda a ~1 km antes de enviar', () {
      final p = _payload(lat: -3.119042, lon: -60.021749);
      expect(p['lat'], -3.12);
      expect(p['lon'], -60.02);
    });

    test('não contém campos de identificação', () {
      final keys = _payload(lat: -3.1, lon: -60.0).keys;
      for (final forbidden in ['nome', 'telefone', 'email', 'ip', 'device_id', 'user_id']) {
        expect(keys, isNot(contains(forbidden)));
      }
    });
  });

  group('newSubmissionId', () {
    test('é um UUID versão 4 válido', () {
      final id = newSubmissionId(random: Random(1));
      expect(
        id,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });

    test('muda a cada envio', () {
      final r = Random(7);
      final ids = {for (var i = 0; i < 50; i++) newSubmissionId(random: r)};
      expect(ids, hasLength(50));
    });
  });

  group('ApiClient', () {
    ApiClient clientFor(http.Client c) => ApiClient(client: c, baseUrl: 'https://api.exemplo.com/');

    test('não configurado quando o endereço é vazio', () {
      expect(ApiClient(baseUrl: '').isConfigured, isFalse);
      expect(ApiClient(baseUrl: 'https://x.com/').isConfigured, isTrue);
    });

    test('POST /respostas com JSON e aceita 201 e 200 (reenvio idempotente)', () async {
      late http.Request seen;
      final mock = MockClient((request) async {
        seen = request;
        return http.Response('{"id":1,"duplicado":false}', 201);
      });
      await clientFor(mock).postAnswer(_payload());
      expect(seen.url.toString(), 'https://api.exemplo.com/respostas');
      expect(seen.headers['content-type'], contains('application/json'));
      expect(jsonDecode(seen.body)['nivel'], 'high');

      final dup = MockClient((_) async => http.Response('{"id":1,"duplicado":true}', 200));
      await clientFor(dup).postAnswer(_payload()); // não lança
    });

    test('422 é recusa permanente; 429 e 5xx são temporárias', () async {
      Future<ApiException> failWith(int code) async {
        final mock = MockClient((_) async => http.Response('erro', code));
        try {
          await clientFor(mock).postAnswer(_payload());
        } on ApiException catch (e) {
          return e;
        }
        fail('deveria ter lançado ApiException');
      }

      expect((await failWith(422)).permanent, isTrue);
      expect((await failWith(429)).permanent, isFalse);
      expect((await failWith(503)).permanent, isFalse);
    });

    test('falha de rede é temporária', () async {
      final mock = MockClient((_) async => throw const SocketException('sem rede'));
      await expectLater(
        clientFor(mock).postAnswer(_payload()),
        throwsA(isA<ApiException>().having((e) => e.permanent, 'permanent', false)),
      );
    });

    test('GET /mapa interpreta as células', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/mapa');
        expect(request.url.queryParameters['horas'], '72');
        return http.Response(
          '{"horas":72,"minimo_por_celula":3,"celulas":['
          '{"lat":-3.12,"lon":-60.02,"respostas":4,"pior_nivel":"high"}]}',
          200,
        );
      });
      final cells = await clientFor(mock).fetchMap();
      expect(cells.single.lat, -3.12);
      expect(cells.single.responses, 4);
      expect(cells.single.worst, RiskLevel.high);
    });

    test('GET /estatisticas lê o formato do servidor', () async {
      final mock = MockClient((request) async {
        expect(request.url.queryParameters['dias'], '30');
        return http.Response(
          '{"periodo_dias":30,"total_respostas":0,"suficiente":false,'
          '"minimo_para_divulgar":5,"niveis":{"low":0,"moderate":0,"high":0,"emergency":0},'
          '"sintomas":[],"serie":[]}',
          200,
        );
      });
      final stats = await clientFor(mock).fetchStats();
      expect(stats.sufficient, isFalse);
      expect(stats.minimumToDisclose, 5);
    });

    test('resposta inesperada vira ApiException', () async {
      final mock = MockClient((_) async => http.Response('não é json', 200));
      await expectLater(clientFor(mock).fetchMap(), throwsA(isA<ApiException>()));
    });
  });
}
