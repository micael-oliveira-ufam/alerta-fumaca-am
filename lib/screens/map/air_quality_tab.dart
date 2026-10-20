import 'package:flutter/material.dart';

import '../../data/pdf_content.dart';
import '../../services/air_quality_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'map_common.dart';

Color _categoryColor(AirCategory c) => switch (c) {
      AirCategory.good => const Color(0xFF2E7D32),
      AirCategory.moderate => const Color(0xFFB7791F),
      AirCategory.unhealthySensitive => const Color(0xFFEF6C00),
      AirCategory.unhealthy => const Color(0xFFC62828),
      AirCategory.veryUnhealthy => const Color(0xFF6A1B9A),
      AirCategory.hazardous => const Color(0xFF7B1B2B),
    };

/// Qualidade do ar estimada por modelo (CAMS via Open-Meteo) para sedes do Amazonas.
///
/// NÃO é o IQAr oficial: é uma estimativa de modelo de baixa resolução espacial.
class AirQualityTab extends StatefulWidget {
  const AirQualityTab({super.key});

  @override
  State<AirQualityTab> createState() => _AirQualityTabState();
}

class _AirQualityTabState extends State<AirQualityTab> {
  final _service = AirQualityService();
  late Future<List<AirReading>> _future = _service.fetch(amazonasAirPoints);

  Future<void> _reload() async {
    final next = _service.fetch(amazonasAirPoints);
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // O erro é exibido pelo FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AirReading>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState(message: 'Consultando a qualidade do ar estimada…');
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          return ErrorState(
            message: error is AirQualityException
                ? error.message
                : 'Não foi possível obter a qualidade do ar agora.',
            hint: 'Confira a internet do aparelho. Esta aba usa um serviço externo '
                '(Open-Meteo) e pode ficar indisponível.',
            details: '$error',
            onRetry: _reload,
          );
        }
        final readings = [...snapshot.data!]
          ..sort((a, b) => (b.usAqi ?? -1).compareTo(a.usAqi ?? -1));
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const _AirNotice(),
              const SizedBox(height: 12),
              if (readings.any((r) => (r.usAqi ?? 0) >= alertPurpleMinAqi)) ...[
                const _PurpleAlert(),
                const SizedBox(height: 12),
              ],
              for (final r in readings) ...[
                _AirCard(reading: r),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 4),
              const Text(
                'Dados: Open-Meteo.com, a partir do modelo CAMS (Copernicus Atmosphere '
                'Monitoring Service / ECMWF). Uso gratuito apenas para fins não comerciais. '
                'Índice: padrão dos EUA (0 a 500), calculado pelo Open-Meteo.',
                style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Alerta roxo (crítico), exibido quando alguma leitura chega a [alertPurpleMinAqi].
class _PurpleAlert extends StatelessWidget {
  const _PurpleAlert();

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF6A1B9A);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: purple,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_rounded, color: Colors.white),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '$alertPurpleTitle: $alertPurpleText',
              style: TextStyle(color: Colors.white, height: 1.4, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _AirNotice extends StatelessWidget {
  const _AirNotice();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      color: const Color(0xFFFFF8E1),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFB7791F)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Estimativa de modelo, não medição. Os valores vêm de um modelo de '
              'qualidade do ar de baixa resolução (dezenas de km) e podem diferir '
              'bastante do que se respira em um bairro. Não substitui o IQAr oficial '
              'dos órgãos ambientais (como o IPAAM). Na dúvida, siga os sintomas '
              'e as orientações de saúde.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _AirCard extends StatelessWidget {
  const _AirCard({required this.reading});
  final AirReading reading;

  @override
  Widget build(BuildContext context) {
    final aqi = reading.usAqi;
    final category = aqi == null ? null : airCategoryOf(aqi);
    final color = category == null ? AppColors.muted : _categoryColor(category);
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  aqi == null ? '—' : '$aqi',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
                ),
                Text('AQI', style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reading.point.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category?.label ?? 'Sem dado',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    'PM2,5: ${_fmt(reading.pm25)} µg/m³',
                    'PM10: ${_fmt(reading.pm10)} µg/m³',
                  ].join('  ·  '),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
                if (reading.time != null)
                  Text(
                    'Estimativa de ${formatDateTime(reading.time!)}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double? v) => v == null ? 'n/d' : v.toStringAsFixed(1).replaceAll('.', ',');
}
