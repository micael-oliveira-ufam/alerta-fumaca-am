import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/guidance_content.dart';
import '../theme/app_theme.dart';
import '../widgets/cit_card.dart';
import '../widgets/ui.dart';
import 'about_screen.dart';
import '../data/pdf_content.dart';
import 'guidance_screen.dart';
import 'info_screen.dart';
import 'questionnaire_screen.dart';
import 'references_screen.dart';
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
        title: const Text('RespirAR Amazonas', style: TextStyle(fontWeight: FontWeight.w800)),
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
          const SizedBox(height: 16),
          const SectionTitle('O QUE VOCÊ PRECISA AGORA'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CircleAction(
                  icon: Icons.health_and_safety_rounded,
                  color: AppColors.brand,
                  label: 'O que fazer agora',
                  onTap: () => _open(context, const GuidanceScreen()),
                ),
              ),
              Expanded(
                child: CircleAction(
                  icon: Icons.assignment_ind_rounded,
                  color: const Color(0xFF1565C0),
                  label: 'Como estou me sentindo',
                  onTap: () => _open(context, const QuestionnaireScreen()),
                ),
              ),
              Expanded(
                child: CircleAction(
                  icon: Icons.map_rounded,
                  color: const Color(0xFF6A1B9A),
                  label: 'Mapa de risco',
                  onTap: () => _open(context, const RiskMapScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CircleAction(
                  icon: Icons.bar_chart_rounded,
                  color: const Color(0xFFEF6C00),
                  label: 'Sintomas mais relatados',
                  onTap: () => _open(context, const StatsScreen()),
                ),
              ),
              Expanded(
                child: CircleAction(
                  icon: Icons.menu_book_rounded,
                  color: const Color(0xFF00838F),
                  label: 'Referências',
                  onTap: () => _open(context, const ReferencesScreen()),
                ),
              ),
              Expanded(
                child: CircleAction(
                  icon: Icons.info_outline_rounded,
                  color: const Color(0xFF546E7A),
                  label: 'Sobre o app',
                  onTap: () => _open(context, const AboutScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CircleAction(
                  icon: Icons.local_pharmacy_rounded,
                  color: const Color(0xFFC62828),
                  label: 'Farmácia caseira',
                  onTap: () => _open(
                    context,
                    const InfoScreen(title: 'Farmácia caseira e cuidados', cards: homeCareCards),
                  ),
                ),
              ),
              Expanded(
                child: CircleAction(
                  icon: Icons.pets_rounded,
                  color: const Color(0xFF6D4C41),
                  label: 'E os nossos pets?',
                  onTap: () => _open(
                    context,
                    const InfoScreen(title: 'E os nossos pets?', cards: petCards),
                  ),
                ),
              ),
              Expanded(
                child: CircleAction(
                  icon: Icons.fact_check_rounded,
                  color: const Color(0xFF283593),
                  label: 'Fato ou Fake?',
                  onTap: () => _open(context, const MythsScreen()),
                ),
              ),
            ],
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
      child: const Row(
        children: const [
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
