import 'package:respirar_amazonas/logic/app_update.dart';
import 'package:respirar_amazonas/services/stats_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareVersions', () {
    test('compara por números, não por texto', () {
      expect(compareVersions('1.9.0', '1.10.0'), -1);
      expect(compareVersions('1.10.0', '1.9.0'), 1);
      expect(compareVersions('1.8.0', '1.8.0'), 0);
    });
    test('versão inválida dá null', () {
      expect(compareVersions('1.8', '1.8.0'), isNull);
      expect(compareVersions('abc', '1.8.0'), isNull);
    });
  });

  group('evaluateUpdate', () {
    AppUpdate info(Map<String, dynamic> j) => AppUpdate.fromJson(j);

    test('versão mais nova publicada = disponível', () {
      final i = info({'ultima': '1.8.0', 'url': 'https://x.example/baixar/app.apk'});
      expect(evaluateUpdate('1.7.1', i), UpdateKind.available);
      expect(evaluateUpdate('1.8.0', i), UpdateKind.none);
      expect(evaluateUpdate('1.9.0', i), UpdateKind.none);
    });
    test('abaixo da mínima = obrigatória', () {
      final i = info({'ultima': '1.8.0', 'minima': '1.7.0', 'url': 'https://x.example/a.apk'});
      expect(evaluateUpdate('1.6.0', i), UpdateKind.required);
    });
    test('sem link ou com link inseguro não oferece nada', () {
      expect(evaluateUpdate('1.0.0', info({'ultima': '1.8.0', 'url': null})), UpdateKind.none);
      expect(evaluateUpdate('1.0.0', info({'ultima': '1.8.0', 'url': 'javascript:alert(1)'})), UpdateKind.none);
      expect(evaluateUpdate('1.0.0', info({'ultima': '1.8.0', 'url': 'file:///sdcard/a.apk'})), UpdateKind.none);
    });
    test('versão publicada inválida é ignorada', () {
      expect(evaluateUpdate('1.0.0', info({'ultima': 'lixo', 'url': 'https://x.example/a.apk'})), UpdateKind.none);
    });
  });

  group('StatsCache.parseCached', () {
    test('lê o que foi guardado', () {
      final c = StatsCache.parseCached(
          '{"dias":30,"salvo_em":"2026-10-20T20:00:00Z","estatisticas":{"a":1},"bairros":null}');
      expect(c, isNotNull);
      expect(c!.days, 30);
      expect(c.neighborhoods, isNull);
      expect(c.savedAt.toUtc().hour, 20);
    });
    test('texto ilegível dá null, sem lançar', () {
      expect(StatsCache.parseCached('não é json'), isNull);
      expect(StatsCache.parseCached('{"dias":30}'), isNull);
    });
  });
}
