import 'package:flutter/material.dart';

import '../data/guidance_content.dart';
import '../data/pdf_content.dart';
import '../theme/app_theme.dart';
import '../widgets/cit_card.dart';
import '../widgets/info_card.dart';
import '../widgets/ui.dart';

/// Tela genérica de cartões educativos (proteção, sintomas, farmácia caseira, pets).
class InfoScreen extends StatelessWidget {
  const InfoScreen({
    super.key,
    required this.title,
    required this.cards,
    this.intro,
    this.showCit = false,
  });

  final String title;
  final String? intro;
  final List<InfoCardData> cards;
  final bool showCit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (intro != null) ...[
            AppCard(
              color: const Color(0xFFFFF8E1),
              child: Text(intro!, style: const TextStyle(height: 1.45, color: AppColors.ink)),
            ),
            const SizedBox(height: 12),
          ],
          for (final c in cards) ...[
            InfoCard(data: c),
            const SizedBox(height: 12),
          ],
          if (showCit) const CitCard(),
          const SizedBox(height: 8),
          const Text(
            kDisclaimer,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// "Fato ou Fake?": mitos e verdades sobre a fumaça.
class MythsScreen extends StatelessWidget {
  const MythsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fato ou Fake?'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const AppCard(
            color: Color(0xFFFFF8E1),
            child: Text(
              'Em crises ambientais, receitas milagrosas circulam rápido nas redes. Veja o que '
              'dizem os textos da equipe e o quanto cada um foi conferido.',
              style: TextStyle(height: 1.45, color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 12),
          for (final m in myths) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Pill(
                    label: m.verdict ? 'FATO' : 'FAKE',
                    color: m.verdict ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                  ),
                  const SizedBox(height: 10),
                  Text(m.claim,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, height: 1.3, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  Text(m.explanation, style: const TextStyle(height: 1.45, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  VerificationBadge(verification: m.verification, note: m.note),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text(mythsReferenceNote,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted)),
        ],
      ),
    );
  }
}
