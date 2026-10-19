import 'package:flutter/material.dart';

import '../data/guidance_content.dart';
import '../logic/risk_assessment.dart';
import '../models/answer_record.dart';
import '../models/smoke_report.dart';
import '../services/answer_sync.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';
import '../services/report_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/emergency_banner.dart';
import '../widgets/ui.dart';

class QuestionnaireScreen extends StatefulWidget {
  const QuestionnaireScreen({super.key});

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final Map<String, int> _severities = {for (final i in symptomItems) i.id: 0};

  /// Sintomas que o usuário já respondeu (inclusive "Nenhum").
  final Set<String> _answered = {};

  Exposure _exposure = Exposure.under1h;
  bool _elderly = false;
  bool _pregnant = false;
  bool _child = false;
  bool _chronicResp = false;
  bool _chronicCard = false;

  RiskResult? _result;
  bool _sharing = false;

  final _repo = LocalReportRepository();
  final _consent = ConsentStore();
  final _location = LocationService();
  final _answers = LocalAnswerStore();
  final _sync = AnswerSync();

  /// Assinatura da última resposta registrada: evita registrar duas vezes a mesma
  /// resposta se a pessoa tocar em "Ver minha orientação" repetidamente.
  String? _lastSignature;

  double get _progress => _answered.length / symptomItems.length;

  Profile get _profile => Profile(
        elderly: _elderly,
        pregnant: _pregnant,
        child: _child,
        chronicRespiratory: _chronicResp,
        chronicCardiac: _chronicCard,
      );

  void _setSeverity(String id, int value) {
    setState(() {
      _severities[id] = value;
      _answered.add(id);
      _result = null;
    });
  }

  void _submit() {
    final result = assess(
      severities: Map.of(_severities),
      exposure: _exposure,
      profile: _profile,
    );
    setState(() => _result = result);
    // Leva o usuário ao resultado, que aparece abaixo do botão.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        _resultKey.currentContext ?? context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
    _registerAnswers(result);
  }

  final _resultKey = GlobalKey();

  /// Guarda a resposta neste aparelho (estatísticas locais) e, se o servidor estiver
  /// configurado e a pessoa consentiu, envia sem identificação.
  Future<void> _registerAnswers(RiskResult result) async {
    final severities = {for (final item in symptomItems) item.id: _severities[item.id] ?? 0};
    final exposure = _exposure;
    final profile = _profile;
    final signature = [
      for (final e in severities.entries) '${e.key}=${e.value}',
      exposure.name,
      profile.elderly,
      profile.pregnant,
      profile.child,
      profile.chronicRespiratory,
      profile.chronicCardiac,
    ].join(',');
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    final recordedAt = DateTime.now().toUtc();
    try {
      await _answers.save(AnswerRecord(
        timestamp: recordedAt,
        severities: severities,
        level: result.level,
        points: result.points,
      ));
    } catch (_) {
      // Falha ao salvar localmente não deve impedir a orientação.
    }

    if (!_sync.isConfigured) return; // modo local: nada é enviado
    await _sendToServer(
      result: result,
      severities: severities,
      exposure: exposure,
      profile: profile,
      recordedAt: recordedAt,
    );
  }

