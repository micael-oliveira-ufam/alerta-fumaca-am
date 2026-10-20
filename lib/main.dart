import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/splash_screen.dart';
import 'services/api_config.dart';
import 'theme/app_theme.dart';

/// Nome exibido do aplicativo.
const appDisplayName = 'RespirAR Amazonas';

Future<void> _enterFullscreen() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tela cheia: esconde as barras do sistema (voltam com um deslize na borda).
  await _enterFullscreen();
  await ApiConfig.load();
  runApp(const AlertaFumacaApp());
}

class AlertaFumacaApp extends StatefulWidget {
  const AlertaFumacaApp({super.key});

  @override
  State<AlertaFumacaApp> createState() => _AlertaFumacaAppState();
}

class _AlertaFumacaAppState extends State<AlertaFumacaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// O sistema mostra as barras de novo ao voltar de outro app ou de um diálogo
  /// do sistema (permissão de localização, por exemplo); reativa a tela cheia.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterFullscreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
