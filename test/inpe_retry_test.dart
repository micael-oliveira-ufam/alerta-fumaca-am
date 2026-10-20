import 'dart:io';

import 'package:respirar_amazonas/services/inpe_fire_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _vazio = '{"type":"FeatureCollection","features":[]}';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('repete após falha de rede e entrega os focos na segunda tentativa', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      if (calls == 1) throw const SocketException('primeira conexão falhou');
      return http.Response(_vazio, 200);
    });
    final service = InpeFireService(client: client, apiBaseUrl: '');
    final result = await service.fetch(FireWindow.today, retryDelay: Duration.zero);
    expect(calls, 2);
    expect(result.fromCache, isFalse);
    expect(result.hotspots, isEmpty);
  });

  test('desiste depois de retries+1 tentativas e relança o erro de rede', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      throw const SocketException('sem rede');
    });
    final service = InpeFireService(client: client, apiBaseUrl: '');
    await expectLater(
      service.fetch(FireWindow.today, retries: 2, retryDelay: Duration.zero),
      throwsA(isA<InpeException>().having((e) => e.kind, 'kind', InpeErrorKind.network)),
    );
    expect(calls, 3);
  });

  test('erro de formato NÃO é repetido', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('<html>erro</html>', 200);
    });
    final service = InpeFireService(client: client, apiBaseUrl: '');
    await expectLater(
      service.fetch(FireWindow.today, retryDelay: Duration.zero),
      throwsA(isA<InpeException>().having((e) => e.kind, 'kind', InpeErrorKind.format)),
    );
    expect(calls, 1);
  });
}
