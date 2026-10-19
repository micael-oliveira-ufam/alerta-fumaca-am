import 'package:flutter/material.dart';

import '../logic/risk_assessment.dart';
import '../logic/symptom_stats.dart';
import '../data/guidance_content.dart';
import '../services/answer_sync.dart';
import '../services/api_client.dart';
import '../services/report_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

const _periodDays = 30;

class _StatsData {
  const _StatsData({required this.snapshot, this.note});
  final StatsSnapshot snapshot;

  /// Aviso quando o servidor falhou e os números vêm só deste aparelho.
  final String? note;
}

/// Sintomas mais relatados: do servidor (todos os usuários) ou só deste aparelho.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _api = ApiClient();
  final _answers = LocalAnswerStore();
  final _consent = ConsentStore();
  late final AnswerSync _sync = AnswerSync(api: _api);

  late Future<_StatsData> _future = _load();
  bool _sendEnabled = false;
  bool _includeLocation = false;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _loadPrivacy();
  }

  Future<_StatsData> _load() async {
    String? note;
    if (_api.isConfigured) {
      try {
        await _sync.flush(); // entrega o que ficou pendente antes de ler os números
        final snapshot = await _api.fetchStats(days: _periodDays);
        return _StatsData(snapshot: snapshot);
      } on ApiException catch (e) {
        note = '${e.message} Mostrando só os dados deste aparelho.';
      }
    }
    final records = await _answers.all();
    return _StatsData(snapshot: computeLocalStats(records, days: _periodDays), note: note);
  }

  Future<void> _loadPrivacy() async {
    final decision = await _consent.sendDecision();
    final location = await _consent.includeLocationInSend();
    final pending = await _sync.pendingCount();
    if (!mounted) return;
    setState(() {
      _sendEnabled = decision ?? false;
      _includeLocation = location;
      _pending = pending;
    });
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sintomas mais relatados'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<_StatsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (data.note != null) ...[
                  AppCard(
                    color: const Color(0xFFFFF8E1),
                    child: Text(
                      data.note!,
                      style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _Overview(snapshot: data.snapshot),
                const SizedBox(height: 16),
                if (data.snapshot.sufficient) ...[
                  const SectionTitle('SINTOMAS MAIS RELATADOS'),
                  AppCard(
                    child: Column(
                      children: [
                        for (final s in data.snapshot.symptoms) _SymptomRow(stat: s),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Relato = sintoma com intensidade leve ou maior. O percentual é sobre o '
                    'total de respostas do período. Os números descrevem quem usa o app e '
                    'não representam toda a população.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
                  ),
                ],
                if (_api.isConfigured) ...[
                  const SizedBox(height: 20),
                  _PrivacySection(
                    sendEnabled: _sendEnabled,
                    includeLocation: _includeLocation,
                    pending: _pending,
                    onSendChanged: (v) async {
                      await _consent.setSendDecision(v);
                      if (!v) await _consent.setIncludeLocationInSend(false);
                      await _loadPrivacy();
                    },
                    onLocationChanged: (v) async {
                      await _consent.setIncludeLocationInSend(v);
                      await _loadPrivacy();
                    },
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.snapshot});
  final StatsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final fromServer = snapshot.source == StatsSource.server;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${snapshot.totalResponses}',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Pill(
                label: fromServer ? 'Todos os usuários' : 'Somente este aparelho',
                color: fromServer ? AppColors.brand : const Color(0xFF1565C0),
              ),
            ],
          ),
          Text(
            'resposta(s) nos últimos ${snapshot.periodDays} dias',
            style: const TextStyle(color: AppColors.muted),
          ),
          if (!snapshot.sufficient) ...[
            const SizedBox(height: 12),
            Text(
              snapshot.totalResponses == 0
                  ? 'Ainda não há respostas. Preencha o questionário "Como estou me sentindo" '
                      'para começar.'
                  : 'Há poucas respostas para divulgar os detalhes (mínimo de '
                      '${snapshot.minimumToDisclose}). Isso protege a privacidade de quem respondeu.',
              style: const TextStyle(height: 1.4, color: AppColors.ink),
            ),
          ] else ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final level in RiskLevel.values)
                  Pill(
                    label: '${_levelShort(level)} ${snapshot.levels[level.name] ?? 0}',
                    color: levelColor(level),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _levelShort(RiskLevel l) => switch (l) {
        RiskLevel.low => 'Baixo',
        RiskLevel.moderate => 'Moderado',
        RiskLevel.high => 'Alto',
        RiskLevel.emergency => 'Emergência',
      };
}

class _SymptomRow extends StatelessWidget {
  const _SymptomRow({required this.stat});
  final SymptomStat stat;

  static final _labels = {for (final i in symptomItems) i.id: i.label};

  @override
  Widget build(BuildContext context) {
    final mean = stat.meanSeverity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _labels[stat.id] ?? stat.id,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
              ),
              Text(
                '${stat.reports} · ${_pct(stat.percent)}%',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (stat.percent / 100).clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            mean == null
                ? 'Sem relatos no período'
                : '${severityLabels[1]} ${stat.mild} · ${severityLabels[2]} ${stat.moderate} · '
                    '${severityLabels[3]} ${stat.intense} · gravidade média '
                    '${mean.toStringAsFixed(1).replaceAll('.', ',')} de 3',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  static String _pct(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({
    required this.sendEnabled,
    required this.includeLocation,
    required this.pending,
    required this.onSendChanged,
    required this.onLocationChanged,
  });

  final bool sendEnabled;
  final bool includeLocation;
  final int pending;
  final ValueChanged<bool> onSendChanged;
  final ValueChanged<bool> onLocationChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('PRIVACIDADE E ENVIO'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: const Text('Enviar minhas respostas, sem identificação'),
                subtitle: const Text('Sintomas, perfil e nível de risco (dados de saúde).'),
                value: sendEnabled,
                onChanged: onSendChanged,
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: const Text('Incluir localização aproximada (~1 km)'),
                value: includeLocation,
                onChanged: sendEnabled ? onLocationChanged : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            'O servidor do projeto não guarda nome, telefone, e-mail, IP nem identificador do aparelho.',
            'Como os registros não têm identificação, não é possível apagar depois um envio específico.',
            if (pending > 0) 'Há $pending envio(s) aguardando conexão.',
          ].join(' '),
          style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
        ),
      ],
    );
  }
}
