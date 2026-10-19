import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

/// Mapa base com camadas de círculos e marcadores.
///
/// Se os tiles não baixarem, mostra um aviso com o erro técnico: sem isso, a falha de
/// rede aparece apenas como um mapa em branco.
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
  });

  final LatLng center;
  final double zoom;
  final List<CircleMarker> circles;
  final List<Marker> markers;
  final MapController? controller;
  final VoidCallback? onReady;

  /// Distância do topo do aviso de falha do mapa base (para não sobrepor outros avisos).
  final double bannerTop;

  @override
  State<BaseMap> createState() => _BaseMapState();
}

class _BaseMapState extends State<BaseMap> {
  String? _tileError;

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (_tileError != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tileError != null) return;
      setState(() => _tileError = '$error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: widget.controller,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            onMapReady: widget.onReady,
          ),
          children: [
            TileLayer(
              urlTemplate: tileUrl,
              userAgentPackageName: mapUserAgent,
              errorTileCallback: _onTileError,
            ),
            CircleLayer(circles: widget.circles),
            if (widget.markers.isNotEmpty) MarkerLayer(markers: widget.markers),
            const SimpleAttributionWidget(source: Text('© OpenStreetMap contributors')),
          ],
        ),
        if (_tileError != null)
          Positioned(
            left: 12,
            right: 12,
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
