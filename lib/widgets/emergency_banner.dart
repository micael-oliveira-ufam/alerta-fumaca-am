import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/guidance_content.dart';
import '../logic/risk_assessment.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Alerta de emergência com acesso direto ao SAMU.
class EmergencyBanner extends StatelessWidget {
  const EmergencyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final red = levelColor(RiskLevel.emergency);
    return AppCard(
      color: red.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_rounded, color: red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sinais de alerta: procure atendimento agora.',
                  style: TextStyle(fontWeight: FontWeight.w700, color: red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: red),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: kSamuNumber)),
              icon: const Icon(Icons.call),
              label: const Text('Ligar SAMU 192'),
            ),
          ),
        ],
      ),
    );
  }
}
