import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/api_config.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.load();
  runApp(const AlertaFumacaApp());
}

class AlertaFumacaApp extends StatelessWidget {
  const AlertaFumacaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alerta Fumaça AM',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
