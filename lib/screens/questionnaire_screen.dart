import 'package:flutter/material.dart';

import '../data/guidance_content.dart';
import '../data/pdf_content.dart';
import '../logic/context_advice.dart';
import '../logic/risk_assessment.dart';
import '../models/answer_record.dart';
import '../models/smoke_context.dart';
import '../models/smoke_report.dart';
import '../services/answer_sync.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/location_service.dart';
import '../services/report_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/choice_widgets.dart';
import '../widgets/emergency_banner.dart';
import '../widgets/ui.dart';
import 'info_screen.dart';
import 'references_screen.dart';

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

  // Contexto (não entra na pontuação). `null` = não sei / sem resposta.
  Place? _place;
  bool? _visibleSmoke;
  MaskUse? _mask;
  bool? _outdoorExercise;
  bool? _cleanAir;
  bool? _outdoorWork;
  bool? _immune;
  bool? _medsAtHand;
  bool? _medsNotWorking;
  bool? _worsening;

  /// Perguntas de contexto que a pessoa tocou (inclusive "Não sei").
  final Set<String> _touched = {};

  /// Etapa atual: 0 sintomas, 1 exposição, 2 sobre você, 3 situação atual, 4 resultado.
  int _step = 0;
  static const _lastQuestionStep = 3;
  final _scroll = ScrollController();

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

  SmokeContext get _context => SmokeContext(
        place: _place,
        visibleSmoke: _visibleSmoke,
        mask: _mask,
        outdoorExercise: _outdoorExercise,
        cleanAir: _cleanAir,
        outdoorWork: _outdoorWork,
        immune: _immune,
        medsAtHand: _medsAtHand,
        medsNotWorking: _medsNotWorking,
        worsening: _worsening,
      );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _restart() {
    setState(() {
      for (final i in symptomItems) {
        _severities[i.id] = 0;
      }
      _answered.clear();
      _touched.clear();
      _exposure = Exposure.under1h;
      _elderly = _pregnant = _child = _chronicResp = _chronicCard = false;
      _place = null;
      _mask = null;
      _visibleSmoke = _outdoorExercise = _cleanAir = _outdoorWork = null;
      _immune = _medsAtHand = _medsNotWorking = _worsening = null;
      _result = null;
      _lastSignature = null;
    });
    _goTo(0);
  }

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
    setState(() {
      _result = result;
      _step = _lastQuestionStep + 1;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _registerAnswers(result);
  }

  /// Guarda a resposta neste aparelho (estatísticas locais) e, se o servidor estiver
  /// configurado e a pessoa consentiu, envia sem identificação.
  Future<void> _registerAnswers(RiskResult result) async {
    final severities = {for (final item in symptomItems) item.id: _severities[item.id] ?? 0};
    final exposure = _exposure;
    final profile = _profile;
    final smokeContext = _context;
    final signature = [
      for (final e in severities.entries) '${e.key}=${e.value}',
      exposure.name,
      profile.elderly,
      profile.pregnant,
      profile.child,
      profile.chronicRespiratory,
      profile.chronicCardiac,
      smokeContext.toPayload().toString(),
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
      smokeContext: smokeContext,
      recordedAt: recordedAt,
    );
  }

  Future<void> _sendToServer({
    required RiskResult result,
    required Map<String, int> severities,
    required Exposure exposure,
    required Profile profile,
    required SmokeContext smokeContext,
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
      context: smokeContext,
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
                Text(
                  'Servidor de destino: ${ApiConfig.host}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Se você concordar, o app enviará ao servidor do projeto cada resposta '
                  'do questionário: os sintomas e suas intensidades, o tempo de exposição, '
                  'seu perfil (por exemplo, gestante, idoso ou doença crônica), as respostas '
                  'sobre o local, a proteção usada e a situação atual, e o nível '
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

  void _touch(String key, VoidCallback change) {
    setState(() {
      _touched.add(key);
      change();
      _result = null;
    });
  }

  static const _stepTitles = ['Sintomas', 'Exposição', 'Sobre você', 'Agora'];

  @override
  Widget build(BuildContext context) {
    final isResult = _step > _lastQuestionStep;
    return Scaffold(
      appBar: AppBar(
        title: Text(isResult ? 'Sua orientação' : 'Como você está'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Referências do questionário',
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ReferencesScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isResult) _StepHeader(step: _step, titles: _stepTitles),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_step == 0) ..._symptomsStep(),
                if (_step == 1) ..._exposureStep(),
                if (_step == 2) ..._aboutStep(),
                if (_step == 3) ..._nowStep(),
                if (isResult) ..._resultStep(),
                const SizedBox(height: 20),
                const Text(
                  kDisclaimer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (!isResult) _bottomBar(),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final isLast = _step == _lastQuestionStep;
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              if (_step > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Voltar',
                    size: 56,
                    onPressed: () => _goTo(_step - 1),
                  ),
                ),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 56),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: isLast ? _submit : () => _goTo(_step + 1),
                  icon: Icon(isLast ? Icons.insights_rounded : Icons.arrow_forward_rounded),
                  label: Text(isLast ? 'Ver minha orientação' : 'Continuar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- etapa 0
  List<Widget> _symptomsStep() {
    final remaining = symptomItems.length - _answered.length;
    return [
      _Question(
        title: 'O que você sente agora?',
        help: 'Toque na intensidade de cada sintoma. Quem não sente nada pode tocar em '
            '"Nenhum" ou usar o botão abaixo.',
        refs: '[1]',
        child: Column(
          children: [
            for (final item in symptomItems) ...[
              _SymptomCard(
                item: item,
                value: _severities[item.id]!,
                answered: _answered.contains(item.id),
                onChanged: (v) => _setSeverity(item.id, v),
              ),
              const SizedBox(height: 10),
            ],
            if (remaining > 0)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 48),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => setState(() {
                  for (final i in symptomItems) {
                    if (!_answered.contains(i.id)) {
                      _severities[i.id] = 0;
                      _answered.add(i.id);
                    }
                  }
                  _result = null;
                }),
                icon: const Icon(Icons.done_all_rounded),
                label: Text('Marcar os $remaining restantes como "Nenhum"'),
              )
            else
              const Text(
                'Todos os sintomas respondidos.',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand),
              ),
          ],
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------- etapa 1
  List<Widget> _exposureStep() => [
        _Question(
          title: 'Onde você está agora?',
          refs: '[1][2]',
          child: CircleChoiceRow<Place>(
            value: _place,
            onChanged: (v) => _touch('place', () => _place = v),
            options: const [
              CircleOption(value: Place.outdoors, label: 'Ao ar livre', icon: Icons.park_rounded, color: Color(0xFF2E7D32)),
              CircleOption(value: Place.homeOpen, label: 'Dentro, janelas abertas', icon: Icons.window_rounded, color: Color(0xFFB7791F)),
              CircleOption(value: Place.homeClosed, label: 'Dentro, janelas fechadas', icon: Icons.home_rounded, color: Color(0xFF1565C0)),
            ],
          ),
        ),
        _Question(
          title: 'Dá para ver ou sentir cheiro de fumaça?',
          refs: '[1]',
          child: YesNoRow(
            value: _visibleSmoke,
            answered: _touched.contains('smoke'),
            onChanged: (v) => _touch('smoke', () => _visibleSmoke = v),
          ),
        ),
        _Question(
          title: 'Quanto tempo ficou ao ar livre hoje?',
          help: 'Soma do dia todo. Os cortes de 1 h e 4 h são escolha do projeto.',
          refs: '[2]',
          child: CircleChoiceRow<Exposure>(
            value: _exposure,
            onChanged: (v) => setState(() {
              _exposure = v;
              _result = null;
            }),
            options: const [
              CircleOption(value: Exposure.under1h, label: 'Menos de 1 h', icon: Icons.timer_outlined, color: Color(0xFF2E7D32)),
              CircleOption(value: Exposure.between1and4h, label: '1 a 4 h', icon: Icons.schedule_rounded, color: Color(0xFFB7791F)),
              CircleOption(value: Exposure.over4h, label: 'Mais de 4 h', icon: Icons.hourglass_bottom_rounded, color: Color(0xFFC62828)),
            ],
          ),
        ),
        _Question(
          title: 'Que proteção usou ao sair hoje?',
          refs: '[1][2]',
          child: CircleChoiceRow<MaskUse>(
            value: _mask,
            onChanged: (v) => _touch('mask', () => _mask = v),
            options: const [
              CircleOption(value: MaskUse.didNotGoOut, label: 'Não saí', icon: Icons.home_work_rounded, color: Color(0xFF607D8B)),
              CircleOption(value: MaskUse.none, label: 'Sem máscara', icon: Icons.face_rounded, color: Color(0xFFC62828)),
              CircleOption(value: MaskUse.surgicalOrCloth, label: 'Cirúrgica ou pano', icon: Icons.masks_rounded, color: Color(0xFFB7791F)),
              CircleOption(value: MaskUse.respirator, label: 'PFF2 / N95', icon: Icons.health_and_safety_rounded, color: Color(0xFF2E7D32)),
            ],
          ),
        ),
        _Question(
          title: 'Fez exercício intenso ao ar livre hoje?',
          refs: '[2]',
          child: YesNoRow(
            value: _outdoorExercise,
            answered: _touched.contains('exercise'),
            onChanged: (v) => _touch('exercise', () => _outdoorExercise = v),
          ),
        ),
        _Question(
          title: 'Seu trabalho é ao ar livre?',
          refs: '[2]',
          child: YesNoRow(
            value: _outdoorWork,
            answered: _touched.contains('work'),
            onChanged: (v) => _touch('work', () => _outdoorWork = v),
          ),
        ),
        _Question(
          title: 'Você tem ar filtrado ou um cômodo protegido para ficar?',
          help: 'Ar-condicionado com filtro, purificador de ar ou um cômodo fechado com menos fumaça.',
          refs: '[1][2]',
          child: YesNoRow(
            value: _cleanAir,
            answered: _touched.contains('clean'),
            onChanged: (v) => _touch('clean', () => _cleanAir = v),
          ),
        ),
      ];

  // ---------------------------------------------------------------- etapa 2
  List<Widget> _aboutStep() => [
        _Question(
          title: 'Algum destes se aplica a você?',
          help: 'Esses grupos têm maior risco com a fumaça. Toque para marcar.',
          refs: '[1][2]',
          child: Column(
            children: [
              _profileTile(Icons.elderly_rounded, 'Tenho 60 anos ou mais', _elderly, (v) => _elderly = v),
              _profileTile(Icons.pregnant_woman_rounded, 'Estou grávida', _pregnant, (v) => _pregnant = v),
              _profileTile(Icons.child_care_rounded, 'Sou criança (menos de 12 anos)', _child, (v) => _child = v),
              _profileTile(Icons.air_rounded, 'Asma, DPOC ou outra doença respiratória crônica', _chronicResp, (v) => _chronicResp = v),
              _profileTile(Icons.favorite_rounded, 'Doença cardíaca crônica', _chronicCard, (v) => _chronicCard = v),
            ],
          ),
        ),
        _Question(
          title: 'Tem doença ou usa remédio que reduz a imunidade?',
          refs: '(critério do projeto)',
          child: YesNoRow(
            value: _immune,
            answered: _touched.contains('immune'),
            onChanged: (v) => _touch('immune', () => _immune = v),
          ),
        ),
        _Question(
          title: 'Se usa medicação para o pulmão ou o coração, ela está à mão?',
          help: 'Se não usa nenhuma, escolha "Não sei" ou pule.',
          refs: '[1]',
          child: YesNoRow(
            value: _medsAtHand,
            answered: _touched.contains('meds'),
            onChanged: (v) => _touch('meds', () => _medsAtHand = v),
          ),
        ),
      ];

  // ---------------------------------------------------------------- etapa 3
  List<Widget> _nowStep() => [
        _Question(
          title: 'Os sintomas estão piorando?',
          refs: '[1] + critério do projeto',
          child: YesNoRow(
            value: _worsening,
            answered: _touched.contains('worse'),
            onChanged: (v) => _touch('worse', () => _worsening = v),
          ),
        ),
        _Question(
          title: 'O remédio que você costuma usar não está aliviando?',
          help: 'Responda só se usa medicação para falta de ar, asma ou o coração.',
          refs: '(critério do projeto)',
          child: YesNoRow(
            value: _medsNotWorking,
            answered: _touched.contains('meds_fail'),
            onChanged: (v) => _touch('meds_fail', () => _medsNotWorking = v),
          ),
        ),
        const AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.brand),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Todas as perguntas de contexto são opcionais e não entram na pontuação: '
                  'servem para orientar os cuidados e, se você permitir, para as estatísticas '
                  'anônimas. Respostas "Não sei" não são enviadas.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ];

  // ---------------------------------------------------------------- resultado
  List<Widget> _resultStep() {
    final result = _result;
    if (result == null) return const [];
    final tips = contextTips(_context, _profile);
    return [
      _ResultCard(result: result),
      if (tips.isNotEmpty) ...[
        const SizedBox(height: 12),
        _TipsCard(tips: tips),
      ],
      const SizedBox(height: 12),
      if (result.level == RiskLevel.emergency) ...[
        const EmergencyBanner(),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const StadiumBorder(),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const InfoScreen(
              title: 'Entenda seus sintomas',
              cards: symptomExplainers,
              showCit: true,
            ),
          ),
        ),
        icon: const Icon(Icons.psychology_alt_rounded),
        label: const Text('Entenda seus sintomas'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const StadiumBorder(),
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
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 48),
                shape: const StadiumBorder(),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const ReferencesScreen()),
              ),
              icon: const Icon(Icons.menu_book_rounded),
              label: const Text('Referências'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 48),
                shape: const StadiumBorder(),
              ),
              onPressed: _restart,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Refazer'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextButton.icon(
        onPressed: () => _goTo(_lastQuestionStep),
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text('Voltar e corrigir respostas'),
      ),
    ];
  }

  Widget _profileTile(IconData icon, String label, bool value, void Function(bool) onChanged) {
    final color = value ? AppColors.brand : AppColors.muted;
    return Semantics(
      toggled: value,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() {
          onChanged(!value);
          _result = null;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? AppColors.brand : Colors.white,
                  border: Border.all(color: color, width: value ? 3 : 2),
                ),
                child: Icon(value ? Icons.check_rounded : icon, color: value ? Colors.white : color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: value ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicador de etapas com círculos numerados.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.titles});

  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < titles.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 3,
                  color: i <= step ? AppColors.brand : AppColors.border,
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= step ? AppColors.brand : Colors.white,
                    border: Border.all(color: i <= step ? AppColors.brand : AppColors.border, width: 2),
                  ),
                  child: i < step
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: i == step ? Colors.white : AppColors.muted,
                          ),
                        ),
                ),
                const SizedBox(height: 2),
                Text(
                  titles[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == step ? FontWeight.w800 : FontWeight.w500,
                    color: i == step ? AppColors.ink : AppColors.muted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Bloco de uma pergunta: título, ajuda opcional, controle e referências.
class _Question extends StatelessWidget {
  const _Question({required this.title, required this.child, this.help, this.refs});

  final String title;
  final String? help;

  /// Texto curto com as referências da pergunta (ex.: "[1][2]"). Detalhes em "Referências".
  final String? refs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
            if (help != null) ...[
              const SizedBox(height: 4),
              Text(help!, style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.muted)),
            ],
            const SizedBox(height: 12),
            child,
            if (refs != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Fonte: $refs',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SymptomCard extends StatelessWidget {
  const _SymptomCard({
    required this.item,
    required this.value,
    required this.answered,
    required this.onChanged,
  });

  final SymptomItem item;
  final int value;
  final bool answered;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      decoration: BoxDecoration(
        color: answered ? Colors.white : AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              item.label,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 6),
          SeverityPicker(value: value, answered: answered, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard({required this.tips});
  final List<ContextTip> tips;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: const Color(0xFFE8F1FB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cuidados para a sua situação',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          for (final t in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    t.urgent ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                    size: 20,
                    color: t.urgent ? const Color(0xFFC62828) : AppColors.brand,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.refs.isEmpty ? t.text : '${t.text} ${t.refs.map((r) => '[$r]').join()}',
                      style: TextStyle(
                        height: 1.4,
                        fontWeight: t.urgent ? FontWeight.w700 : FontWeight.w400,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
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
