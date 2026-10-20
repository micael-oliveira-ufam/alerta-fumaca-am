import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/report_repository.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Mostra e permite trocar o endereço do servidor (o link do painel do administrador).
class ServerCard extends StatefulWidget {
  const ServerCard({super.key});

  @override
  State<ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<ServerCard> {
  @override
  Widget build(BuildContext context) {
    final configured = ApiConfig.isConfigured;
    final origin = ApiConfig.isOverridden ? 'endereço colado neste aparelho' : 'definido na compilação do app';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            configured ? ApiConfig.host : 'Modo local (sem servidor)',
            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            configured
                ? 'Para onde vão as respostas, só se você autorizar o envio ($origin).'
                : 'Nenhuma resposta sai deste aparelho. Para ajudar nas estatísticas do projeto, '
                    'cole o endereço do servidor informado pela equipe.',
            style: const TextStyle(height: 1.4, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _edit,
                icon: const Icon(Icons.link),
                label: const Text('Alterar endereço'),
              ),
              if (ApiConfig.isOverridden)
                TextButton(onPressed: _reset, child: const Text('Usar o padrão do app')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _applyChange(String? validated) async {
    final before = ApiConfig.baseUrl;
    await ApiConfig.save(validated);
    // O consentimento de envio foi dado para o destino anterior: ao trocar, pergunta de novo.
    if (ApiConfig.baseUrl != before) await ConsentStore().resetSendDecision();
    if (mounted) setState(() {});
  }

  Future<void> _reset() async {
    await _applyChange(null);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Voltou ao endereço padrão do app.')));
  }

  Future<void> _edit() async {
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => const _AddressDialog(),
    );
    if (saved == null) return;
    await _applyChange(saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Servidor conectado: ${ApiConfig.host}. O envio continua exigindo a sua autorização.')),
    );
  }
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final String address;
    try {
      address = parseServerAddress(_controller.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient(baseUrl: address).checkHealth();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Não foi possível conectar: ${e.message}';
      });
      return;
    }
    if (mounted) Navigator.pop(context, address);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Endereço do servidor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cole o link mostrado no painel do servidor (algo como '
            'https://palavras-aleatorias.trycloudflare.com). Só cole links recebidos da equipe '
            'do projeto: as respostas, se você autorizar, vão para este endereço.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'https://…',
              border: const OutlineInputBorder(),
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _test(),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _test, child: const Text('Testar e salvar')),
      ],
    );
  }
}
