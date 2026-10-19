import 'fire_satellite.dart';

/// Foco de calor detectado por satélite (dado oficial do INPE / Programa Queimadas).
///
/// Um foco indica uma detecção de fogo ou anomalia térmica no ponto e horário
/// informados. Ele NÃO é uma medição direta da qualidade do ar. A fumaça de
/// queimadas é uma das principais fontes de poluição do ar na região, mas a
/// concentração de poluentes depende de vento, relevo e distância da fonte.
class FireHotspot {
  const FireHotspot({
    required this.lat,
    required this.lon,
    required this.detectedAt,
    required this.state,
    required this.municipality,
    required this.satellite,
    required this.biome,
    this.frp,
    this.daysWithoutRain,
    this.fireRisk,
  });

  final double lat;
  final double lon;

  /// Data e hora da detecção, em UTC (campo `data_hora_gmt` do INPE).
  final DateTime detectedAt;
  final String state;
  final String municipality;

  /// Valor bruto do campo `satelite` (ex.: "NOAA-20", "AQUA_M-T").
  final String satellite;
  final String biome;

  /// Potência radiativa do fogo (FRP, em MW), quando disponível.
  final double? frp;

  /// Dias sem chuva até a detecção (campo `numero_dias_sem_chuva` do INPE).
  final int? daysWithoutRain;

  /// Valor do campo `risco_fogo` do INPE, exibido como veio. O app não interpreta
  /// a escala: apenas repassa o dado oficial.
  final double? fireRisk;

  /// Família do satélite (MODIS, NOAA-20, Suomi NPP...), ou `null` se for outro.
  FireSatellite? get family => FireSatellite.fromInpeName(satellite);

  /// Classe visual de intensidade para o mapa.
  ///
  /// ATENÇÃO: os limites abaixo são apenas uma escala de exibição escolhida
  /// para facilitar a leitura. Não são limiares validados de risco à saúde.
  FireIntensity get intensity {
    final value = frp ?? 0;
    if (value >= 50) return FireIntensity.strong;
    if (value >= 10) return FireIntensity.medium;
    return FireIntensity.weak;
  }
}

enum FireIntensity { weak, medium, strong }
