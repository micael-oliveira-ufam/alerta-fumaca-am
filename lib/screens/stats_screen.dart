import 'package:flutter/material.dart';

import '../logic/risk_assessment.dart';
import '../logic/symptom_stats.dart';
import '../data/guidance_content.dart';
import '../services/answer_sync.dart';
import '../services/api_client.dart';
import '../services/report_repository.dart';
import '../services/stats_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

const _periodDays = 30;

class _StatsData {
  const _StatsData({required this.snapshot, this.neighborhoods, this.note});
  final StatsSnapshot snapshot;

  /// Bairros de Manaus mais afetados; `null` sem servidor ou se a consulta falhou.
  final NeighborhoodsData? neighborhoods;

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
  // Tempo curto: sem servidor a tela não pode ficar esperando; os dados do aparelho já aparecem antes.
  final _api = ApiClient(timeout: const Duration(seconds: 8));
  final _answers = LocalAnswerStore();
  final _cache = StatsCache();
  late final AnswerSync _sync = AnswerSync(api: _api);

  /// Sempre preenchido logo após abrir (dados deste aparelho); o servidor só substitui.
  _StatsData? _data;
  bool _refreshing = false;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<StatsSnapshot> _localSnapshot() async {
    try {
      return computeLocalStats(await _answers.all(), days: _periodDays);
    } catch (_) {
      return computeLocalStats(const [], days: _periodDays); // até aqui a tela não fica vazia
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _when(DateTime t) {
    final l = t.toLocal();
    return '${_two(l.day)}/${_two(l.month)}/${l.year} ${_two(l.hour)}:${_two(l.minute)}';
  }

  Future<void> _loadPending() async {
    try {
      final pending = await _sync.pendingCount();
      if (mounted) setState(() => _pending = pending);
    } catch (_) {
      // contador é só informativo
    }
  }

  /// 1) mostra já os dados deste aparelho; 2) tenta o servidor; 3) se falhar, usa a última cópia
  /// recebida do servidor; 4) se não houver, mantém os dados do aparelho com um aviso.
  /// Nenhum caminho deixa a tela em branco ou girando sem fim.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final local = await _localSnapshot();
      if (!mounted) return;
      if (_data == null) setState(() => _data = _StatsData(snapshot: local));

      if (!_api.isConfigured) return;

      // Entrega o que ficou pendente sem travar a tela.
      _sync.flush().then((_) => _loadPending()).catchError((Object _) {});

      String? note;
      try {
        final statsJson = await _api.fetchStatsJson(days: _periodDays);
        final snapshot = StatsSnapshot.fromServerJson(statsJson);
        Map<String, dynamic>? neighborhoodsJson;
        NeighborhoodsData? neighborhoods;
        try {
          neighborhoodsJson = await _api.fetchNeighborhoodsJson(days: _periodDays);
          neighborhoods = NeighborhoodsData.fromJson(neighborhoodsJson);
        } catch (_) {
          neighborhoodsJson = null; // os demais gráficos continuam
        }
        await _cache.save(days: _periodDays, stats: statsJson, neighborhoods: neighborhoodsJson);
        if (!mounted) return;
        setState(() => _data = _StatsData(snapshot: snapshot, neighborhoods: neighborhoods));
        return;
      } on ApiException catch (e) {
        note = e.message;
      } catch (_) {
        note = 'Não foi possível obter os números do servidor agora.';
      }

      final cached = await _cache.load();
      if (cached != null && cached.days == _periodDays) {
        try {
          final snapshot = StatsSnapshot.fromServerJson(cached.stats);
          NeighborhoodsData? neighborhoods;
          try {
            final nb = cached.neighborhoods;
            neighborhoods = nb == null ? null : NeighborhoodsData.fromJson(nb);
          } catch (_) {
            neighborhoods = null;
          }
          if (!mounted) return;
          setState(() {
            _data = _StatsData(
              snapshot: snapshot,
              neighborhoods: neighborhoods,
              note: '$note Mostrando os últimos números recebidos do servidor, de ${_when(cached.savedAt)}.',
            );
          });
          return;
        } catch (_) {
          // cópia inválida: segue para os dados do aparelho
        }
      }
      if (!mounted) return;
      setState(() => _data = _StatsData(snapshot: local, note: '$note Mostrando só os dados deste aparelho.'));
    } catch (_) {
      // qualquer falha inesperada: a tela segue com o que já tem
    } finally {
      if (mounted) setState(() => _refreshing = false);
      _loadPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
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
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_refreshing) ...[
                    const LinearProgressIndicator(minHeight: 3),
                    const SizedBox(height: 8),
                  ],
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
                  const SectionTitle('SINTOMAS MAIS RELATADOS'),
                  AppCard(
                    child: Column(
                      children: [
                        for (final s in _symptomsToShow(data.snapshot)) _SymptomRow(stat: s),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data.snapshot.sufficient
                        ? 'Relato = sintoma com intensidade leve ou maior. O percentual é sobre o '
                            'total de respostas do período. Os números descrevem quem usa o app e '
                            'não representam toda a população.'
                        : 'Os gráficos aparecem zerados porque ainda não há dados publicados.',
                    style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  const SectionTitle('NÍVEL DE RISCO DAS RESPOSTAS'),
                  AppCard(child: _LevelsChart(snapshot: data.snapshot)),
                  const SizedBox(height: 16),
                  const SectionTitle('BAIRROS DE MANAUS MAIS AFETADOS'),
                  _NeighborhoodsCard(data: data.neighborhoods, serverConfigured: _api.isConfigured),
                  if (_pending > 0) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Há $_pending envio(s) aguardando conexão.',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Sintomas do período; se ainda não há dados, a lista completa com zeros (o gráfico não some).
List<SymptomStat> _symptomsToShow(StatsSnapshot snapshot) {
  if (snapshot.sufficient && snapshot.symptoms.isNotEmpty) return snapshot.symptoms;
  return [
    for (final item in symptomItems)
      SymptomStat(
        id: item.id,
        reports: 0,
        percent: 0,
        mild: 0,
        moderate: 0,
        intense: 0,
        meanSeverity: null,
      ),
  ];
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

/// Barras do nível de risco das respostas (sempre visível, inclusive zerado).
class _LevelsChart extends StatelessWidget {
  const _LevelsChart({required this.snapshot});
  final StatsSnapshot snapshot;

  static String _label(RiskLevel l) => switch (l) {
        RiskLevel.low => 'Baixo',
        RiskLevel.moderate => 'Moderado',
        RiskLevel.high => 'Alto',
        RiskLevel.emergency => 'Procure atendimento',
      };

  @override
  Widget build(BuildContext context) {
    final counts = {
      for (final l in RiskLevel.values) l: snapshot.sufficient ? (snapshot.levels[l.name] ?? 0) : 0,
    };
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return Column(
      children: [
        for (final level in RiskLevel.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_label(level),
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                    ),
                    Text(
                      '${counts[level]} · ${total == 0 ? '0' : (100 * counts[level]! / total).toStringAsFixed(1).replaceAll('.', ',')}%',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : counts[level]! / total,
                    minHeight: 9,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation(levelColor(level)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ranking dos bairros de Manaus; sem dados, mostra as barras vazias e a explicação.
class _NeighborhoodsCard extends StatelessWidget {
  const _NeighborhoodsCard({required this.data, required this.serverConfigured});
  final NeighborhoodsData? data;
  final bool serverConfigured;

  @override
  Widget build(BuildContext context) {
    final items = data?.items ?? const <NeighborhoodStat>[];
    final top = items.isEmpty ? 0 : items.first.responses;
    final rows = items.isEmpty ? 5 : items.length;
    final message = !serverConfigured
        ? 'Disponível quando o app estiver conectado ao servidor do projeto.'
        : data == null
            ? 'Não foi possível carregar os bairros agora.'
            : 'Ainda não há dados publicados. Um bairro aparece quando tem pelo menos '
                '${data!.minimum} respostas.';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          items.isEmpty ? '—' : '${i + 1}. ${items[i].name}',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                        ),
                      ),
                      Text(
                        items.isEmpty ? '0' : '${items[i].responses} resposta(s)',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: items.isEmpty || top == 0 ? 0 : items[i].responses / top,
                      minHeight: 9,
                      backgroundColor: AppColors.border,
                    ),
                  ),
                  if (items.isNotEmpty && items[i].high > 0) ...[
                    const SizedBox(height: 3),
                    Text('${items[i].high} com risco alto ou emergência',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
          if (items.isEmpty) ...[
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(height: 1.4, color: AppColors.muted)),
          ] else ...[
            const SizedBox(height: 8),
            Text(data!.source, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }
}
