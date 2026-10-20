import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_info.dart';
import '../data/lgpd_terms.dart';
import '../services/report_repository.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'lgpd_screen.dart';

/// Tela de abertura. Continua visualmente a splash nativa (mesma cor e marca),
/// então a transição entre as duas é contínua.
///
/// Animação: fumaça que se dissipa ao fundo, logo com anel de pulso e entrada
/// escalonada de nome, slogan e recursos. Um toque pula a abertura. Com a opção
/// "remover animações" do sistema ligada, o movimento contínuo é desligado.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  static const _total = Duration(milliseconds: 3800);

  /// Linha do tempo única de entrada (0 a 1 em 3,8 s); cada elemento usa um trecho.
  late final AnimationController _intro = AnimationController(vsync: this, duration: _total)
    ..forward();

  /// Movimento contínuo (fumaça e pulso do anel).
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  Timer? _timer;
  var _leaving = false;

  Animation<double> _slot(double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _intro, curve: Interval(begin, end, curve: curve));

  late final Animation<double> _logo = _slot(0.00, 0.30, Curves.easeOutBack);
  late final Animation<double> _logoFade = _slot(0.00, 0.12, Curves.easeIn);
  late final Animation<double> _name = _slot(0.18, 0.40);
  late final Animation<double> _tagline = _slot(0.32, 0.52);
  late final Animation<double> _footer = _slot(0.70, 0.90);

  @override
  void initState() {
    super.initState();
    _timer = Timer(_total, _goHome);
  }

  Future<void> _goHome() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    var accepted = false;
    try {
      accepted = await ConsentStore().hasAcceptedTerms(kLgpdTermsVersion);
    } catch (_) {
      accepted = false; // na dúvida, mostra o termo
    }
    if (!mounted) return;
    if (!accepted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => LgpdScreen(onAccepted: _openHome),
      ));
      return;
    }
    _openHome();
  }

  /// Recebe o contexto da tela de quem chama: depois do termo, a splash já saiu da pilha.
  void _openHome([BuildContext? from]) {
    final ctx = from ?? context;
    if (!ctx.mounted) return;
    Navigator.of(ctx).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _loop.isAnimating) _loop.stop();

    return Scaffold(
      backgroundColor: AppColors.brandDark,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _goHome,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1B5E20), Color(0xFF123F16)],
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(painter: _SmokePainter(_loop)),
            ),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  _LogoWithPulse(scale: _logo, fade: _logoFade, loop: _loop, still: reduceMotion),
                  const SizedBox(height: 28),
                  _Reveal(animation: _name, child: const _NameBlock()),
                  const SizedBox(height: 14),
                  _Reveal(
                    animation: _tagline,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 36),
                      child: Text(
                        'Alertas, triagem e proteção contra fumaça no Amazonas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFCFE8D2), fontSize: 15, height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _Features(intro: _intro),
                  const Spacer(flex: 2),
                  _Reveal(
                    animation: _footer,
                    child: Column(
                      children: [
                        const Text(
                          'Faculdade de Ciências Farmacêuticas · UFAM',
                          style: TextStyle(color: Color(0xFFA5D6A7), fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Versão $kAppVersion',
                          style: TextStyle(color: Color(0xFF81C784), fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Orientação educativa. Não substitui atendimento médico.',
                          style: TextStyle(color: Color(0xFF81C784), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 64),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: AnimatedBuilder(
                        animation: _intro,
                        builder: (context, _) => LinearProgressIndicator(
                          value: _intro.value,
                          minHeight: 3,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(Color(0xFFA5D6A7)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Toque para continuar',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aparece subindo alguns pixels e ganhando opacidade.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
        child: child,
      ),
    );
  }
}

class _NameBlock extends StatelessWidget {
  const _NameBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text.rich(
          TextSpan(
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
            children: [
              TextSpan(text: 'Respir'),
              TextSpan(text: 'AR', style: TextStyle(color: Color(0xFF9CCC65))),
            ],
          ),
        ),
        SizedBox(height: 2),
        Text(
          'AMAZONAS',
          style: TextStyle(
            color: Color(0xFFCFE8D2),
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
        ),
      ],
    );
  }
}

/// Logo com dois anéis que se expandem e somem, como o ar "respirando".
class _LogoWithPulse extends StatelessWidget {
  const _LogoWithPulse(
      {required this.scale, required this.fade, required this.loop, required this.still});
  final Animation<double> scale;
  final Animation<double> fade;
  final Animation<double> loop;
  final bool still;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!still) CustomPaint(size: const Size(220, 190), painter: _RingsPainter(loop)),
          ScaleTransition(
            scale: scale,
            child: FadeTransition(
              opacity: fade,
              child: Image.asset(
                'assets/icon/app_icon_foreground.png',
                width: 140,
                height: 140,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.loop) : super(repaint: loop);
  final Animation<double> loop;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Ciclo de 3 s dentro dos 12 s do controlador: 4 pulsos por volta.
    for (var i = 0; i < 2; i++) {
      final t = ((loop.value * 4) + i * 0.5) % 1.0;
      final radius = 70 + 40 * t;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFA5D6A7).withValues(alpha: 0.35 * (1 - t));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => false;
}

class _Features extends StatelessWidget {
  const _Features({required this.intro});
  final Animation<double> intro;

  static const _items = <(IconData, String)>[
    (Icons.local_fire_department_rounded, 'Focos de calor\n(INPE)'),
    (Icons.air_rounded, 'Qualidade\ndo ar'),
    (Icons.assignment_ind_rounded, 'Triagem de\nsintomas'),
    (Icons.wifi_off_rounded, 'Orientações\nsem internet'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _items.length; i++)
          _Reveal(
            animation: CurvedAnimation(
              parent: intro,
              curve: Interval(0.46 + i * 0.07, 0.66 + i * 0.07, curve: Curves.easeOutBack),
            ),
            child: SizedBox(
              width: 82,
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Icon(_items[i].$1, color: const Color(0xFFE8F5E9), size: 24),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _items[i].$2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFCFE8D2), fontSize: 11, height: 1.25),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Manchas de fumaça que sobem devagar e vão ficando transparentes.
class _SmokePainter extends CustomPainter {
  _SmokePainter(this.loop) : super(repaint: loop);
  final Animation<double> loop;

  // (x inicial 0..1, fase 0..1, raio relativo, velocidade em voltas por ciclo)
  static const _blobs = <(double, double, double, int)>[
    (0.12, 0.00, 0.30, 1),
    (0.80, 0.18, 0.26, 1),
    (0.45, 0.36, 0.34, 1),
    (0.25, 0.55, 0.24, 1),
    (0.90, 0.70, 0.30, 1),
    (0.60, 0.86, 0.22, 1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in _blobs) {
      final t = (loop.value * b.$4 + b.$2) % 1.0; // 0 = embaixo, 1 = topo
      final dx = math.sin((t + b.$2) * 2 * math.pi) * 24;
      final center = Offset(size.width * b.$1 + dx, size.height * (1.08 - 1.2 * t));
      final radius = size.width * b.$3 * (0.8 + 0.5 * t);
      // Mais opaca no meio da subida, some nas pontas.
      final alpha = 0.16 * math.sin(math.pi * t);
      final paint = Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: alpha),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SmokePainter old) => false;
}
