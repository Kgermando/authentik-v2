import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/identity.dart';
import '../core/theme.dart';
import '../services/app_controller.dart';
import 'screens/analyze_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profiles_screen.dart';
import 'screens/references_screen.dart';
import 'screens/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _items = <(IconData, IconData, String)>[
    (
      Icons.document_scanner_outlined,
      Icons.document_scanner_rounded,
      'Analyse',
    ),
    (Icons.history_rounded, Icons.history_rounded, 'Historique'),
    (
      Icons.collections_bookmark_outlined,
      Icons.collections_bookmark,
      'Référentiels',
    ),
    (Icons.tune_rounded, Icons.tune_rounded, 'Profils'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Paramètres'),
  ];

  Widget _page() => switch (_index) {
    0 => AnalyzeScreen(
      onGoToProfiles: () => setState(() => _index = 3),
      onGoToReferences: () => setState(() => _index = 2),
      onGoToHistory: () => setState(() => _index = 1),
    ),
    1 => HistoryScreen(
      onOpenResult: (r) {
        context.read<AppController>().select(r);
        setState(() => _index = 0);
      },
    ),
    2 => const ReferencesScreen(),
    3 => const ProfilesScreen(),
    _ => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = context.watch<AppController>();
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 860;
        final body = AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(_index),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1380),
                child: _page(),
              ),
            ),
          ),
        );
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                _Sidebar(
                  index: _index,
                  onSelect: (i) => setState(() => _index = i),
                  items: _items,
                  c: c,
                ),
                VerticalDivider(width: 1, color: p.line),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            backgroundColor: p.bg,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 20,
            title: const _Brand(),
          ),
          body: body,
          bottomNavigationBar: NavigationBar(
            backgroundColor: p.surface,
            indicatorColor: p.accentSoft,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final it in _items)
                NavigationDestination(
                  icon: Icon(it.$1),
                  selectedIcon: Icon(it.$2, color: p.accent),
                  label: it.$3,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.accent, width: 2.4),
          ),
          child: Center(
            child: Text(
              'A',
              style: TextStyle(
                fontFamilyFallback: kSerif,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: p.accent,
                height: 1,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ProductIdentity.shortName,
              style: TextStyle(
                fontFamilyFallback: kSerif,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: p.ink,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'v2 · détection de faux',
              style: TextStyle(color: p.muted, fontSize: 11.5, height: 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.items,
    required this.c,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<(IconData, IconData, String)> items;
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (dbColor, dbText) = switch (c.dbState) {
      DbState.connected => (p.authentic, 'Historique SQLite'),
      DbState.connecting => (p.review, 'Ouverture SQLite…'),
      DbState.failed => (p.suspect, 'SQLite indisponible'),
      DbState.disconnected => (p.muted, 'SQLite non ouvert'),
    };
    return Container(
      width: 244,
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 6, bottom: 30),
            child: _Brand(),
          ),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _NavItem(
                icon: i == index ? items[i].$2 : items[i].$1,
                label: items[i].$3,
                selected: i == index,
                badge: i == 0 && c.busy,
                onTap: () => onSelect(i),
              ),
            ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: c.dbState == DbState.connected ? null : c.connectDb,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dbColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      dbText,
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? p.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 21, color: selected ? p.accent : p.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? p.accent : p.ink,
                ),
              ),
            ),
            if (badge)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: p.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
