import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../logic/fire_stats.dart';
import '../../models/fire_hotspot.dart';
import '../../models/fire_satellite.dart';
import '../../services/inpe_fire_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rank_bars.dart';
import '../../widgets/ui.dart';
import 'map_common.dart';

/// Intervalo de atualização automática dos focos do INPE.
const _autoRefresh = Duration(minutes: 10);

/// Cores por intensidade de exibição dos focos (escala visual, não validada).
const _intensityColors = {
  FireIntensity.weak: Color(0xFFF9A825),
  FireIntensity.medium: Color(0xFFE65100),
  FireIntensity.strong: Color(0xFFB71C1C),
};

/// Cor das células agregadas do Brasil, por número de focos (escala visual).
Color _gridColor(int count) {
  if (count >= 50) return const Color(0xFF8E1B1B);
  if (count >= 10) return const Color(0xFFD84315);
  if (count >= 3) return const Color(0xFFF57C00);
  return const Color(0xFFFFB300);
}

/// Aba oficial: focos de calor do INPE por satélite (MODIS, NOAA-20, Suomi NPP),
/// com o Amazonas em destaque e visão do Brasil.
class OfficialFireTab extends StatefulWidget {
  const OfficialFireTab({super.key});

  @override
  State<OfficialFireTab> createState() => _OfficialFireTabState();
}

class _OfficialFireTabState extends State<OfficialFireTab> {
  final _service = InpeFireService(phoneDownload: true);
  FireScope _scope = FireScope.amazonas;
  FireWindow _window = FireWindow.today;
  Set<FireSatellite> _satellites = FireSatellite.defaults();
  bool _showHotspots = true;
  bool _showCells = true;
  late Future<FireResult> _future = _load();
  Timer? _timer;

