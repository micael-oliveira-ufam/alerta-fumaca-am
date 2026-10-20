import 'package:flutter/material.dart';

import '../data/guidance_content.dart';
import '../logic/risk_assessment.dart';
import '../theme/app_theme.dart';
import '../widgets/cit_card.dart';
import '../widgets/emergency_banner.dart';
import '../widgets/ui.dart';

class GuidanceScreen extends StatelessWidget {
  const GuidanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('O que fazer'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const EmergencyBanner(),
          const SizedBox(height: 12),
          const CitCard(),
          const SizedBox(height: 16),
          const SectionTitle('ORIENTAÇÕES POR NÍVEL DE RISCO'),
          for (final level in [RiskLevel.low, RiskLevel.moderate, RiskLevel.high])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _LevelCard(level: level),
            ),
          const SizedBox(height: 8),
          const Text(
            kDisclaimer,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level});
  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    final color = levelColor(level);
    final actions = levelActions[level]!;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          title: Text(
            levelLabel(level),
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          initiallyExpanded: level == RiskLevel.moderate,
          children: [
            for (final action in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 18, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(action,
                          style: const TextStyle(height: 1.4, color: AppColors.ink)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
