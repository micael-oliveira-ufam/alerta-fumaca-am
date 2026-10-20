import 'package:flutter/widgets.dart';

/// Mantém a página viva dentro de um TabBarView.
///
/// Sem isso, o TabBarView destrói a aba que não está visível. Ao voltar, a aba refaz a
/// consulta do zero (e a consulta falha de novo, se a primeira já tinha falhado).
class KeepAlivePage extends StatefulWidget {
  const KeepAlivePage({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // obrigatório com AutomaticKeepAliveClientMixin
    return widget.child;
  }
}
