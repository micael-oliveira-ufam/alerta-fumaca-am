import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/guidance_content.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Cartão de contato do Centro de Informações Toxicológicas do Amazonas.
///
/// Usado para dúvidas sobre exposição ou intoxicação por substâncias tóxicas.
/// Não substitui o SAMU (192) em casos graves.
class CitCard extends StatelessWidget {
  const CitCard({super.key});

  static const _teal = Color(0xFF00695C);

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/cit_am_logo.png',
                width: 56,
                height: 56,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kCitName,
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.25),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Dúvidas sobre intoxicação ou contato com produtos tóxicos.',
                      style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _teal),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: kCitPhoneDial)),
              icon: const Icon(Icons.call_rounded),
              label: const Text('Ligar $kCitPhoneDisplay'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Em sinais graves, como falta de ar, dor no peito ou desmaio, ligue 192 (SAMU).',
            style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
