import 'package:flutter/material.dart';

import '../data/pdf_content.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Cartão educativo com selo de verificação e nota de honestidade sobre a fonte.
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
          const SizedBox(height: 12),
          VerificationBadge(
            verification: data.verification,
            note: data.verificationNote,
            refs: data.refs,
          ),
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

/// Selo "Conferido / Parcialmente / Texto da equipe" com a nota expansível.
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({super.key, required this.verification, this.note, this.refs = const []});
  final Verification verification;
  final String? note;
  final List<int> refs;

  Color get _color => switch (verification) {
        Verification.checked => const Color(0xFF2E7D32),
        Verification.partial => const Color(0xFFB7791F),
        Verification.teamText => const Color(0xFF8A5A00),
      };

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        title: Align(
          alignment: Alignment.centerLeft,
          child: Pill(label: verification.label, color: _color),
        ),
        children: [
          if (note != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(note!, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted)),
            ),
          if (refs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Fontes na tela Referências: ${refs.map((r) => '[$r]').join(' ')}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
