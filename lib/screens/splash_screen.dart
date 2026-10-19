import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../data/lgpd_terms.dart';
import '../services/report_repository.dart';
import 'home_screen.dart';
import 'lgpd_screen.dart';

/// Tela de abertura. Continua visualmente a splash nativa (mesma cor e marca),
/// então a transição entre as duas é contínua.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 2200);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final Animation<double> _logoScale =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
  late final Animation<double> _textFade =
      CurvedAnimation(parent: _controller, curve: const Interval(0.45, 1, curve: Curves.easeIn));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(_duration, _goHome);
  }

  Future<void> _goHome() async {
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
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandDark,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            ScaleTransition(
              scale: _logoScale,
              child: Image.asset(
                'assets/icon/app_icon_foreground.png',
                width: 150,
                height: 150,
              ),
            ),
            const SizedBox(height: 28),
            FadeTransition(
              opacity: _textFade,
              child: const Column(
                children: [
                  Text(
                    'Alerta Fumaça AM',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Orientação e mapeamento durante episódios de fumaça',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFCFE8D2), fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            FadeTransition(
              opacity: _textFade,
              child: const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text(
                  'Faculdade de Ciências Farmacêuticas · UFAM',
                  style: TextStyle(color: Color(0xFFA5D6A7), fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
