import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:respirar_amazonas/logic/map_layers.dart';
import 'package:respirar_amazonas/services/gibs_availability.dart';

void main() {
  test('tile de referência de Manaus no zoom 3 é x=2, y=4', () {
    final t = GibsAvailability.tileOf(GibsAvailability.refLat, GibsAvailability.refLon, 3);
    expect(t.x, 2);
    expect(t.y, 4);
  });

  test('URL de teste preenche z/y/x e a data', () {
    final u = GibsAvailability.probeUri(gibsTrueColor, '2026-10-19');
    expect(u.toString(), contains('/default/2026-10-19/GoogleMapsCompatible_Level9/3/4/2.jpg'));
  });

  test('lista só os dias em que todas as camadas respondem 200', () async {
    final now = DateTime.utc(2026, 10, 20, 12);
    final client = MockClient((req) async {
      final u = req.url.toString();
      // 20/10 não existe; 19/10 só a cor real; 18/10 ambas.
      if (u.contains('2026-10-20')) return http.Response('', 404);
      if (u.contains('2026-10-19') && u.contains('Aerosol')) return http.Response('', 404);
      return http.Response('x', 200);
    });
    final a = GibsAvailability(client: client, now: () => now);
    final both = await a.availableDaysBack([gibsTrueColor, gibsAerosol]);
    expect(both.contains(0), isFalse);
    expect(both.contains(1), isFalse);
    expect(both.first, 2);
    final onlyTrue = await a.availableDaysBack([gibsTrueColor]);
    expect(onlyTrue.first, 1);
  });

  test('falha de rede não conta como disponível', () async {
    final a = GibsAvailability(
      client: MockClient((_) async => throw http.ClientException('sem rede')),
      now: () => DateTime.utc(2026, 10, 20),
    );
    expect(await a.availableDaysBack([gibsTrueColor]), isEmpty);
  });
}
