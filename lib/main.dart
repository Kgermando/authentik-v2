import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import 'core/i18n.dart';
import 'core/identity.dart';
import 'core/theme.dart';
import 'services/app_controller.dart';
import 'services/database.dart';
import 'services/reference_controller.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Textes.load(Textes.parse(await rootBundle.loadString(Textes.assetPath)));
  await initSqlite();
  try {
    await pdfrxFlutterInitialize();
  } catch (_) {
    // Les versions de pdfrx qui s'initialisent seules n'ont pas besoin de cet appel.
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppController()..init()),
        ChangeNotifierProvider(
          create: (ctx) => ReferenceController(ctx.read<AppController>()),
        ),
      ],
      child: const AuthentikApp(),
    ),
  );
}

class AuthentikApp extends StatelessWidget {
  const AuthentikApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.select<AppController, bool>(
      (c) => c.settings.darkMode,
    );
    final ready = context.select<AppController, bool>((c) => c.ready);
    return MaterialApp(
      title: ProductIdentity.name,
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
