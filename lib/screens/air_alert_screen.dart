import 'dart:io';

import 'package:flutter/material.dart';

import '../logic/air_alert.dart';
import '../services/air_alert_background.dart';
import '../services/air_alert_service.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Configuração dos alertas de qualidade do ar (notificações do Android).
class AirAlertScreen extends StatefulWidget {
  const AirAlertScreen({super.key});

  @override
  State<AirAlertScreen> createState() => _AirAlertScreenState();
}

class _AirAlertScreenState extends State<AirAlertScreen> {
  final _store = AirAlertStore();
  final _api = ApiClient(timeout: const Duration(seconds: 15));

  AirAlertSettings _settings = const AirAlertSettings();
  List<({int code, String name})> _municipalities = const [];
  bool _loading = true;
  bool _checking = false;
  String? _message;
  AirAlertReading? _reading;

  bool get _supported => Platform.isAndroid;

  static const _thresholdLabels = {
    51: 'Moderada (a partir de 51)',
    101: 'Ruim para grupos sensíveis (a partir de 101)',
    151: 'Ruim (a partir de 151)',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _store.loadSettings();
    List<({int code, String name})> municipalities = const [];
    if (_api.isConfigured) {
      try {
        municipalities = await _api.fetchAirMunicipalities();
      } catch (_) {
        municipalities = const [];
      }
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _municipalities = municipalities;
      _loading = false;
    });
  }

  Future<void> _save(AirAlertSettings next) async {
    setState(() => _settings = next);
    await _store.saveSettings(next);
    await AirAlertBackground.sync(enabled: next.enabled);
  }

  Future<void> _toggle(bool on) async {
    if (on) {
      final granted = await AirAlertNotifier.requestPermission();
      if (!granted) {
        if (!mounted) return;
        setState(() => _message =
            'Sem a permissão de notificações o Android não mostra os alertas. Autorize em Configurações > Apps > RespirAR Amazonas > Notificações.');
        return;
      }
    }
    setState(() => _message = null);
    await _save(_settings.copyWith(enabled: on));
    if (on) await _checkNow();
  }

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    final result = await AirAlertService(api: _api).check(force: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _reading = result.reading ?? _reading;
      _message = result.error ?? _describe(result);
    });
  }

  String? _describe(AirCheckResult r) {
    final reading = r.reading;
    if (reading == null) return null;
    final aqi = reading.usAqi;
    if (aqi == null) return 'O modelo não trouxe índice para ${reading.municipalityName} agora.';
    final over = aqi >= _settings.threshold;
    return over
        ? (_settings.enabled && r.action == AlertAction.notify
            ? 'Índice $aqi: o alerta foi enviado.'
            : 'Índice $aqi, acima do limite escolhido.')
        : 'Índice $aqi, abaixo do limite escolhido: nenhum alerta agora.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas de qualidade do ar'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (!_supported)
                  const AppCard(
                    color: Color(0xFFFFF8E1),
                    child: Text(
                      'Os alertas por notificação estão disponíveis apenas no Android por enquanto.',
                      style: TextStyle(height: 1.4, color: AppColors.ink),
                    ),
                  ),
                if (!_api.isConfigured)
                  const AppCard(
                    color: Color(0xFFFFF8E1),
                    child: Text(
                      'Os alertas usam o servidor do projeto. Configure o endereço em "Sobre o app".',
                      style: TextStyle(height: 1.4, color: AppColors.ink),
                    ),
                  ),
                AppCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Avisar quando o ar piorar', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Notificação quando o índice de ${_settings.municipalityName} passar do limite.'),
                    value: _settings.enabled,
                    onChanged: _supported && _api.isConfigured ? _toggle : null,
                  ),
                ),
                const SizedBox(height: 12),
                const SectionTitle('LOCAL'),
                AppCard(
                  child: _municipalities.isEmpty
                      ? Text(
                          'Município: ${_settings.municipalityName}. A lista de municípios aparece quando o app '
                          'consegue falar com o servidor.',
                          style: const TextStyle(height: 1.4, color: AppColors.ink),
                        )
                      : DropdownButtonFormField<int>(
                          initialValue: _municipalities.any((m) => m.code == _settings.municipalityCode)
                              ? _settings.municipalityCode
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Município', border: OutlineInputBorder()),
                          items: [
                            for (final m in _municipalities) DropdownMenuItem(value: m.code, child: Text(m.name)),
                          ],
                          onChanged: (code) {
                            if (code == null) return;
                            final m = _municipalities.firstWhere((m) => m.code == code);
                            _save(_settings.copyWith(municipalityCode: m.code, municipalityName: m.name));
                          },
                        ),
                ),
                const SizedBox(height: 12),
                const SectionTitle('QUANDO AVISAR'),
                AppCard(
                  child: Column(
                    children: [
                      for (final t in kAlertThresholds)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _settings.threshold == t
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: AppColors.brand,
                          ),
                          title: Text(_thresholdLabels[t]!),
                          onTap: () => _save(_settings.copyWith(threshold: t)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _checking || !_api.isConfigured ? null : _checkNow,
                  icon: const Icon(Icons.air_rounded),
                  label: Text(_checking ? 'Verificando…' : 'Verificar agora'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  AppCard(
                    child: Text(_message!, style: const TextStyle(height: 1.4, color: AppColors.ink)),
                  ),
                ],
                if (_reading?.usAqi != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_reading!.municipalityName}: índice ${_reading!.usAqi}'
                    '${_reading!.pm25 == null ? '' : ' · PM2,5 ${_reading!.pm25!.toStringAsFixed(1).replaceAll('.', ',')} µg/m³'}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Como funciona: o app confere o índice a cada cerca de 1 hora em segundo plano e também ao '
                  'ser aberto. O Android (e a economia de bateria do fabricante) pode atrasar essas checagens, '
                  'então o aviso pode chegar depois da piora. O índice é uma ESTIMATIVA de modelo (CAMS, '
                  'Open-Meteo, escala US AQI, células de ~45 km), não uma medição de estação, e não substitui '
                  'boletins oficiais nem orientação de profissional de saúde. Um novo aviso só é enviado se a '
                  'faixa piorar ou depois de 12 horas com o índice ainda alto. Nada sobre você é enviado: '
                  'só o código do município consultado.',
                  style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.muted),
                ),
              ],
            ),
    );
  }
}
