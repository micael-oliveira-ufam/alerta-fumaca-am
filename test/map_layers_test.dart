import 'package:respirar_amazonas/logic/map_layers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('URL GIBS segue o padrão WMTS com {z}/{y}/{x}', () {
    final url = gibsAerosol.urlTemplate('2026-10-18');
    expect(
      url,
      'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/MODIS_Terra_Aerosol/default/'
      '2026-10-18/GoogleMapsCompatible_Level6/{z}/{y}/{x}.png',
    );
    expect(gibsTrueColor.urlTemplate('2026-10-18'), endsWith('{z}/{y}/{x}.jpg'));
  });

  test('data da GIBS é UTC e recua os dias pedidos', () {
    final now = DateTime.utc(2026, 10, 19, 1);
    expect(gibsDate(now), '2026-10-18');
    expect(gibsDate(now, daysBack: 0), '2026-10-19');
    expect(gibsDate(DateTime.utc(2026, 3, 1), daysBack: 1), '2026-02-28');
  });

  test('metros por pixel: valor conhecido no equador, zoom 0', () {
    expect(metersPerPixel(0, 0), closeTo(156543.03392, 1e-6));
    expect(metersPerPixel(0, 1), closeTo(156543.03392 / 2, 1e-6));
    expect(metersPerPixel(60, 0), closeTo(156543.03392 / 2, 1e-3));
  });

  test('escala usa valores redondos 1, 2, 5', () {
    expect(niceScaleMeters(1), 1);
    expect(niceScaleMeters(7), 5);
    expect(niceScaleMeters(30), 20);
    expect(niceScaleMeters(99), 50);
    expect(niceScaleMeters(100), 100);
    expect(niceScaleMeters(2400), 2000);
    expect(niceScaleMeters(0), 0);
    expect(scaleLabel(2000), '2 km');
    expect(scaleLabel(500), '500 m');
  });
}