  Future<void> _sendToServer({
    required RiskResult result,
    required Map<String, int> severities,
    required Exposure exposure,
    required Profile profile,
    required DateTime recordedAt,
  }) async {
    final stored = await _consent.sendDecision();
    final bool send;
    if (stored != null) {
      send = stored;
    } else {
      if (!mounted) return;
      final choice = await _askSendConsent();
      if (choice == null) return; // fechou o diálogo: pergunta de novo no próximo envio
      send = choice.send;
      await _consent.setSendDecision(choice.send);
      await _consent.setIncludeLocationInSend(choice.send && choice.includeLocation);
    }
    if (!send) return;

    double? lat;
    double? lon;
    if (await _consent.includeLocationInSend()) {
      final located = await _location.requestAndGetPosition();
      final position = located.position;
      if (located.status == LocationStatus.ok && position != null) {
        lat = position.latitude;
        lon = position.longitude;
      }
      // Sem permissão ou sem GPS: o envio segue, apenas sem localização.
    }

    final payload = buildAnswerPayload(
      submissionId: newSubmissionId(),
      recordedAt: recordedAt,
      result: result,
      exposure: exposure,
      profile: profile,
      severities: severities,
      lat: lat,
      lon: lon,
    );
    final outcome = await _sync.send(payload);
    _snack(switch (outcome) {
      SyncResult.sent => 'Resposta registrada no servidor, sem identificação.',
      SyncResult.queued => 'Sem conexão: sua resposta será enviada quando possível.',
      SyncResult.rejected => 'O servidor não aceitou o envio desta resposta.',
      SyncResult.notConfigured => 'Servidor não configurado.',
    });
  }

  /// Consentimento específico para enviar dados de saúde ao servidor (LGPD).
  /// Retorna `null` se o diálogo for dispensado sem escolha.
  Future<({bool send, bool includeLocation})?> _askSendConsent() {
    var includeLocation = false;
    return showDialog<({bool send, bool includeLocation})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Ajudar a mapear a fumaça'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Se você concordar, o app enviará ao servidor do projeto cada resposta '
                  'do questionário: os sintomas e suas intensidades, o tempo de exposição, '
                  'seu perfil (por exemplo, gestante, idoso ou doença crônica) e o nível '
                  'de risco calculado. Esses são dados de saúde.\n\n'
                  'Não enviamos nome, telefone, e-mail nem identificador do aparelho, e o '
                  'banco de dados não guarda seu IP. Os dados servem para estatísticas e '
                  'para o mapa da comunidade, que só mostra áreas com várias respostas.\n\n'
                  'Como os registros não têm identificação, não será possível apagar um '
                  'envio específico depois. Em lugares pequenos, saúde somada à localização '
                  'pode permitir que alguém reconheça você; por isso a localização é opcional. '
                  'Você pode desativar o envio quando quiser em "Sintomas mais relatados". '
                  'Recusar não impede o uso do app.',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: includeLocation,
                  onChanged: (v) => setLocal(() => includeLocation = v ?? false),
                  title: const Text('Incluir minha localização aproximada (~1 km)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, (send: false, includeLocation: false)),
              child: const Text('Não enviar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (send: true, includeLocation: includeLocation)),
              child: const Text('Concordar e enviar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _askConsent() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Compartilhar localização'),
        content: const Text(
          'Para mapear áreas de risco, usaremos sua localização apenas no '
          'momento do envio. Ela será arredondada (~1 km) e salva sem '
          'identificação pessoal. Nesta versão, os registros ficam apenas '
          'neste aparelho. Você pode recusar e continuar usando o app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não permitir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Permitir'),
          ),
        ],
      ),
    );
    if (accepted == true) await _consent.setConsent(true);
    return accepted ?? false;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  Future<void> _share() async {
    final result = _result;
    if (result == null) return;

    setState(() => _sharing = true);
    try {
      final hasConsent = await _consent.hasConsent() || await _askConsent();
      if (!hasConsent) {
        _snack('Envio cancelado: permissão de localização não concedida.');
        return;
      }

      final pos = await _location.currentPosition();
      if (pos == null) {
        _snack('Não foi possível obter a localização. Verifique GPS e permissões.');
        return;
      }

      await _repo.save(SmokeReport(
        timestamp: DateTime.now().toUtc(),
        lat: SmokeReport.coarsen(pos.latitude),
        lon: SmokeReport.coarsen(pos.longitude),
        level: result.level,
        points: result.points,
      ));
      _snack('Registro anonimizado salvo neste aparelho.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = symptomItems.length - _answered.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Como você está'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  remaining == 0
                      ? 'Todos os sintomas respondidos'
                      : 'Respondidos: ${_answered.length} de ${symptomItems.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Marque a intensidade de cada sintoma que você sente agora.',
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final item in symptomItems) ...[
            _SymptomCard(
              item: item,
              value: _severities[item.id]!,
              onChanged: (v) => _setSeverity(item.id, v),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
          const SectionTitle('EXPOSIÇÃO AO AR LIVRE HOJE'),
          AppCard(
            child: SegmentedButton<Exposure>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Exposure.under1h, label: Text('< 1 h')),
                ButtonSegment(value: Exposure.between1and4h, label: Text('1–4 h')),
                ButtonSegment(value: Exposure.over4h, label: Text('> 4 h')),
              ],
              selected: {_exposure},
              onSelectionChanged: (s) => setState(() {
                _exposure = s.first;
                _result = null;
              }),
            ),
          ),
          const SizedBox(height: 18),
          const SectionTitle('SOBRE VOCÊ'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                _profileSwitch('Tenho 60 anos ou mais', _elderly, (v) => _elderly = v),
                _profileSwitch('Estou grávida', _pregnant, (v) => _pregnant = v),
                _profileSwitch('Sou criança (menos de 12 anos)', _child, (v) => _child = v),
                _profileSwitch('Asma, DPOC ou outra doença respiratória crônica', _chronicResp, (v) => _chronicResp = v),
                _profileSwitch('Doença cardíaca crônica', _chronicCard, (v) => _chronicCard = v),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.insights_rounded),
            label: const Text('Ver minha orientação'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 20),
            KeyedSubtree(
              key: _resultKey,
              child: _ResultCard(result: _result!),
            ),
            const SizedBox(height: 12),
            if (_result!.level == RiskLevel.emergency) ...[
              const EmergencyBanner(),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share_location_rounded),
              label: const Text('Compartilhar localização anonimizada'),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            kDisclaimer,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _profileSwitch(String label, bool value, void Function(bool) onChanged) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.ink)),
      value: value,
      onChanged: (v) => setState(() {
        onChanged(v);
        _result = null;
      }),
    );
  }
}

