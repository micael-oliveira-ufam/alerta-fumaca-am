/// Verificação de atualização do aplicativo instalado.
///
/// O app consulta `GET /app/versao` no servidor do projeto. A resposta só informa a versão do APK
/// publicado e o endereço para baixá-lo; nada sobre a pessoa é enviado.
///
/// LIMITE HONESTO: o Android não permite que um app instale a própria atualização em silêncio fora
/// da loja. O app avisa e abre o download; a pessoa confirma a instalação no sistema.
library;

enum UpdateKind {
  /// Está na versão publicada (ou não foi possível saber).
  none,

  /// Há versão mais nova; atualizar é opcional.
  available,

  /// A versão instalada é menor que a mínima aceita pelo servidor.
  required,
}

/// Interpreta "X.Y.Z" como três inteiros. Devolve `null` se o texto não for exatamente isso.
List<int>? parseVersion(String? text) {
  if (text == null) return null;
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(text.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

/// Compara por números (1.10.0 > 1.9.0). `null` se alguma das versões for inválida.
int? compareVersions(String a, String b) {
  final x = parseVersion(a);
  final y = parseVersion(b);
  if (x == null || y == null) return null;
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
  }
  return 0;
}

class AppUpdate {
  const AppUpdate({this.latest, this.minimum, this.url, this.sha256, this.sizeBytes});

  final String? latest;
  final String? minimum;

  /// Endereço do download (só http/https).
  final Uri? url;
  final String? sha256;
  final int? sizeBytes;

  factory AppUpdate.fromJson(Map<String, dynamic> j) {
    Uri? url;
    final raw = j['url'];
    if (raw is String) {
      final parsed = Uri.tryParse(raw);
      if (parsed != null && (parsed.scheme == 'https' || parsed.scheme == 'http') && parsed.host.isNotEmpty) {
        url = parsed;
      }
    }
    return AppUpdate(
      latest: parseVersion(j['ultima'] as String?) == null ? null : j['ultima'] as String,
      minimum: parseVersion(j['minima'] as String?) == null ? null : j['minima'] as String,
      url: url,
      sha256: j['sha256'] as String?,
      sizeBytes: (j['tamanho_bytes'] as num?)?.toInt(),
    );
  }
}

/// Decide o que mostrar à pessoa. Sem link de download não há o que oferecer: `none`.
UpdateKind evaluateUpdate(String current, AppUpdate info) {
  if (info.url == null) return UpdateKind.none;
  final min = info.minimum;
  if (min != null && (compareVersions(current, min) ?? 0) < 0) return UpdateKind.required;
  final latest = info.latest;
  if (latest != null && (compareVersions(current, latest) ?? 0) < 0) return UpdateKind.available;
  return UpdateKind.none;
}
