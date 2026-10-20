import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/pdf_content.dart';
import '../data/references.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Referências do questionário: o que cada pergunta usa e o que foi verificado.
class ReferencesScreen extends StatelessWidget {
  const ReferencesScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('Não foi possível abrir: $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referências'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const AppCard(
            child: Text(
              'O questionário é uma ferramenta educativa. As perguntas sobre sintomas, '
              'grupos de risco e proteção se baseiam nas fontes abaixo. Onde a pergunta é '
              'escolha do projeto (e não das fontes), isso está indicado.',
              style: TextStyle(height: 1.45, color: AppColors.ink),
            ),
          ),
          const SectionTitle('FONTES'),
          for (final r in references) ...[
            AppCard(
              onTap: () => _open(context, r.url),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                        child: Text(
                          '${r.id}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          r.citation,
                          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35, color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Usado para: ${r.used}', style: const TextStyle(height: 1.4, color: AppColors.ink)),
                  if (r.caveat != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Ressalva: ${r.caveat}',
                      style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF8A5A00)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    r.url,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1565C0), decoration: TextDecoration.underline),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SectionTitle('FONTES DOS TEXTOS EDUCATIVOS'),
          const AppCard(
            color: Color(0xFFFFF8E1),
            child: Text(
              'Estas fontes foram indicadas pela equipe para os textos de proteção, farmácia '
              'caseira, pets e "Fato ou Fake?". Abaixo está dito o que foi conferido pelo '
              'desenvolvedor e o que NÃO foi consultado. Nada aqui substitui orientação médica ou veterinária.',
              style: TextStyle(height: 1.45, color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 10),
          for (final r in extraReferences) ...[
            AppCard(
              onTap: r.url == null ? null : () => _open(context, r.url!),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('[${r.id}] ${r.citation}',
                      style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  Text('Usado para: ${r.used}', style: const TextStyle(height: 1.4, color: AppColors.ink)),
                  const SizedBox(height: 6),
                  Text('Verificação: ${r.status}',
                      style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF8A5A00))),
                  if (r.url != null) ...[
                    const SizedBox(height: 6),
                    Text(r.url!,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF1565C0), decoration: TextDecoration.underline)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SectionTitle('DE ONDE VEIO CADA PERGUNTA'),
          for (final q in questionSources) ...[
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.question, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (q.refs.isEmpty)
                        const Pill(label: 'Critério do projeto', color: Color(0xFF8A5A00))
                      else
                        for (final id in q.refs) Pill(label: 'Fonte [$id]', color: AppColors.brandDark),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(q.note, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SectionTitle('SOBRE A PONTUAÇÃO'),
          const AppCard(
            color: Color(0xFFFFF8E1),
            child: Text(scoringNotice, style: TextStyle(height: 1.45, color: AppColors.ink)),
          ),
        ],
      ),
    );
  }
}
