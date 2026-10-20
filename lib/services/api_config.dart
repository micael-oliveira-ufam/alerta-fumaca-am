import 'package:shared_preferences/shared_preferences.dart';

/// Endereço do servidor próprio (API + banco).
///
/// Duas origens, nesta ordem de prioridade:
/// 1. o endereço colado pela pessoa em "Sobre → Servidor" (guardado neste aparelho);
/// 2. o definido na compilação: `flutter build apk --dart-define=API_BASE_URL=https://...`.
///
/// Vazio nas duas = modo local: nada é enviado a servidor algum; as estatísticas e o mapa da
/// comunidade usam só os dados deste aparelho, e os focos do INPE são consultados diretamente.
///
/// O link do túnel da Cloudflare é sorteado a cada início do túnel; por isso o endereço precisa
/// poder ser trocado no app sem recompilar.
class ApiConfig {
  const ApiConfig._();

  static const _compiled = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const _prefsKey = 'servidor_url_v1';

  static String? _override;

  /// Carrega o endereço salvo. Chamar uma vez em `main()`, antes de `runApp`.
  /// Falha de armazenamento não impede o app de abrir (segue com o endereço compilado).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      _override = saved == null ? null : _tryParse(saved);
    } catch (_) {
      _override = null;
    }
  }

  /// Endereço efetivo, sem barra final. Vazio se não configurado.
  static String get baseUrl => _override ?? normalize(_compiled);

  static bool get isConfigured => baseUrl.isNotEmpty;

  /// `true` se o endereço atual foi colado pela pessoa (e não veio da compilação).
  static bool get isOverridden => _override != null;

  /// Endereço definido na compilação (pode ser vazio).
  static String get compiledBaseUrl => normalize(_compiled);

  /// Host do endereço efetivo (para mostrar à pessoa), ou vazio.
  static String get host => isConfigured ? (Uri.tryParse(baseUrl)?.host ?? '') : '';

  /// Salva um endereço já validado por [parseServerAddress]. `null` volta ao padrão do app.
  static Future<void> save(String? validated) async {
    final prefs = await SharedPreferences.getInstance();
    if (validated == null) {
      await prefs.remove(_prefsKey);
      _override = null;
    } else {
      await prefs.setString(_prefsKey, validated);
      _override = validated;
    }
  }

  /// Remove espaços e barras finais para montar URLs sem `//`.
  static String normalize(String url) {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String? _tryParse(String value) {
    try {
      return parseServerAddress(value);
    } on FormatException {
      return null;
    }
  }
}

/// Valida o endereço colado pela pessoa e devolve a forma canônica `https://host[:porta]`.
///
/// Regras (o app envia dados de saúde a este endereço, então é restritivo):
/// - exige `https` (HTTP puro só para o próprio aparelho/emulador: localhost, 127.0.0.1, 10.0.2.2);
/// - sem usuário/senha, sem parâmetros nem fragmento; um caminho, se houver, é descartado.
/// Lança [FormatException] com mensagem em português.
String parseServerAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) throw const FormatException('Cole o endereço do servidor.');
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) throw const FormatException('Endereço inválido.');
  if (uri.userInfo.isNotEmpty) {
    throw const FormatException('O endereço não pode conter usuário ou senha.');
  }
  if (uri.hasQuery || uri.hasFragment) {
    throw const FormatException('Cole só o endereço, sem "?" nem "#".');
  }
  const local = {'localhost', '127.0.0.1', '10.0.2.2'};
  if (uri.scheme == 'http' && local.contains(uri.host)) {
    return 'http://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }
  if (uri.scheme != 'https') {
    throw const FormatException('Use um endereço https:// (conexão segura).');
  }
  return 'https://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
}
