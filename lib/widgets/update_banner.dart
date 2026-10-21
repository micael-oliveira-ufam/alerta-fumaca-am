import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_info.dart';
import '../logic/app_update.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Aviso "há uma versão nova do app" na tela inicial.
///
/// Consulta o servidor do projeto ao abrir. Sem servidor configurado, sem conexão, em iPhone ou
/// com qualquer erro, não mostra nada (nunca atrapalha o uso). Atualização opcional pode ser
/// dispensada; a obrigatória (abaixo da versão mínima) não some, mas o app continua utilizável.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  AppUpdate? _info;
  UpdateKind _kind = UpdateKind.none;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      if (!Platform.isAndroid) return; // o APK é só para Android
      final api = ApiClient(timeout: const Duration(seconds: 6));
      if (!api.isConfigured) return;
      final info = await api.fetchAppUpdate();
      final kind = evaluateUpdate(kAppVersion, info);
      if (!mounted || kind == UpdateKind.none) return;
      setState(() {
        _info = info;
        _kind = kind;
      });
    } catch (_) {
      // sem rede ou resposta inesperada: simplesmente não avisa
    }
  }

  Future<void> _download() async {
    final url = _info?.url;
    if (url == null) return;
    var ok = false;
    try {
      ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o download. Endereço: $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null || _kind == UpdateKind.none || _dismissed) return const SizedBox.shrink();
    final required = _kind == UpdateKind.required;
    final text = required
        ? 'Esta versão ($kAppVersion) é antiga e pode não funcionar direito. '
            'Instale a versão ${info.latest ?? info.minimum}.'
        : 'Há uma versão nova do aplicativo: ${info.latest} (você tem $kAppVersion).';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        color: required ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_rounded, color: required ? AppColors.ink : AppColors.brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(text, style: const TextStyle(height: 1.35, color: AppColors.ink)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'O Android pede sua confirmação para instalar. Seus relatos guardados no aparelho são mantidos.',
              style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Baixar atualização'),
                ),
                if (!required) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _dismissed = true),
                    child: const Text('Agora não'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
