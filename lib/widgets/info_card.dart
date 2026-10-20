import 'package:flutter/material.dart';

import '../data/pdf_content.dart';
import '../theme/app_theme.dart';
import '../screens/references_screen.dart';
import 'ui.dart';

/// Cartão educativo com as referências da fonte no rodapé.
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.data});
  final InfoCardData data;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, height: 1.3, color: AppColors.ink),
          ),
          for (final p in data.paragraphs) ...[
            const SizedBox(height: 10),
            Text(p, style: const TextStyle(height: 1.45, color: AppColors.ink)),
          ],
          if (data.bullets.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (data.bulletsTitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  data.bulletsTitle!,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brandDark),
                ),
              ),
            for (final b in data.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 10),
                      child: Icon(Icons.circle, size: 7, color: AppColors.brand),
                    ),
                    Expanded(child: Text(b, style: const TextStyle(height: 1.45, color: AppColors.ink))),
                  ],
                ),
              ),
          ],
          if (data.tip != null) ...[
            const SizedBox(height: 10),
            _Callout(
              icon: Icons.lightbulb_outline_rounded,
              color: const Color(0xFF2E7D32),
              text: data.tip!,
            ),
          ],
          if (data.warning != null) ...[
            const SizedBox(height: 10),
            _Callout(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFC62828),
              text: data.warning!,
            ),
          ],
          if (data.refs.isNotEmpty) ...[
            const SizedBox(height: 10),
            RefLine(refs: data.refs),
          ],
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(height: 1.4, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// "Referências: …" no fim de um cartão; toque abre a lista completa.
class RefLine extends StatelessWidget {
  const RefLine({super.key, required this.refs});
  final List<int> refs;

  @override
  Widget build(BuildContext context) {
    if (refs.isEmpty) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const ReferencesScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted),
            children: [
              const TextSpan(text: 'Referências: ', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: refs.map((r) => '[$r] ${referenceShort[r] ?? ''}').join('; ')),
            ],
          ),
        ),
      ),
    );
  }
}
