import '../services/air_quality_service.dart' show AirCategory, airCategoryOf;

/// Posição da faixa do índice (0 = boa ... 5 = perigosa).
int airCategoryIndex(int usAqi) => airCategoryOf(usAqi).index;

/// Alertas de qualidade do ar: configuração, leitura e regra de decisão (funções puras, testáveis).
///
/// LIMITE: o índice vem de um MODELO (CAMS via Open-Meteo, ~45 km), não de uma estação. O alerta
/// diz isso no texto. Não substitui boletins oficiais nem orientação de saúde.

/// Código IBGE de Manaus (padrão).
const kDefaultAlertMunicipalityCode = 1302603;

/// Limiar padrão: 101 = "ruim para grupos sensíveis" (faixa da EPA, igual à do app).
const kDefaultAlertThreshold = 101;

/// Limiares que a pessoa pode escolher (início de cada faixa do US AQI).
const kAlertThresholds = <int>[51, 101, 151];

/// Reenvia o aviso, mesmo sem piora, depois deste tempo com o índice ainda acima do limiar.
const kAlertRepeatAfter = Duration(hours: 12);

class AirAlertSettings {
  const AirAlertSettings({
    this.enabled = false,
    this.municipalityCode = kDefaultAlertMunicipalityCode,
    this.municipalityName = 'Manaus',
    this.threshold = kDefaultAlertThreshold,
  });

  final bool enabled;
  final int municipalityCode;
  final String municipalityName;
  final int threshold;

  AirAlertSettings copyWith({bool? enabled, int? municipalityCode, String? municipalityName, int? threshold}) =>
      AirAlertSettings(
        enabled: enabled ?? this.enabled,
        municipalityCode: municipalityCode ?? this.municipalityCode,
        municipalityName: municipalityName ?? this.municipalityName,
        threshold: threshold ?? this.threshold,
      );

  Map<String, dynamic> toJson() => {
        'ativo': enabled,
        'codigo': municipalityCode,
        'nome': municipalityName,
        'limiar': threshold,
      };

  /// Tolerante: qualquer campo ausente ou inválido volta ao padrão.
  factory AirAlertSettings.fromJson(Map<String, dynamic> j) {
    final threshold = j['limiar'];
    final code = j['codigo'];
    final name = j['nome'];
    return AirAlertSettings(
      enabled: j['ativo'] == true,
      municipalityCode: code is int && code >= 1300000 && code <= 1399999 ? code : kDefaultAlertMunicipalityCode,
      municipalityName: name is String && name.trim().isNotEmpty ? name.trim() : 'Manaus',
      threshold: threshold is int && kAlertThresholds.contains(threshold) ? threshold : kDefaultAlertThreshold,
    );
  }
}

/// Leitura devolvida por `GET /app/ar`.
class AirAlertReading {
  const AirAlertReading({
    required this.municipalityName,
    required this.usAqi,
    required this.pm25,
    required this.pm10,
    required this.modelTime,
    required this.stale,
  });

  final String municipalityName;
  final int? usAqi;
  final double? pm25;
  final double? pm10;

  /// Instante do modelo (UTC), se informado.
  final DateTime? modelTime;

  /// O servidor devolveu a última leitura boa porque o serviço de origem falhou.
  final bool stale;

  factory AirAlertReading.fromJson(Map<String, dynamic> j) => AirAlertReading(
        municipalityName: j['municipio'] as String,
        usAqi: (j['us_aqi'] as num?)?.round(),
        pm25: (j['pm2_5'] as num?)?.toDouble(),
        pm10: (j['pm10'] as num?)?.toDouble(),
        modelTime: j['referencia_modelo'] is String ? DateTime.tryParse(j['referencia_modelo'] as String)?.toUtc() : null,
        stale: j['desatualizado'] == true,
      );
}

/// Último aviso enviado (para não repetir a mesma notificação a cada checagem).
class AirAlertState {
  const AirAlertState({this.lastCategoryIndex, this.lastNotifiedAt});

  final int? lastCategoryIndex;
  final DateTime? lastNotifiedAt;

  Map<String, dynamic> toJson() => {
        'categoria': lastCategoryIndex,
        'em': lastNotifiedAt?.toUtc().toIso8601String(),
      };

  factory AirAlertState.fromJson(Map<String, dynamic> j) => AirAlertState(
        lastCategoryIndex: j['categoria'] is int ? j['categoria'] as int : null,
        lastNotifiedAt: j['em'] is String ? DateTime.tryParse(j['em'] as String)?.toUtc() : null,
      );
}

enum AlertAction {
  /// Nada a fazer.
  none,

  /// Enviar notificação.
  notify,

  /// Índice voltou abaixo do limiar: esquecer o último aviso (o próximo aumento avisa de novo).
  reset,
}

/// Decide o que fazer com uma leitura.
///
/// - desligado, sem índice ou leitura desatualizada: nada (não alarmar com dado velho);
/// - abaixo do limiar: `reset` se havia aviso guardado;
/// - no limiar ou acima: avisa se nunca avisou, se a categoria PIOROU, ou se já passaram
///   [kAlertRepeatAfter] desde o último aviso.
AlertAction decideAlert({
  required AirAlertSettings settings,
  required AirAlertReading reading,
  required AirAlertState state,
  required DateTime now,
}) {
  final aqi = reading.usAqi;
  if (!settings.enabled || aqi == null || reading.stale) return AlertAction.none;
  if (aqi < settings.threshold) {
    return state.lastCategoryIndex == null && state.lastNotifiedAt == null ? AlertAction.none : AlertAction.reset;
  }
  final category = airCategoryIndex(aqi);
  final last = state.lastCategoryIndex;
  final when = state.lastNotifiedAt;
  if (last == null || when == null) return AlertAction.notify;
  if (category > last) return AlertAction.notify;
  if (now.toUtc().difference(when) >= kAlertRepeatAfter) return AlertAction.notify;
  return AlertAction.none;
}

String _num(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// Título e texto da notificação.
({String title, String body}) alertMessage(AirAlertReading r) {
  final aqi = r.usAqi!;
  final AirCategory category = airCategoryOf(aqi);
  final pm = r.pm25 == null ? '' : ' PM2,5: ${_num(r.pm25!)} µg/m³.';
  return (
    title: 'Qualidade do ar em ${r.municipalityName}: ${category.label}',
    body: 'Índice $aqi (US AQI).$pm Estimativa de modelo (~45 km), não é medição de estação. '
        'Abra o app para ver as orientações.',
  );
}