class _SymptomCard extends StatelessWidget {
  const _SymptomCard({required this.item, required this.value, required this.onChanged});

  final SymptomItem item;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = value == 0 ? AppColors.muted : levelColor(_levelFor(value));
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
              ),
              Text(
                severityLabels[value],
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              segments: [
                for (var s = 0; s <= 3; s++)
                  ButtonSegment<int>(
                    value: s,
                    label: Text(severityLabels[s], style: const TextStyle(fontSize: 12)),
                  ),
              ],
              selected: {value},
              onSelectionChanged: (set) => onChanged(set.first),
            ),
          ),
        ],
      ),
    );
  }

  /// Mapeia a severidade do sintoma para uma cor de destaque (apenas visual).
  static RiskLevel _levelFor(int severity) => switch (severity) {
        1 => RiskLevel.low,
        2 => RiskLevel.moderate,
        _ => RiskLevel.high,
      };
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final RiskResult result;

  @override
  Widget build(BuildContext context) {
    final color = levelColor(result.level);
    final consequences = result.consequences.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return AppCard(
      color: color.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  levelLabel(result.level),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              Pill(label: 'Pontos: ${result.points}', color: color),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Efeitos predominantes',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          if (consequences.isEmpty)
            const Text('Nenhum efeito predominante identificado.',
                style: TextStyle(color: AppColors.muted))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in consequences)
                  Pill(label: consequenceLabel(c), color: AppColors.brand),
              ],
            ),
          const SizedBox(height: 16),
          const Text('O que fazer agora',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          for (final a in levelActions[result.level]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.arrow_right_rounded, color: color),
                  Expanded(
                    child: Text(a, style: const TextStyle(height: 1.4, color: AppColors.ink)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