  Future<FireResult> _load() =>
      _service.fetch(_window, scope: _scope, satellites: _satellites);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_autoRefresh, (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  void _changeScope(FireScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _future = _load();
    });
  }

  void _changeWindow(FireWindow window) {
    if (window == _window) return;
    setState(() {
      _window = window;
      _future = _load();
    });
  }

  void _toggleSatellite(FireSatellite satellite, bool selected) {
    final next = {..._satellites};
    if (selected) {
      next.add(satellite);
    } else {
      next.remove(satellite);
    }
    if (next.isEmpty) return; // pelo menos um satélite precisa ficar marcado
    setState(() {
      _satellites = next;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<FireScope>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                  segments: [
                    for (final s in FireScope.values)
                      ButtonSegment(value: s, label: Text(s.label)),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (s) => _changeScope(s.first),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<FireWindow>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                  segments: [
                    for (final w in FireWindow.values)
                      ButtonSegment(value: w, label: Text(w.label)),
                  ],
                  selected: {_window},
                  onSelectionChanged: (s) => _changeWindow(s.first),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final satellite in FireSatellite.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(satellite.shortLabel),
                          selected: _satellites.contains(satellite),
                          onSelected: (v) => _toggleSatellite(satellite, v),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<FireResult>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return LoadingState(
                  message: _scope == FireScope.brasil
                      ? 'Baixando os focos do Brasil. Pode levar alguns segundos.'
                      : null,
                );
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                return ErrorState(
                  message: error is InpeException
                      ? error.message
                      : 'Não foi possível carregar os focos de calor agora.',
                  hint: 'Confira se o aparelho está com internet. "Failed host lookup" também '
                      'aparece quando o app não tem a permissão INTERNET (comum em builds '
                      'de release): rode tool/apply_platform_config.py e reinstale. Se a '
                      'permissão estiver correta e o erro continuar, desative o "DNS privado" '
                      'do Android e tente de novo.',
                  details: '$error',
                  onRetry: _reload,
                );
              }
              return _OfficialContent(
                key: ValueKey('$_scope-$_window'),
                scope: _scope,
                window: _window,
                satellites: _satellites,
                showHotspots: _showHotspots,
                showCells: _showCells,
                onShowHotspots: (v) => setState(() => _showHotspots = v),
                onShowCells: (v) => setState(() => _showCells = v),
                result: snapshot.data!,
                onRefresh: _reload,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OfficialContent extends StatelessWidget {
  const _OfficialContent({
    super.key,
    required this.scope,
    required this.window,
    required this.satellites,
    required this.showHotspots,
    required this.showCells,
    required this.onShowHotspots,
    required this.onShowCells,
    required this.result,
    required this.onRefresh,
  });

  final FireScope scope;
  final FireWindow window;
  final Set<FireSatellite> satellites;
  final bool showHotspots;
  final bool showCells;
  final ValueChanged<bool> onShowHotspots;
  final ValueChanged<bool> onShowCells;
  final FireResult result;
  final VoidCallback onRefresh;

  CircleMarker _point(FireHotspot h, {required bool emphasized}) => CircleMarker(
        point: LatLng(h.lat, h.lon),
        radius: emphasized ? 5 : 4,
        useRadiusInMeter: false,
        color: _intensityColors[h.intensity]!.withValues(alpha: 0.9),
        borderColor: emphasized ? const Color(0xFF3E0A0A) : Colors.white,
        borderStrokeWidth: emphasized ? 1.2 : 0.6,
      );

  List<CircleMarker> _circles(List<FireHotspot> hotspots) {
    if (!showHotspots && !showCells) return const [];
    if (scope == FireScope.amazonas) {
      return showHotspots ? [for (final h in hotspots) _point(h, emphasized: false)] : const [];
    }
    // Brasil: os demais estados viram células de 0,5°; o Amazonas continua foco a foco.
    final others = hotspots.where((h) => h.state != InpeFireService.state);
    final amazonas = hotspots.where((h) => h.state == InpeFireService.state);
    return [
      if (showCells)
      for (final cell in aggregateGrid(others))
        CircleMarker(
          point: LatLng(cell.lat, cell.lon),
          radius: gridRadius(cell.count),
          useRadiusInMeter: false,
          color: _gridColor(cell.count).withValues(alpha: 0.55),
          borderColor: _gridColor(cell.count),
          borderStrokeWidth: 0.8,
        ),
      if (showHotspots)
        for (final h in amazonas) _point(h, emphasized: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hotspots = result.hotspots;
    final summary = FireSummary(hotspots);
    final isBrasil = scope == FireScope.brasil;

    final headline = isBrasil
        ? '${summary.total} foco(s) no Brasil · ${summary.amazonasCount} no Amazonas'
            '${summary.amazonasSharePercent == null ? '' : ' (${summary.amazonasSharePercent}%)'}'
        : summary.total == 0
            ? 'Nenhum foco no Amazonas (${window.label.toLowerCase()}).'
            : '${summary.total} foco(s) no Amazonas (${window.label.toLowerCase()}).';

    return Stack(
      children: [
        BaseMap(
          key: ValueKey('map-$scope'),
          center: isBrasil ? brasilCenter : amazonasCenter,
          zoom: isBrasil ? 3.6 : 5.2,
          circles: _circles(hotspots),
          bannerTop: result.fromCache ? 100 : 12,
          toggles: [
            LayerToggle(
              label: 'Focos de calor do INPE',
              subtitle: 'Pontos por satélite, coloridos pela intensidade (FRP)',
              icon: Icons.local_fire_department_rounded,
              value: showHotspots,
              onChanged: onShowHotspots,
            ),
            if (isBrasil)
              LayerToggle(
                label: 'Densidade nos outros estados',
                subtitle: 'Células de 0,5° com a contagem de focos',
                icon: Icons.grid_view_rounded,
                value: showCells,
                onChanged: onShowCells,
              ),
          ],
        ),
        if (result.fromCache)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: AppCard(
              color: const Color(0xFFFFF8E1),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, color: Color(0xFFB7791F)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sem conexão com os focos de calor. Mostrando dados salvos em '
                      '${formatDateTime(result.fetchedAt)}.',
                      style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final satellite in FireSatellite.values)
                      if (satellites.contains(satellite))
                        Pill(
                          label: '${satellite.shortLabel} ${summary.bySatellite[satellite] ?? 0}',
                          color: AppColors.brandDark,
                        ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    LegendDot(color: _intensityColors[FireIntensity.weak]!, label: 'Fraca'),
                    LegendDot(color: _intensityColors[FireIntensity.medium]!, label: 'Média'),
                    LegendDot(color: _intensityColors[FireIntensity.strong]!, label: 'Forte'),
                    if (isBrasil)
                      const LegendDot(color: Color(0xFFD84315), label: 'Células de 0,5° (outros estados)'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if (summary.lastDetection != null)
                      'Detecção mais recente: ${formatDateTime(summary.lastDetection!)}.',
                    'Consulta: ${formatDateTime(result.fetchedAt)}.',
                    'Fonte: INPE (Programa Queimadas). Focos indicam fogo detectado por '
                        'satélite, com atraso de passagem e processamento; não medem a '
                        'qualidade do ar. Atualização automática a cada 10 minutos.',
                  ].join(' '),
                  style: const TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.muted),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: hotspots.isEmpty
                            ? null
                            : () => _showDetails(context, summary),
                        icon: const Icon(Icons.bar_chart_rounded, size: 18),
                        label: const Text('Ver detalhes'),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Atualizar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showDetails(BuildContext context, FireSummary summary) {
    final isBrasil = scope == FireScope.brasil;
    final amazonasHotspots = summary.hotspots
        .where((h) => h.state == InpeFireService.state)
        .toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    const maxRows = 100;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (listContext, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${scope.label} · ${window.label}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.total} foco(s) dos satélites selecionados.',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SectionTitle('POR SATÉLITE'),
            RankBars(
              entries: [
                for (final satellite in FireSatellite.values)
                  if (satellites.contains(satellite))
                    MapEntry(satellite.label, summary.bySatellite[satellite] ?? 0),
              ],
            ),
            if (isBrasil) ...[
              const SectionTitle('ESTADOS COM MAIS FOCOS'),
              RankBars(
                entries: FireSummary.ranked(summary.byState, limit: 10),
                highlight: InpeFireService.state,
              ),
            ],
            if (summary.amazonasCount > 0) ...[
              const SectionTitle('MUNICÍPIOS DO AMAZONAS COM MAIS FOCOS'),
              RankBars(
                entries: FireSummary.ranked(summary.byMunicipalityAmazonas, limit: 10),
                color: const Color(0xFFB71C1C),
              ),
            ],
            const SectionTitle('POR BIOMA'),
            RankBars(entries: FireSummary.ranked(summary.byBiome, limit: 6)),
            if (amazonasHotspots.isNotEmpty) ...[
              SectionTitle(
                'FOCOS NO AMAZONAS · MAIS RECENTES'
                '${amazonasHotspots.length > maxRows ? ' (primeiros $maxRows)' : ''}',
              ),
              for (final h in amazonasHotspots.take(maxRows)) _HotspotTile(hotspot: h),
            ],
          ],
        ),
      ),
    );
  }
}

class _HotspotTile extends StatelessWidget {
  const _HotspotTile({required this.hotspot});
  final FireHotspot hotspot;

  @override
  Widget build(BuildContext context) {
    final h = hotspot;
    final color = _intensityColors[h.intensity]!;
    final details = [
      formatDateTime(h.detectedAt),
      h.family?.shortLabel ?? h.satellite,
      h.frp == null ? 'FRP n/d' : 'FRP ${h.frp!.toStringAsFixed(1)} MW',
      if (h.daysWithoutRain != null) '${h.daysWithoutRain} dia(s) sem chuva',
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(
        h.municipality.isEmpty ? 'Município não informado' : _titleCase(h.municipality),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(details, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    );
  }

  static String _titleCase(String s) => s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
