import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../logic/map_layers.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Centro do Amazonas, com zoom que mostra o estado inteiro.
const amazonasCenter = LatLng(-4.0, -63.0);

/// Centro aproximado do Brasil, para o zoom que mostra o país inteiro.
const brasilCenter = LatLng(-14.0, -52.0);

/// Centro de Manaus, usado como referência do mapa comunitário.
const manausCenter = LatLng(-3.1190, -60.0217);

/// Mapa base gratuito (OpenStreetMap), sem chave de API.
const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const mapUserAgent = 'br.ufam.alertafumaca';

String twoDigits(int n) => n.toString().padLeft(2, '0');

/// "19/10 às 18:45" no horário local do aparelho.
String formatDateTime(DateTime d) {
  final l = d.toLocal();
  return '${twoDigits(l.day)}/${twoDigits(l.month)} às ${twoDigits(l.hour)}:${twoDigits(l.minute)}';
}

/// Chave de uma camada extra que a aba controla (por exemplo, "Focos do INPE").
class LayerToggle {
  const LayerToggle({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
}

/// Mapa base com camadas de círculos e marcadores e ferramentas de navegação.
///
/// - Rotação DESATIVADA: o gesto de pinça só aplica zoom e o norte fica sempre no topo.
/// - Botões circulares: aproximar, afastar, minha localização, voltar à região e camadas.
/// - Camadas: mapa base (ruas ou satélite NASA) e sobreposições (fumaça/aerossóis e
///   focos de calor da NASA), além das chaves [toggles] fornecidas pela aba.
/// - Se os tiles não baixarem, mostra um aviso com o erro técnico.
class BaseMap extends StatefulWidget {
  const BaseMap({
    super.key,
    required this.center,
    required this.zoom,
    required this.circles,
    this.markers = const [],
    this.controller,
    this.onReady,
    this.bannerTop = 12,
    this.toggles = const [],
    this.onLocate,
  });

  final LatLng center;
  final double zoom;
  final List<CircleMarker> circles;
  final List<Marker> markers;
  final MapController? controller;
  final VoidCallback? onReady;

  /// Distância do topo do aviso de falha do mapa base (para não sobrepor outros avisos).
  final double bannerTop;

  /// Camadas extras controladas pela aba, mostradas no painel "Camadas".
  final List<LayerToggle> toggles;

  /// Se informado, substitui o comportamento do botão "minha localização".
  final VoidCallback? onLocate;

  @override
  State<BaseMap> createState() => _BaseMapState();
}

enum _BaseLayer { streets, satellite }

class _BaseMapState extends State<BaseMap> {
  late final MapController _controller = widget.controller ?? MapController();
  final _location = LocationService();

  bool _ready = false;
  bool _locating = false;
  String? _tileError;
  LatLng? _myPoint;

  _BaseLayer _base = _BaseLayer.streets;
  final Set<String> _overlays = {};
  int _daysBack = 1;

  /// Camadas da NASA que já falharam (avisadas uma vez só).
  final Set<String> _failedLayers = {};

  static const _minZoom = 3.0;
  static const _maxZoom = 18.0;

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (_tileError != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tileError != null) return;
      setState(() => _tileError = '$error');
    });
  }

  void _gibsTileError(GibsLayer layer, TileImage tile, Object error, StackTrace? st) {
    if (_failedLayers.contains(layer.id)) return;
    _failedLayers.add(layer.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          content: Text(
            'A camada "${layer.label}" não carregou para ${gibsDate(DateTime.now(), daysBack: _daysBack)}. '
            'Tente outro dia no painel de camadas ou verifique a internet. '
            'Detalhe técnico: $error',
          ),
        ),
      );
    });
  }

  void _zoomBy(double delta) {
    if (!_ready) return;
    final camera = _controller.camera;
    final next = (camera.zoom + delta).clamp(_minZoom, _maxZoom).toDouble();
    _controller.move(camera.center, next);
  }

  void _goHome() {
    if (!_ready) return;
    _controller.move(widget.center, widget.zoom);
  }

  Future<void> _locate() async {
    final custom = widget.onLocate;
    if (custom != null) {
      custom();
      return;
    }
    if (_locating) return;
    setState(() => _locating = true);
    final outcome = await _location.requestAndGetPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    final position = outcome.position;
    if (outcome.status == LocationStatus.ok && position != null) {
      final point = LatLng(position.latitude, position.longitude);
      setState(() => _myPoint = point);
      if (_ready) _controller.move(point, 11);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(switch (outcome.status) {
          LocationStatus.serviceDisabled =>
            'O GPS está desligado. Ative a localização do aparelho.',
          LocationStatus.denied => 'Permissão de localização negada.',
          LocationStatus.deniedForever =>
            'A permissão de localização está bloqueada. Libere-a nas configurações do aparelho.',
          LocationStatus.permissionNotDeclared =>
            'O app foi compilado sem a permissão de localização. Rode tool/apply_platform_config.py e reinstale.',
          _ => 'Não foi possível obter sua localização agora.',
        }),
      ),
    );
  }

  bool get _anyLayerOn =>
      _base != _BaseLayer.streets ||
      _overlays.isNotEmpty ||
      widget.toggles.any((t) => t.value);

  void _openLayers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          void update(VoidCallback change) {
            setState(change);
            setSheet(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const Text(
                    'Camadas do mapa',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                  const SectionTitle('MAPA DE FUNDO'),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<_BaseLayer>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: _BaseLayer.streets,
                          icon: Icon(Icons.map_outlined),
                          label: Text('Ruas'),
                        ),
                        ButtonSegment(
                          value: _BaseLayer.satellite,
                          icon: Icon(Icons.satellite_alt_rounded),
                          label: Text('Satélite'),
                        ),
                      ],
                      selected: {_base},
                      onSelectionChanged: (s) => update(() => _base = s.first),
                    ),
                  ),
                  if (_base == _BaseLayer.satellite)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        gibsTrueColor.description,
                        style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.muted),
                      ),
                    ),
                  if (widget.toggles.isNotEmpty) ...[
                    const SectionTitle('DADOS DESTA TELA'),
                    for (final t in widget.toggles)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(t.icon, color: AppColors.brandDark),
                        title: Text(t.label),
                        subtitle: t.subtitle == null ? null : Text(t.subtitle!),
                        value: t.value,
                        onChanged: (v) {
                          t.onChanged(v);
                          setSheet(() {});
                        },
                      ),
                  ],
                  const SectionTitle('IMAGENS DE SATÉLITE (NASA GIBS)'),
                  for (final layer in gibsOverlays)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        layer == gibsAerosol
                            ? Icons.cloud_rounded
                            : Icons.local_fire_department_rounded,
                        color: AppColors.brandDark,
                      ),
                      title: Text(layer.label),
                      subtitle: Text(layer.description),
                      value: _overlays.contains(layer.id),
                      onChanged: (v) => update(() {
                        if (v) {
                          _overlays.add(layer.id);
                          _failedLayers.remove(layer.id);
                        } else {
                          _overlays.remove(layer.id);
                        }
                      }),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Data da imagem de satélite',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                        ),
                      ),
                      RoundIconButton(
                        icon: Icons.chevron_left_rounded,
                        tooltip: 'Dia anterior',
                        size: 40,
                        onPressed: _daysBack >= 7
                            ? null
                            : () => update(() {
                                  _daysBack++;
                                  _failedLayers.clear();
                                }),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          gibsDate(DateTime.now(), daysBack: _daysBack),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      RoundIconButton(
                        icon: Icons.chevron_right_rounded,
                        tooltip: 'Próximo dia',
                        size: 40,
                        onPressed: _daysBack <= 0
                            ? null
                            : () => update(() {
                                  _daysBack--;
                                  _failedLayers.clear();
                                }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'As imagens da NASA têm atraso de horas e dependem de nuvens e da '
                    'passagem do satélite; a data é em UTC. Servem para ter uma ideia da '
                    'extensão da fumaça, não para medir a qualidade do ar. Se uma camada '
                    'ficar em branco, teste outro dia.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  TileLayer _gibsTileLayer(GibsLayer layer, String date) => TileLayer(
        key: ValueKey('${layer.id}-$date'),
        urlTemplate: layer.urlTemplate(date),
        userAgentPackageName: mapUserAgent,
        maxNativeZoom: layer.maxNativeZoom,
        errorTileCallback: (tile, error, st) => _gibsTileError(layer, tile, error, st),
      );

  @override
  Widget build(BuildContext context) {
    final date = gibsDate(DateTime.now().toUtc(), daysBack: _daysBack);
    final controlsTop = widget.bannerTop + (_tileError != null ? 100 : 0);
    final markers = [
      ...widget.markers,
      if (_myPoint != null && widget.onLocate == null) userMarker(_myPoint!),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            // Tudo habilitado, exceto rotação: com ela, o zoom por pinça girava o mapa.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _ready = true;
              widget.onReady?.call();
            },
          ),
          children: [
            if (_base == _BaseLayer.satellite)
              _gibsTileLayer(gibsTrueColor, date)
            else
              TileLayer(
                urlTemplate: tileUrl,
                userAgentPackageName: mapUserAgent,
                errorTileCallback: _onTileError,
              ),
            for (final layer in gibsOverlays)
              if (_overlays.contains(layer.id))
                Opacity(opacity: layer.opacity, child: _gibsTileLayer(layer, date)),
            CircleLayer(circles: widget.circles),
            if (markers.isNotEmpty) MarkerLayer(markers: markers),
            _ScaleBar(top: controlsTop + 4),
            SimpleAttributionWidget(
              source: Text(
                [
                  if (_base == _BaseLayer.streets) '© OpenStreetMap contributors',
                  if (_base == _BaseLayer.satellite || _overlays.isNotEmpty)
                    'Imagens: NASA GIBS/EOSDIS',
                ].join(' · '),
              ),
            ),
          ],
        ),
        Positioned(
          right: 12,
          top: controlsTop,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RoundIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Aproximar',
                onPressed: () => _zoomBy(1),
              ),
              const SizedBox(height: 10),
              RoundIconButton(
                icon: Icons.remove_rounded,
                tooltip: 'Afastar',
                onPressed: () => _zoomBy(-1),
              ),
              const SizedBox(height: 10),
              RoundIconButton(
                icon: _locating ? Icons.hourglass_top_rounded : Icons.my_location_rounded,
                tooltip: 'Minha localização',
                onPressed: _locating ? null : _locate,
              ),
              const SizedBox(height: 10),
              RoundIconButton(
                icon: Icons.zoom_out_map_rounded,
                tooltip: 'Voltar à visão inicial',
                onPressed: _goHome,
              ),
              const SizedBox(height: 10),
              RoundIconButton(
                icon: Icons.layers_rounded,
                tooltip: 'Camadas',
                active: _anyLayerOn,
                onPressed: _openLayers,
              ),
            ],
          ),
        ),
        if (_tileError != null)
          Positioned(
            left: 12,
            right: 72,
            top: widget.bannerTop,
            child: AppCard(
              color: const Color(0xFFFFEBEE),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.map_outlined, color: Color(0xFFC62828)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Não foi possível baixar o mapa base (OpenStreetMap). '
                      'Verifique a internet. Se o app foi instalado em modo release, '
                      'confirme a permissão INTERNET no AndroidManifest.xml '
                      '(use tool/apply_platform_config.py).\n'
                      'Detalhe técnico: $_tileError',
                      style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Barra de escala (metros ou km) no canto superior esquerdo.
class _ScaleBar extends StatelessWidget {
  const _ScaleBar({required this.top});
  final double top;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final perPixel = metersPerPixel(camera.center.latitude, camera.zoom);
    const maxWidth = 100.0;
    final meters = niceScaleMeters(perPixel * maxWidth);
    final width = perPixel == 0 ? 0.0 : meters / perPixel;
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 12, top: top + 56), // abaixo dos avisos
        child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(scaleLabel(meters), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              Container(
                width: width,
                height: 4,
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(width: 2),
                    right: BorderSide(width: 2),
                    bottom: BorderSide(width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Marcador azul da posição do usuário ("você está aqui").
Marker userMarker(LatLng point) => Marker(
      point: point,
      width: 28,
      height: 28,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1565C0),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
        ),
      ),
    );

/// Marcador com o nome da cidade, para o mapa ter referência mesmo sem dados.
Marker cityMarker(String name, LatLng point) => Marker(
      point: point,
      width: 120,
      height: 56,
      child: CityLabel(name: name),
    );

class CityLabel extends StatelessWidget {
  const CityLabel({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.brandDark),
          ),
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.brandDark,
            ),
          ),
        ),
        const Icon(Icons.location_on_rounded, color: AppColors.brandDark, size: 28),
      ],
    );
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.ink)),
      ],
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado de erro com mensagem, dica e detalhes técnicos recolhidos.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    required this.hint,
    required this.details,
    required this.onRetry,
  });

  final String message;
  final String hint;
  final String details;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.muted),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 10),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'Detalhes técnicos',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          children: [
            Text(details, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
      ],
    );
  }
}
