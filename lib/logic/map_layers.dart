import 'dart:math' as math;

/// Camadas de imagens de satélite da NASA GIBS (Global Imagery Browse Services)
/// usadas no mapa, no sistema de tiles Web Mercator (EPSG:3857) do WMTS.
///
/// VERIFICAÇÃO: o padrão da URL segue a documentação pública da GIBS
/// (`.../wmts/epsg3857/best/{camada}/default/{data}/{matriz}/{z}/{y}/{x}.{ext}`).
/// Os identificadores de camada, formatos e níveis máximos abaixo NÃO puderam ser
/// conferidos contra o serviço no ambiente de desenvolvimento (acesso bloqueado).
/// Se uma camada não carregar, o app avisa; confira o nome em
/// https://nasa-gibs.github.io/gibs-api-docs/available-visualizations/ e ajuste aqui.
class GibsLayer {
  const GibsLayer({
    required this.id,
    required this.label,
    required this.description,
    required this.ext,
    required this.maxNativeZoom,
    this.opacity = 1.0,
  });

  /// Identificador da camada na GIBS.
  final String id;
  final String label;
  final String description;

  /// `jpg` ou `png`.
  final String ext;

  /// Nível máximo de tiles reais; acima disso o app amplia o último nível.
  final int maxNativeZoom;
  final double opacity;

  /// Nome do conjunto de matrizes: `GoogleMapsCompatible_Level{N}`.
  String get matrixSet => 'GoogleMapsCompatible_Level$maxNativeZoom';

  /// Modelo de URL para o `TileLayer` do flutter_map ({z}, {y}, {x} nessa ordem).
  String urlTemplate(String date) =>
      'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/$id/default/$date/$matrixSet/{z}/{y}/{x}.$ext';
}

/// Imagem de satélite em cor real (usada como mapa base alternativo).
const gibsTrueColor = GibsLayer(
  id: 'VIIRS_SNPP_CorrectedReflectance_TrueColor',
  label: 'Satélite (cor real, NASA VIIRS)',
  description: 'Imagem diária do satélite Suomi NPP. Nuvens e a fumaça aparecem como na foto.',
  ext: 'jpg',
  maxNativeZoom: 9,
);

/// Aerossóis (fumaça e poeira) estimados pelo MODIS/Terra.
const gibsAerosol = GibsLayer(
  id: 'MODIS_Terra_Aerosol',
  label: 'Fumaça e aerossóis (NASA MODIS)',
  description: 'Profundidade óptica de aerossóis: valores altos sugerem fumaça, poeira ou neblina. '
      'Não é medição de PM2,5 no solo.',
  ext: 'png',
  maxNativeZoom: 6,
  opacity: 0.65,
);

/// Anomalias térmicas (focos de calor) do VIIRS 375 m, independentes do INPE.
const gibsThermal = GibsLayer(
  id: 'VIIRS_SNPP_Thermal_Anomalies_375m_All',
  label: 'Focos de calor (NASA VIIRS 375 m)',
  description: 'Detecção de fogo do satélite Suomi NPP. Complementa os focos do INPE.',
  ext: 'png',
  maxNativeZoom: 9,
);

const gibsOverlays = [gibsAerosol, gibsThermal];

/// Data (AAAA-MM-DD, UTC) para pedir imagens à GIBS.
///
/// A imagem do dia corrente costuma estar incompleta; por isso o padrão é 1 dia atrás.
String gibsDate(DateTime nowUtc, {int daysBack = 1}) {
  final d = nowUtc.toUtc().subtract(Duration(days: daysBack));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

/// Metros por pixel (tile de 256 px, Web Mercator) numa latitude e zoom.
double metersPerPixel(double latitude, double zoom) {
  const equator = 156543.03392;
  return equator * math.cos(latitude * math.pi / 180) / math.pow(2, zoom);
}

/// Maior valor "redondo" (1, 2, 5 × 10^n m) que cabe em [maxMeters].
double niceScaleMeters(double maxMeters) {
  if (maxMeters <= 0) return 0;
  var magnitude = 1.0;
  while (magnitude * 10 <= maxMeters) {
    magnitude *= 10;
  }
  while (magnitude > maxMeters) {
    magnitude /= 10;
  }
  for (final m in const [5.0, 2.0, 1.0]) {
    if (magnitude * m <= maxMeters) return magnitude * m;
  }
  return magnitude;
}

String scaleLabel(double meters) =>
    meters >= 1000 ? '${(meters / 1000).round()} km' : '${meters.round()} m';
