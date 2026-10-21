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

/// Raios (km, a partir da sede do município) que a pessoa pode escolher para os focos de calor.
const kFireRadii = <int>[10, 25, 50, 100];
const kDefaultFireRadius = 50;

/// Reenvia o aviso, mesmo sem piora, depois deste tempo com o índice ainda acima do limiar.
const kAlertRepeatAfter = Duration(hours: 12);

class AirAlertSettings {
  const AirAlertSettings({
    this.enabled = false,
    this.municipalityCode = kDefaultAlertMunicipalityCode,
    this.municipalityName = 'Manaus',
    this.threshold = kDefaultAlertThreshold,
    this.fireEnabled = false,
    this.fireRadiusKm = kDefaultFireRadius,
  });

  final bool fireEnabled;
  final int fireRadiusKm;

  /// Alguma checagem em segundo plano precisa rodar?
  bool get anyEnabled => enabled || fireEnabled;

  final bool enabled;
  final int municipalityCode;
  final String municipalityName;
  final int threshold;

  AirAlertSettings copyWith({
    bool? enabled,
    int? municipalityCode,
    String? municipalityName,
    int? threshold,
    bool? fireEnabled,
    int? fireRadiusKm,
  }) =>
      AirAlertSettings(
        enabled: enabled ?? this.enabled,
        municipalityCode: municipalityCode ?? this.municipalityCode,
        municipalityName: municipalityName ?? this.municipalityName,
        threshold: threshold ?? this.threshold,
        fireEnabled: fireEnabled ?? this.fireEnabled,
        fireRadiusKm: fireRadiusKm ?? this.fireRadiusKm,
      );

  Map<String, dynamic> toJson() => {
        'ativo': enabled,
        'codigo': municipalityCode,
        'nome': municipalityName,
        'limiar': threshold,
        'foco_ativo': fireEnabled,
        'foco_raio': fireRadiusKm,
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
      fireEnabled: j['foco_ativo'] == true,
      fireRadiusKm: j['foco_raio'] is int && kFireRadii.contains(j['foco_raio']) ? j['foco_raio'] as int : kDefaultFireRadius,
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


// ------------------------------------------------------------------ focos de calor

/// Leitura devolvida por `GET /app/focos`.
class FireAlertReading {
  const FireAlertReading({
    required this.municipalityName,
    required this.radiusKm,
    required this.count24h,
    required this.count48h,
    required this.nearestKm,
    required this.lastDetectionUtc,
    required this.stale,
  });

  final String municipalityName;
  final int radiusKm;
  final int count24h;
  final int count48h;
  final double? nearestKm;
  final DateTime? lastDetectionUtc;
  final bool stale;

  factory FireAlertReading.fromJson(Map<String, dynamic> j) => FireAlertReading(
        municipalityName: j['municipio'] as String,
        radiusKm: (j['raio_km'] as num).toInt(),
        count24h: (j['focos_24h'] as num).toInt(),
        count48h: (j['focos_48h'] as num).toInt(),
        nearestKm: (j['mais_proximo_km'] as num?)?.toDouble(),
        lastDetectionUtc:
            j['ultima_deteccao_utc'] is String ? DateTime.tryParse(j['ultima_deteccao_utc'] as String)?.toUtc() : null,
        stale: j['desatualizado'] == true,
      );
}

class FireAlertState {
  const FireAlertState({this.lastCount, this.lastNotifiedAt});

  final int? lastCount;
  final DateTime? lastNotifiedAt;

  Map<String, dynamic> toJson() => {'total': lastCount, 'em': lastNotifiedAt?.toUtc().toIso8601String()};

  factory FireAlertState.fromJson(Map<String, dynamic> j) => FireAlertState(
        lastCount: j['total'] is int ? j['total'] as int : null,
        lastNotifiedAt: j['em'] is String ? DateTime.tryParse(j['em'] as String)?.toUtc() : null,
      );
}

/// Aviso de focos só repete se o total crescer bastante, ou depois de 24 h ainda com focos
/// (na época de queimadas há focos quase todo dia: sem esta regra seria um aviso diário sem novidade).
const kFireRepeatAfter = Duration(hours: 24);
const kFireMinGrowth = 5;

/// Decide o que fazer com a leitura de focos (últimas 24 h dentro do raio).
///
/// - desligado ou dado desatualizado: nada;
/// - nenhum foco: `reset` se havia aviso guardado;
/// - com focos: avisa se nunca avisou, se o total subiu pelo menos [kFireMinGrowth] E 50% sobre o
///   último aviso, ou se passaram [kFireRepeatAfter].
AlertAction decideFireAlert({
  required AirAlertSettings settings,
  required FireAlertReading reading,
  required FireAlertState state,
  required DateTime now,
}) {
  if (!settings.fireEnabled || reading.stale) return AlertAction.none;
  final n = reading.count24h;
  if (n <= 0) {
    return state.lastCount == null && state.lastNotifiedAt == null ? AlertAction.none : AlertAction.reset;
  }
  final last = state.lastCount;
  final when = state.lastNotifiedAt;
  if (last == null || when == null) return AlertAction.notify;
  if (n - last >= kFireMinGrowth && n >= last * 1.5) return AlertAction.notify;
  if (now.toUtc().difference(when) >= kFireRepeatAfter) return AlertAction.notify;
  return AlertAction.none;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Texto da notificação de focos. Horário em Manaus (UTC-4, sem horário de verão).
({String title, String body}) fireMessage(FireAlertReading r) {
  final n = r.count24h;
  final detections = n == 1 ? '1 foco de calor' : '$n focos de calor';
  final nearest = r.nearestKm == null ? '' : ' O mais próximo está a ${_num(r.nearestKm!)} km.';
  var last = '';
  final t = r.lastDetectionUtc;
  if (t != null) {
    final m = t.subtract(const Duration(hours: 4));
    last = ' Última detecção: ${_two(m.day)}/${_two(m.month)} às ${_two(m.hour)}:${_two(m.minute)} (Manaus).';
  }
  return (
    title: 'Focos de calor perto de ${r.municipalityName}',
    body: '$detections nas últimas 24 h, num raio de ${r.radiusKm} km da sede.$nearest$last '
        'São detecções por satélite (INPE), não incêndios confirmados.',
  );
}
