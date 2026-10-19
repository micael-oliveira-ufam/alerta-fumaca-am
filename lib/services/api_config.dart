/// Endereço do servidor próprio (API + banco), definido na compilação.
///
///     flutter build apk --dart-define=API_BASE_URL=https://api.seudominio.com.br
///
/// Vazio (padrão) = modo local: nada é enviado a servidor algum; as estatísticas
/// e o mapa da comunidade usam apenas os dados deste aparelho, e os focos do INPE
/// são consultados diretamente.
class ApiConfig {
  const ApiConfig._();

  static const _raw = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Endereço sem barra final. Vazio se não configurado.
  static String get baseUrl => normalize(_raw);

  static bool get isConfigured => baseUrl.isNotEmpty;

  /// Remove espaços e barras finais para montar URLs sem `//`.
  static String normalize(String url) {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
