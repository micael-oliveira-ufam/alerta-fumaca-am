import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/keep_alive_page.dart';
import 'map/air_quality_tab.dart';
import 'map/community_tab.dart';
import 'map/official_fire_tab.dart';

/// Tela de mapas e qualidade do ar, em três abas:
/// 1. focos de calor oficiais (INPE) por satélite, com o Amazonas em destaque;
/// 2. qualidade do ar estimada por modelo (CAMS via Open-Meteo);
/// 3. registros anonimizados da comunidade.
class RiskMapScreen extends StatelessWidget {
  const RiskMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mapa de risco'),
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.local_fire_department_rounded), text: 'Focos · INPE'),
              Tab(icon: Icon(Icons.air_rounded), text: 'Qualidade do ar'),
              Tab(icon: Icon(Icons.groups_rounded), text: 'Comunidade'),
            ],
          ),
        ),
        body: const TabBarView(
          // Evita arrastar entre abas ao mover o mapa.
          physics: NeverScrollableScrollPhysics(),
          children: [
            KeepAlivePage(child: OfficialFireTab()),
            KeepAlivePage(child: AirQualityTab()),
            KeepAlivePage(child: CommunityTab()),
          ],
        ),
      ),
    );
  }
}
