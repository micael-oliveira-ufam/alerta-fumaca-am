import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../logic/community_map.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import '../../services/report_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'map_common.dart';

/// Dados do mapa da comunidade e de onde vieram.
class _CommunityData {
  const _CommunityData({required this.cells, required this.fromServer, this.note});
  final List<CommunityCell> cells;
  final bool fromServer;

  /// Aviso quando o servidor falhou e o mapa caiu para os dados deste aparelho.
  final String? note;
}

/// Aba coletiva: respostas anonimizadas.
///
/// - Com servidor (`API_BASE_URL`): áreas de TODOS os usuários, só com o mínimo de respostas.
/// - Sem servidor: apenas os registros deste aparelho.
class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  static const _hours = 72;
  final _repo = LocalReportRepository();
  final _api = ApiClient();
  late Future<_CommunityData> _future = _load();

  /// Controla o mapa para poder movê-lo quando a localização chegar.
  final _mapController = MapController();
  final _location = LocationService();
  bool _mapReady = false;
  bool _locating = false;

  /// Posição do usuário apenas em memória: não é salva nem enviada.
  LatLng? _userPoint;

  Future<_CommunityData> _load() async {
    String? note;
    if (_api.isConfigured) {
      try {
        final cells = await _api.fetchMap(hours: _hours);
        return _CommunityData(cells: cellsFromServer(cells), fromServer: true);
      } on ApiException catch (e) {
        note = '${e.message} Mostrando só os registros deste aparelho.';
      }
    }
    final reports = await _repo.recent(window: const Duration(hours: _hours));
    return _CommunityData(cells: aggregateReports(reports), fromServer: false, note: note);
  }

  @override
  void initState() {
    super.initState();
    // Pergunta a permissão logo após a primeira construção da tela.
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateMe());
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  /// Explica o motivo, pede a permissão e centraliza o mapa na posição obtida.
  Future<void> _locateMe() async {
    if (!mounted || _locating) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Centralizar o mapa em você'),
        content: const Text(
          'Para centralizar o mapa na sua região, o app precisa acessar sua '
          'localização. Ela é usada só para mostrar o mapa: não é enviada a '
          'nenhum servidor e não é salva. Se preferir, recuse e o mapa '
          'continua em Manaus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Permitir'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() => _locating = true);
    final outcome = await _location.requestAndGetPosition();
    if (!mounted) return;
    setState(() => _locating = false);

    final position = outcome.position;
    if (outcome.status == LocationStatus.ok && position != null) {
      final point = LatLng(position.latitude, position.longitude);
      setState(() => _userPoint = point);
      if (_mapReady) _mapController.move(point, 13);
      return;
    }
    final detail = outcome.detail;
    _snack(
      detail == null
          ? _locationMessage(outcome.status)
          : '${_locationMessage(outcome.status)}\nDetalhe técnico: $detail',
    );
  }

  void _onLocateTap() {
    final point = _userPoint;
    if (point != null && _mapReady) {
      _mapController.move(point, 13);
    } else {
      _locateMe();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        content: Text(msg),
      ),
    );
  }

  static String _locationMessage(LocationStatus s) => switch (s) {
        LocationStatus.serviceDisabled =>
          'O GPS está desligado. Ative a localização do aparelho para centralizar o mapa em você.',
        LocationStatus.denied => 'Permissão negada. O mapa continua em Manaus.',
        LocationStatus.deniedForever =>
          'A permissão de localização está bloqueada. Você pode liberá-la nas configurações do aparelho.',
        LocationStatus.permissionNotDeclared =>
          'O app foi compilado sem a permissão de localização no AndroidManifest.xml. '
              'Rode tool/apply_platform_config.py e reinstale o app.',
        _ => 'Não foi possível obter sua localização agora. O mapa continua em Manaus.',
      };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CommunityData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState();
        }
        final data = snapshot.data ??
            const _CommunityData(cells: [], fromServer: false);
        final cells = data.cells;
        final circles = [
          for (final c in cells)
            CircleMarker(
              point: LatLng(c.lat, c.lon),
              radius: 800,
              useRadiusInMeter: true,
              color: levelColor(c.worst).withValues(alpha: 0.35),
              borderColor: levelColor(c.worst),
              borderStrokeWidth: 2,
            ),
        ];
        // Enquanto não há localização, o mapa abre em Manaus (zoom 11).
        final center = _userPoint ?? manausCenter;
        final zoom = _userPoint == null ? 11.0 : 13.0;
        final total = cells.fold<int>(0, (sum, c) => sum + c.count);

        return Stack(
          children: [
            BaseMap(
              center: center,
              zoom: zoom,
              circles: circles,
              controller: _mapController,
              onReady: () => _mapReady = true,
              bannerTop: data.note == null ? 12 : 100,
              markers: [
                if (_userPoint != null) userMarker(_userPoint!),
                cityMarker('Manaus', manausCenter),
              ],
            ),
            if (data.note != null)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: AppCard(
                  color: const Color(0xFFFFF8E1),
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    data.note!,
                    style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.ink),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cells.isEmpty
                          ? (data.fromServer
                              ? 'Ainda não há áreas com respostas suficientes nas últimas $_hours horas.'
                              : 'Ainda não há notificações neste aparelho nas últimas $_hours horas.')
                          : '$total resposta(s) em ${cells.length} área(s) nas últimas $_hours horas.',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                    const SizedBox(height: 10),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        LegendDot(color: Color(0xFF2E7D32), label: 'Baixo'),
                        LegendDot(color: Color(0xFFB7791F), label: 'Moderado'),
                        LegendDot(color: Color(0xFFE65100), label: 'Alto'),
                        LegendDot(color: Color(0xFFC62828), label: 'Emergência'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      data.fromServer
                          ? 'Respostas de usuários do app, agrupadas em áreas de ~1 km, sem '
                              'identificação. Só aparecem áreas com várias respostas, para '
                              'não expor uma pessoa isolada.'
                          : 'Registros arredondados para ~1 km e sem identificação. '
                              'Neste modo, ficam apenas neste aparelho.',
                      style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _locating ? null : _onLocateTap,
                            icon: const Icon(Icons.my_location_rounded, size: 18),
                            label: Text(
                              _locating
                                  ? 'Localizando…'
                                  : _userPoint == null
                                      ? 'Minha localização'
                                      : 'Centralizar em mim',
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _reload(),
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
      },
    );
  }
}
