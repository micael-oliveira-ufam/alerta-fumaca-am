import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/guidance_content.dart';
import '../theme/app_theme.dart';
import '../widgets/cit_card.dart';
import '../widgets/ui.dart';
import 'about_screen.dart';
import 'guidance_screen.dart';
import 'questionnaire_screen.dart';
import 'risk_map_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerta Fumaça AM', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Sobre o aplicativo',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => _open(context, const AboutScreen()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _Hero(),
          const SizedBox(height: 20),
          const SectionTitle('O QUE VOCÊ PRECISA AGORA'),
          ModuleCard(
            icon: Icons.health_and_safety_rounded,
            color: AppColors.brand,
            title: 'O que fazer agora',
            subtitle: 'Orientações por nível de risco e cuidados de proteção',
            onTap: () => _open(context, const GuidanceScreen()),
          ),
          const SizedBox(height: 12),
          ModuleCard(
            icon: Icons.assignment_ind_rounded,
            color: const Color(0xFF1565C0),
            title: 'Como estou me sentindo',
            subtitle: 'Questionário rápido e triagem dos efeitos da fumaça',
            onTap: () => _open(context, const QuestionnaireScreen()),
          ),
          const SizedBox(height: 12),
          ModuleCard(
            icon: Icons.map_rounded,
            color: const Color(0xFF6A1B9A),
            title: 'Mapa de risco',
            subtitle: 'Focos de calor (INPE), qualidade do ar e comunidade',
            onTap: () => _open(context, const RiskMapScreen()),
          ),
          const SizedBox(height: 12),
          ModuleCard(
            icon: Icons.bar_chart_rounded,
            color: const Color(0xFFEF6C00),
            title: 'Sintomas mais relatados',
            subtitle: 'Estatísticas das respostas ao questionário',
            onTap: () => _open(context, const StatsScreen()),
          ),
          const SizedBox(height: 20),
          _SamuCard(),
          const SizedBox(height: 12),
          const CitCard(),
          const SizedBox(height: 20),
          Text(
            kDisclaimer,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brandDark, AppColors.brandLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Image.asset('assets/icon/app_icon_foreground.png', width: 64, height: 64),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Respire com informação',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Saiba o que fazer, avalie seus sintomas e acompanhe as áreas de risco.',
                  style: TextStyle(color: Color(0xFFDDF1DF), fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SamuCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFC62828);
    return AppCard(
      color: red.withValues(alpha: 0.06),
      onTap: () => launchUrl(Uri(scheme: 'tel', path: kSamuNumber)),
      child: Row(
        children: [
          const Icon(Icons.emergency_rounded, color: red, size: 30),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergência? Ligue 192',
                  style: TextStyle(fontWeight: FontWeight.w700, color: red, fontSize: 16),
                ),
                SizedBox(height: 2),
                Text(
                  'SAMU · falta de ar, dor no peito ou confusão',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
