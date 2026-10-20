import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/lgpd_terms.dart';
import '../services/report_repository.dart';
import '../theme/app_theme.dart';

/// Termo de privacidade (LGPD). Exibido na primeira abertura (e quando a versão muda).
///
/// [onlyRead] = abertura pela tela "Sobre": só leitura, sem botão de aceite.
class LgpdScreen extends StatefulWidget {
  const LgpdScreen({super.key, this.onlyRead = false, this.onAccepted});

  final bool onlyRead;
  final void Function(BuildContext context)? onAccepted;

  @override
  State<LgpdScreen> createState() => _LgpdScreenState();
}

class _LgpdScreenState extends State<LgpdScreen> {
  bool _checked = false;
  bool _saving = false;

  Future<void> _accept() async {
    setState(() => _saving = true);
    try {
      await ConsentStore().acceptTerms(kLgpdTermsVersion);
    } catch (_) {
      // Sem armazenamento, o termo volta a aparecer na próxima abertura; segue o uso.
    }
    if (!mounted) return;
    widget.onAccepted?.call(context);
  }

  Future<void> _decline() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair do aplicativo?'),
        content: const Text(
          'Sem ler e aceitar o termo, o aplicativo não pode ser usado. Nenhum dado foi '
          'coletado ou enviado.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sair')),
        ],
      ),
    );
    if (leave == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.onlyRead,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Privacidade e uso dos dados'),
          automaticallyImplyLeading: widget.onlyRead,
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.brand.withValues(alpha: 0.35)),
                      ),
                      child: const Text(
                        kLgpdSummary,
                        style: TextStyle(height: 1.4, fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final section in kLgpdSections) ...[
                      Text(
                        section.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.brandDark),
                      ),
                      const SizedBox(height: 6),
                      for (final p in section.paragraphs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(p, style: const TextStyle(height: 1.45, color: AppColors.ink)),
                        ),
                      const SizedBox(height: 10),
                    ],
                    const Text(
                      'Este texto não é aconselhamento jurídico e está sujeito à revisão da instituição.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (!widget.onlyRead)
                // A cor de fundo fica no Material (e não num DecoratedBox), para que o
                // CheckboxListTile e os efeitos de toque apareçam sobre ela.
                Material(
                  color: Colors.white,
                  child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        value: _checked,
                        onChanged: (v) => setState(() => _checked = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(kLgpdCheckboxLabel, style: TextStyle(fontSize: 13.5)),
                      ),
                      Row(
                        children: [
                          TextButton(onPressed: _decline, child: const Text('Não aceito')),
                          const Spacer(),
                          FilledButton(
                            onPressed: _checked && !_saving ? _accept : null,
                            child: const Text(kLgpdAcceptLabel),
                          ),
                        ],
                      ),
                    ],
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
