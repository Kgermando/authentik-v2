import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'services/app_controller.dart';
import 'services/database.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSqlite();
  try {
    await pdfrxFlutterInitialize();
  } catch (_) {
    // Les versions de pdfrx qui s'initialisent seules n'ont pas besoin de cet appel.
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppController()..init(),
      child: const AuthentikApp(),
    ),
  );
}

class AuthentikApp extends StatelessWidget {
  const AuthentikApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.select<AppController, bool>((c) => c.settings.darkMode);
    final ready = context.select<AppController, bool>((c) => c.ready);
    return MaterialApp(
      title: 'Authentik v2',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: ready ? const AppShell() : const _Splash(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
