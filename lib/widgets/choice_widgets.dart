import 'package:flutter/material.dart';

import '../data/guidance_content.dart';
import '../theme/app_theme.dart';

/// Opção de uma linha de botões circulares.
class CircleOption<T> {
  const CircleOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final T value;
  final String label;
  final IconData icon;
  final Color color;
}

/// Linha de botões circulares de escolha única, com rótulo abaixo de cada um.
///
/// O botão selecionado fica preenchido; os demais, só com contorno. Tocar de novo no
/// selecionado não o desmarca (use uma opção "Não sei" quando a resposta for opcional).
class CircleChoiceRow<T> extends StatelessWidget {
  const CircleChoiceRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.diameter = 54,
  });

  final List<CircleOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final o in options)
          Expanded(
            child: _CircleChoice(
              label: o.label,
              icon: o.icon,
              color: o.color,
              selected: o.value == value,
              diameter: diameter,
              onTap: () => onChanged(o.value),
            ),
          ),
      ],
    );
  }
}

class _CircleChoice extends StatelessWidget {
  const _CircleChoice({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.diameter,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final double diameter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? color : Colors.white,
                  border: Border.all(color: color, width: selected ? 3 : 2),
                  boxShadow: selected
                      ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))]
                      : null,
                ),
                child: Icon(icon, color: selected ? Colors.white : color, size: diameter * 0.5),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.ink : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Intensidade de um sintoma em quatro botões circulares (0 a 3).
class SeverityPicker extends StatelessWidget {
  const SeverityPicker({super.key, required this.value, required this.answered, required this.onChanged});

  final int value;

  /// Enquanto a pessoa não tocou, nenhum botão aparece selecionado.
  final bool answered;
  final ValueChanged<int> onChanged;

  static const _colors = [
    Color(0xFF607D8B),
    Color(0xFF2E7D32),
    Color(0xFFB7791F),
    Color(0xFFC62828),
  ];
  static const _icons = [
    Icons.check_rounded,
    Icons.sentiment_satisfied_rounded,
    Icons.sentiment_neutral_rounded,
    Icons.sentiment_very_dissatisfied_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return CircleChoiceRow<int>(
      diameter: 48,
      value: answered ? value : null,
      onChanged: onChanged,
      options: [
        for (var s = 0; s <= 3; s++)
          CircleOption(value: s, label: severityLabels[s], icon: _icons[s], color: _colors[s]),
      ],
    );
  }
}

/// Sim / Não / Não sei em botões circulares. `null` = "Não sei" ou sem resposta.
class YesNoRow extends StatelessWidget {
  const YesNoRow({super.key, required this.value, required this.answered, required this.onChanged});

  final bool? value;

  /// `true` depois que a pessoa tocou em qualquer opção (inclusive "Não sei").
  final bool answered;
  final ValueChanged<bool?> onChanged;

  // O valor `null` não pode ser chave de seleção; usamos 0 = sim, 1 = não, 2 = não sei.
  int? get _selected => !answered ? null : (value == null ? 2 : (value! ? 0 : 1));

  @override
  Widget build(BuildContext context) {
    return CircleChoiceRow<int>(
      diameter: 48,
      value: _selected,
      onChanged: (i) => onChanged(switch (i) {
        0 => true,
        1 => false,
        _ => null,
      }),
      options: const [
        CircleOption(value: 0, label: 'Sim', icon: Icons.check_rounded, color: Color(0xFF2E7D32)),
        CircleOption(value: 1, label: 'Não', icon: Icons.close_rounded, color: Color(0xFFC62828)),
        CircleOption(value: 2, label: 'Não sei', icon: Icons.question_mark_rounded, color: Color(0xFF607D8B)),
      ],
    );
  }
}
