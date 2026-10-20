import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_config.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Link da plataforma online (painel público com os dados agregados), que o usuário abre
/// no navegador. Não há como alterar o endereço pelo app: ele é definido na compilação.
class PlatformCard extends StatelessWidget {
  const PlatformCard({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('Não foi possível abrir: $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = ApiConfig.baseUrl;
    final configured = url.isNotEmpty;
    return AppCard(
      onTap: configured ? () => _open(context, url) : null,
      child: Row(
        children: [
          const Icon(Icons.public_rounded, color: AppColors.brandDark, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Plataforma online',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 4),
                const Text(
                  'Focos de calor, sintomas mais relatados, mapas e bairros de Manaus mais '
                  'afetados, em dados agregados e abertos a qualquer pessoa.',
                  style: TextStyle(height: 1.4, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                Text(
                  configured ? url : 'Endereço ainda não disponível nesta versão do aplicativo.',
                  style: TextStyle(
                    color: configured ? const Color(0xFF1565C0) : AppColors.muted,
                    decoration: configured ? TextDecoration.underline : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
