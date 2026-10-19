import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Barras horizontais simples para rankings (sem biblioteca de gráficos).
///
/// O comprimento de cada barra é proporcional ao valor, tomando o maior como 100 %.
class RankBars extends StatelessWidget {
  const RankBars({
    super.key,
    required this.entries,
    this.highlight,
    this.color = AppColors.brand,
    this.highlightColor = const Color(0xFFB71C1C),
    this.valueSuffix = '',
  });

  final List<MapEntry<String, int>> entries;

  /// Rótulo destacado (ex.: "AMAZONAS").
  final String? highlight;
  final Color color;
  final Color highlightColor;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text('Sem dados.', style: TextStyle(color: AppColors.muted));
    }
    final maxValue = entries.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _row(e, maxValue),
          ),
      ],
    );
  }

  Widget _row(MapEntry<String, int> e, int maxValue) {
    final isHighlight = e.key == highlight;
    final barColor = isHighlight ? highlightColor : color;
    final fraction = maxValue == 0 ? 0.0 : e.value / maxValue;
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(
            _titleCase(e.key),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w500,
              color: isHighlight ? highlightColor : AppColors.ink,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: Stack(
            children: [
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          child: Text(
            '${e.value}$valueSuffix',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
        ),
      ],
    );
  }

  /// "SÃO PAULO" -> "São Paulo". Só altera rótulos totalmente em maiúsculas (vindos do INPE).
  static String _titleCase(String s) {
    if (s != s.toUpperCase()) return s;
    return s
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
