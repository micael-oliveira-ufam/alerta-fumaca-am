import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_info.dart';
import '../data/guidance_content.dart';
import '../services/inpe_fire_service.dart';
import '../theme/app_theme.dart';
import '../widgets/platform_card.dart';
import '../widgets/ui.dart';
import 'lgpd_screen.dart';

const _instituicao = 'Faculdade de Ciências Farmacêuticas (FCF)\nUniversidade Federal do Amazonas (UFAM)';

const _desenvolvedores = <({String nome, String instituicao, String email, String foto})>[
  (
    nome: 'Micael Davi Lima de Oliveira',
    instituicao: 'FCF · UFAM',
    email: 'micael.oliveira@ufam.edu.br',
    foto: 'assets/images/dev_micael.jpg',
  ),
  (
    nome: 'Elias de Souza Barros',
    instituicao: 'FCF · UFAM',
    email: 'eliasbarros170@gmail.com',
    foto: 'assets/images/dev_elias.jpg',
  ),
];

Future<void> _escrever(BuildContext context, String email) async {
  final ok = await launchUrl(Uri(scheme: 'mailto', path: email));
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text('Escreva para $email')),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sobre o aplicativo'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              children: [
                Image.asset('assets/icon/app_icon.png', width: 96, height: 96),
                const SizedBox(height: 12),
                const Text(
                  'RespirAR Amazonas',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                const Text('Versão $kAppVersion', style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 12),
                const Text(
                  'Orientação educativa e triagem de sintomas durante episódios de fumaça '
                  'no Amazonas, com dados oficiais de focos de calor e registros anonimizados da comunidade.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.4, color: AppColors.ink),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LgpdScreen(onlyRead: true)),
            ),
            icon: const Icon(Icons.privacy_tip_outlined),
            label: const Text('Privacidade e uso dos dados (LGPD)'),
          ),
          const SizedBox(height: 20),
          const SectionTitle('PLATAFORMA ONLINE'),
          const PlatformCard(),
          const SizedBox(height: 20),
          const SectionTitle('DESENVOLVEDORES'),
          for (final dev in _desenvolvedores) ...[
            AppCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFFE8F5E9),
                    backgroundImage: AssetImage(dev.foto),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dev.nome,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                        const SizedBox(height: 2),
                        Text(dev.instituicao,
                            style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _escrever(context, dev.email),
                          child: Row(
                            children: [
                              const Icon(Icons.mail_outline_rounded, size: 16, color: Color(0xFF1565C0)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(dev.email,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF1565C0),
                                        decoration: TextDecoration.underline)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          const SectionTitle('INSTITUIÇÃO'),
          AppCard(
            child: Column(
              children: [
                Image.asset('assets/images/ufam_logo.png', height: 130, fit: BoxFit.contain),
                const SizedBox(height: 12),
                const Text(
                  _instituicao,
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.4, color: AppColors.ink),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('PARCEIROS'),
          AppCard(
            child: Row(
              children: [
                Image.asset('assets/images/cit_am_logo.png', width: 64, height: 64, fit: BoxFit.contain),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    kCitName,
                    style: TextStyle(height: 1.35, color: AppColors.ink, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('FONTES DE DADOS'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Focos de calor (dado oficial)',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 4),
                Text(
                  'Instituto Nacional de Pesquisas Espaciais (INPE), Programa Queimadas, '
                  'via TerraBrasilis. Camada de todos os satélites: ${FireWindow.last48h.layer}; '
                  '"Hoje" mostra os focos do dia atual em Manaus. Satélites exibidos: '
                  'MODIS (Aqua e Terra), NOAA-20, Suomi NPP e, opcionalmente, NOAA-21.',
                  style: const TextStyle(height: 1.4, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Os focos de calor indicam fogo detectado por satélite, com atraso de '
                  'passagem e processamento. Não são medição direta da qualidade do ar.',
                  style: TextStyle(height: 1.4, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                const Text('Qualidade do ar (estimativa de modelo)',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 4),
                const Text(
                  'Open-Meteo.com, com o modelo CAMS (Copernicus Atmosphere Monitoring '
                  'Service / ECMWF). São estimativas de baixa resolução espacial, não medições '
                  'de estações, e não substituem o IQAr oficial dos órgãos ambientais. Uso '
                  'gratuito apenas para fins não comerciais.',
                  style: TextStyle(height: 1.4, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                const Text('Mapas',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 4),
                const Text(
                  '© colaboradores do OpenStreetMap.',
                  style: TextStyle(height: 1.4, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            kDisclaimer,
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.4, fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
