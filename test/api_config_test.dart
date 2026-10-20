import 'package:respirar_amazonas/services/api_client.dart';
import 'package:respirar_amazonas/services/api_config.dart';
import 'package:respirar_amazonas/services/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('parseServerAddress', () {
    test('aceita o link do túnel, com ou sem https e barra final', () {
      const esperado = 'https://roda-livre-1234.trycloudflare.com';
      expect(parseServerAddress('https://roda-livre-1234.trycloudflare.com'), esperado);
      expect(parseServerAddress('  https://roda-livre-1234.trycloudflare.com/ '), esperado);
      expect(parseServerAddress('roda-livre-1234.trycloudflare.com'), esperado);
      expect(parseServerAddress('https://roda-livre-1234.trycloudflare.com/respostas'), esperado);
    });

    test('mantém a porta', () {
      expect(parseServerAddress('https://api.exemplo.org:8443/'), 'https://api.exemplo.org:8443');
    });

    test('http só para o próprio aparelho/emulador', () {
      expect(parseServerAddress('http://10.0.2.2:8000'), 'http://10.0.2.2:8000');
      expect(parseServerAddress('http://localhost:8000/'), 'http://localhost:8000');
      expect(() => parseServerAddress('http://api.exemplo.org'), throwsFormatException);
      expect(() => parseServerAddress('http://192.168.0.10:8000'), throwsFormatException);
    });

    test('recusa vazio, usuário/senha, parâmetros e esquemas estranhos', () {
      for (final bad in [
        '',
        '   ',
        'https://usuario:senha@api.exemplo.org',
        'https://api.exemplo.org/?a=1',
        'https://api.exemplo.org/#x',
        'ftp://api.exemplo.org',
        'https://',
        'javascript:alert(1)',
      ]) {
        expect(() => parseServerAddress(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('ApiConfig (persistência)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await ApiConfig.save(null);
    });

    test('sem nada salvo e sem compilação: modo local', () async {
      await ApiConfig.load();
      expect(ApiConfig.isConfigured, isFalse);
      expect(ApiConfig.isOverridden, isFalse);
      expect(ApiConfig.host, '');
    });

    test('salvar vale na hora e sobrevive a um novo load()', () async {
      await ApiConfig.save('https://a-b-c.trycloudflare.com');
      expect(ApiConfig.baseUrl, 'https://a-b-c.trycloudflare.com');
      expect(ApiConfig.host, 'a-b-c.trycloudflare.com');
      expect(ApiClient().isConfigured, isTrue); // quem cria o cliente depois já usa o novo endereço

      await ApiConfig.load(); // simula reabrir o app
      expect(ApiConfig.isOverridden, isTrue);
      expect(ApiConfig.baseUrl, 'https://a-b-c.trycloudflare.com');
    });

    test('save(null) volta ao padrão', () async {
      await ApiConfig.save('https://a-b-c.trycloudflare.com');
      await ApiConfig.save(null);
      expect(ApiConfig.isOverridden, isFalse);
      expect(ApiConfig.isConfigured, isFalse);
    });

    test('valor inválido guardado é ignorado no load()', () async {
      SharedPreferences.setMockInitialValues({'servidor_url_v1': 'http://malicioso.example'});
      await ApiConfig.load();
      expect(ApiConfig.isOverridden, isFalse);
    });

    test('trocar de servidor zera o consentimento de envio', () async {
      final consent = ConsentStore();
      await consent.setSendDecision(true);
      await consent.setIncludeLocationInSend(true);
      await consent.resetSendDecision();
      expect(await consent.sendDecision(), isNull);
      expect(await consent.includeLocationInSend(), isFalse);
    });
  });

  group('checkHealth', () {
    ApiClient clientFor(http.Client c) => ApiClient(client: c, baseUrl: 'https://x.trycloudflare.com');

    test('servidor correto devolve a versão', () async {
      final mock = MockClient((r) async {
        expect(r.url.path, '/health');
        return http.Response('{"status":"ok","version":"1.0.0"}', 200);
      });
      expect(await clientFor(mock).checkHealth(), '1.0.0');
    });

    test('qualquer outra coisa é recusada', () async {
      for (final body in ['{"status":"erro"}', '{"foo":1}', '[]']) {
        final mock = MockClient((_) async => http.Response(body, 200));
        await expectLater(clientFor(mock).checkHealth(), throwsA(isA<ApiException>()), reason: body);
      }
      final down = MockClient((_) async => http.Response('', 503));
      await expectLater(clientFor(down).checkHealth(), throwsA(isA<ApiException>()));
    });
  });
}
