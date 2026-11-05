import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/identity.dart';
import '../../core/theme.dart';
import '../../services/app_controller.dart';
import '../../services/database.dart' show kSchemaVersion;
import '../../services/reference/admin_code.dart' show AdminCode;
import '../../services/reference_controller.dart';
import '../widgets/common.dart';

/// Code administrateur unique de tous les référentiels : création, puis
/// modification (code actuel exigé).
class _AdminCodePanel extends StatefulWidget {
  const _AdminCodePanel();

  @override
  State<_AdminCodePanel> createState() => _AdminCodePanelState();
}

class _AdminCodePanelState extends State<_AdminCodePanel> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  String? _done;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = context.read<ReferenceController>();
    final configured = c.adminConfigured == true;
    if (_next.text != _confirm.text) {
      setState(() {
        _error = tr('admin.confirmation_differente');
        _done = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    final err = configured
        ? await c.changeCode(_current.text, _next.text)
        : await c.createCode(_next.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err == null) {
        _done = configured ? tr('admin.modifie_ok') : tr('admin.cree_ok');
        _current.clear();
        _next.clear();
        _confirm.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ReferenceController>();
    final p = Palette.of(context);
    final configured = c.adminConfigured == true;
    final enabled = c.dbReady && c.adminConfigured != null && !_busy;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            tr('admin.parametres_titre'),
            trailing: Pill(
              configured ? tr('admin.etat_defini') : tr('admin.etat_absent'),
              color: configured ? p.authentic : p.review,
              icon: configured ? Icons.lock_rounded : Icons.lock_open_rounded,
            ),
          ),
          Text(
            tr('admin.parametres_explication'),
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (!c.dbReady)
            Text(tr('ref.ui.base_requise'), style: TextStyle(color: p.muted))
          else ...[
            if (configured) ...[
              TextField(
                controller: _current,
                obscureText: true,
                enabled: enabled,
                decoration: InputDecoration(labelText: tr('admin.code_actuel')),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _next,
                    obscureText: true,
                    enabled: enabled,
                    decoration: InputDecoration(
                      labelText: configured
                          ? tr('admin.nouveau_code')
                          : tr('admin.code'),
                      helperText: tr('admin.trop_court', {
                        'n': AdminCode.minLength,
                      }),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _confirm,
                    obscureText: true,
                    enabled: enabled,
                    decoration: InputDecoration(
                      labelText: tr('admin.confirmer'),
                      helperText: '',
                    ),
                    onSubmitted: (_) => enabled ? _submit() : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: enabled ? _submit : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          configured ? Icons.key_rounded : Icons.add_rounded,
                          size: 18,
                        ),
                  label: Text(
                    configured ? tr('admin.modifier') : tr('admin.creer'),
                  ),
                ),
                const SizedBox(width: 14),
                if (_error != null)
                  Expanded(
                    child: Text(_error!, style: TextStyle(color: p.suspect)),
                  )
                else if (_done != null)
                  Expanded(
                    child: Text(_done!, style: TextStyle(color: p.authentic)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _folder;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppController>().settings;
    _folder = TextEditingController(text: s.watchFolder);
  }

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Dossier où le scanner dépose ses fichiers',
    );
    if (dir == null || !mounted) return;
    _folder.text = dir;
    final c = context.read<AppController>();
    c.settings.watchFolder = dir;
    await c.saveSettings();
    if (c.settings.watchEnabled) await c.startWatching();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final p = Palette.of(context);
    final (dbColor, dbText) = switch (c.dbState) {
      DbState.connected => (p.authentic, 'Historique local actif'),
      DbState.connecting => (p.review, 'Ouverture…'),
      DbState.failed => (p.suspect, 'Base indisponible'),
      DbState.disconnected => (p.muted, 'Non initialisée'),
    };
    final dbPath = c.db.path ?? '—';
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      children: [
        const PageHeader(
          title: 'Paramètres',
          subtitle:
              'Historique SQLite, dossier surveillé, code administrateur '
              'et apparence.',
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                'Historique SQLite',
                trailing: Pill(dbText, color: dbColor, icon: Icons.circle),
              ),
              Text(
                'Les analyses sont enregistrées dans un fichier SQLite sur cet '
                'ordinateur. Aucun serveur réseau n’est requis.',
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Fichier de base'),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        dbPath,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copier le chemin',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: dbPath));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Chemin copié')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              if (c.dbNotice != null && c.dbState == DbState.connected)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Text(
                    c.dbNotice!,
                    style: TextStyle(color: p.muted, fontSize: 12.5),
                  ),
                ),
              if (c.dbError != null && c.dbState != DbState.connected)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Text(
                    c.dbError!,
                    style: TextStyle(color: p.suspect, fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: c.dbState == DbState.connecting
                        ? null
                        : c.connectDb,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Réouvrir la base'),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Variable AUTHENTIK_DB_PATH pour un autre emplacement. '
                      '${tr('base.info_schema')}',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Dossier surveillé (scanner)'),
              Text(
                'Configurez le scanner pour enregistrer ses numérisations dans un dossier. '
                '${ProductIdentity.shortName} analyse automatiquement chaque nouveau fichier qui y arrive, '
                'sans avoir à le glisser.',
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _folder,
                      decoration: const InputDecoration(labelText: 'Dossier'),
                      onSubmitted: (v) async {
                        c.settings.watchFolder = v.trim();
                        await c.saveSettings();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _pickFolder,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Choisir'),
                  ),
                ],
              ),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Analyser automatiquement les nouveaux fichiers',
                  ),
                  subtitle: c.watchError != null
                      ? Text(c.watchError!, style: TextStyle(color: p.suspect))
                      : (c.watching
                            ? const Text('Surveillance active')
                            : const Text('Surveillance arrêtée')),
                  value: c.settings.watchEnabled,
                  onChanged: (v) async {
                    c.settings.watchFolder = _folder.text.trim();
                    c.settings.watchEnabled = v;
                    await c.saveSettings();
                    if (v) {
                      await c.startWatching();
                    } else {
                      await c.stopWatching();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _AdminCodePanel(),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Apparence'),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Thème sombre'),
                  value: c.settings.darkMode,
                  onChanged: c.toggleDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          color: p.accentSoft.withValues(alpha: p.dark ? 0.5 : 0.7),
          borderColor: p.accent.withValues(alpha: 0.3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: p.accent, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'À propos de la fiabilité',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${ProductIdentity.name} estime une probabilité de falsification à partir d’indices '
                'visuels (ruptures de fond autour des sceaux et signatures, encre des mots, '
                'grain du papier, duplications, métadonnées). Aucun détecteur n’est fiable '
                'à 100 % : un score élevé signale un document à vérifier manuellement, un '
                'score bas ne prouve pas l’authenticité. Les scans de bonne qualité '
                '(300 DPI, sans compression forte) donnent les meilleurs résultats. '
                'L’analyse est entièrement locale et le document n’est jamais enregistré.',
                style: TextStyle(fontSize: 13, height: 1.45, color: p.ink),
              ),
              const SizedBox(height: 10),
              Text(
                '${ProductIdentity.name} · '
                '${tr('apropos.editeur', {'editeur': ProductIdentity.publisher})} · '
                '${ProductIdentity.copyright} · '
                '${tr('apropos.version_schema', {'version': kSchemaVersion})}',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
