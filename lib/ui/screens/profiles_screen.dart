import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../../services/app_controller.dart';
import '../widgets/common.dart';

/// Profils de vérification : choix des éléments à contrôler contre le
/// Photoshop (sceau, signature, date…) et réglage de la sévérité.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  String? _editingId;

  Future<void> _confirmRestoreDefaults(AppController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer les profils par défaut ?'),
        content: const Text(
          'Standard, Certificats et Rapide seront remis à leurs réglages '
          'd’origine (contrôles, seuil, sensibilité, pages et DPI).\n\n'
          'Vos profils personnalisés (copies ou créations) seront conservés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await c.restoreDefaultProfiles();
    setState(() => _editingId = c.settings.activeProfileId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profils Standard, Certificats et Rapide restaurés.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final p = Palette.of(context);
    final profiles = c.settings.profiles;
    final editing = profiles.firstWhere(
      (e) => e.id == (_editingId ?? c.profile.id),
      orElse: () => c.profile,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final list = _list(context, c, profiles, editing);
        final editor = _Editor(
          key: ValueKey(editing.id),
          profile: editing,
          isActive: editing.id == c.settings.activeProfileId,
          canDelete: profiles.length > 1,
          onChanged: () => c.saveSettings(),
          onActivate: () => c.setActiveProfile(editing.id),
          onDelete: () {
            final wasActive = editing.id == c.settings.activeProfileId;
            c.settings.profiles.removeWhere((e) => e.id == editing.id);
            if (wasActive) {
              c.settings.activeProfileId = c.settings.profiles.first.id;
            }
            setState(() => _editingId = null);
            c.saveSettings();
          },
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
          children: [
            PageHeader(
              title: 'Profils de vérification',
              subtitle:
                  'Choisissez quels éléments contrôler contre les montages Photoshop (sceau, signature, date…) et à partir de quel score un document devient suspect.',
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _confirmRestoreDefaults(c),
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('Restaurer les profils par défaut'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      final base = editing.copy();
                      final np = VerificationProfile(
                        id: newId(),
                        name: '${base.name} (copie)',
                        enabled: base.enabled,
                        threshold: base.threshold,
                        sensitivity: base.sensitivity,
                        maxPages: base.maxPages,
                        renderDpi: base.renderDpi,
                      );
                      c.settings.profiles.add(np);
                      setState(() => _editingId = np.id);
                      c.saveSettings();
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nouveau profil'),
                  ),
                ],
              ),
            ),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 300, child: list),
                  const SizedBox(width: 20),
                  Expanded(child: editor),
                ],
              )
            else ...[
              list,
              const SizedBox(height: 16),
              editor,
            ],
            const SizedBox(height: 20),
            Text(
              'Les poids de chaque contrôle sont des valeurs de départ. Calibrez le seuil '
              'sur des certificats authentiques et falsifiés connus avant un usage officiel.',
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
            ),
          ],
        );
      },
    );
  }

  Widget _list(
    BuildContext context,
    AppController c,
    List<VerificationProfile> profiles,
    VerificationProfile editing,
  ) {
    final p = Palette.of(context);
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          for (final pr in profiles)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _editingId = pr.id),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: pr.id == editing.id ? p.accentSoft : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      pr.id == c.settings.activeProfileId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: p.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pr.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${pr.enabled.length} contrôles · seuil ${(pr.threshold * 100).round()} %',
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                        ],
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

class _Editor extends StatefulWidget {
  const _Editor({
    super.key,
    required this.profile,
    required this.isActive,
    required this.canDelete,
    required this.onChanged,
    required this.onActivate,
    required this.onDelete,
  });

  final VerificationProfile profile;
  final bool isActive;
  final bool canDelete;
  final VoidCallback onChanged;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.name,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _touch(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pr = widget.profile;
    final groups = <String, List<CheckId>>{};
    for (final id in CheckId.values) {
      groups.putIfAbsent(id.group, () => []).add(id);
    }
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nom du profil'),
                  onChanged: (v) {
                    pr.name = v.isEmpty ? 'Profil' : v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              if (widget.isActive)
                const Pill('Profil actif', icon: Icons.check_rounded)
              else
                FilledButton.tonal(
                  onPressed: widget.onActivate,
                  child: const Text('Utiliser ce profil'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionTitle('Éléments à contrôler'),
          for (final e in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text(
                e.key,
                style: TextStyle(
                  color: p.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            for (final id in e.value)
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: pr.enabled.contains(id),
                  title: Text(
                    id.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    id.description,
                    style: TextStyle(
                      color: p.muted,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                  onChanged: (v) => _touch(() {
                    if (v) {
                      pr.enabled.add(id);
                    } else if (pr.enabled.length > 1) {
                      pr.enabled.remove(id);
                    }
                  }),
                ),
              ),
          ],
          const SizedBox(height: 24),
          const SectionTitle('Sévérité'),
          _slider(
            context,
            label: 'Seuil « suspect »',
            help:
                'Au-delà de ce score, le document est suspect et exige une vérification manuelle.',
            value: pr.threshold,
            min: 0.5,
            max: 0.95,
            divisions: 45,
            format: (v) => '${(v * 100).round()} %',
            onChanged: (v) => _touch(() => pr.threshold = v),
          ),
          _slider(
            context,
            label: 'Sensibilité des contrôles',
            help:
                'Plus élevée : détecte davantage, avec plus de faux positifs.',
            value: pr.sensitivity,
            min: 0.6,
            max: 1.4,
            divisions: 16,
            format: (v) => '×${v.toStringAsFixed(2)}',
            onChanged: (v) => _touch(() => pr.sensitivity = v),
          ),
          const SizedBox(height: 8),
          const SectionTitle('Lecture du document'),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: pr.renderDpi,
                  decoration: const InputDecoration(
                    labelText: 'Résolution de rendu des PDF',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 150,
                      child: Text('150 DPI (rapide)'),
                    ),
                    DropdownMenuItem(value: 200, child: Text('200 DPI')),
                    DropdownMenuItem(
                      value: 300,
                      child: Text('300 DPI (recommandé)'),
                    ),
                    DropdownMenuItem(
                      value: 400,
                      child: Text('400 DPI (précis, lent)'),
                    ),
                  ],
                  onChanged: (v) => _touch(() => pr.renderDpi = v ?? 300),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: pr.maxPages,
                  decoration: const InputDecoration(
                    labelText: 'Pages analysées par PDF',
                  ),
                  items: [
                    for (var i = 1; i <= 6; i++)
                      DropdownMenuItem(value: i, child: Text('$i page(s)')),
                  ],
                  onChanged: (v) => _touch(() => pr.maxPages = v ?? 3),
                ),
              ),
            ],
          ),
          if (widget.canDelete) ...[
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: p.suspect,
                  size: 18,
                ),
                label: Text(
                  'Supprimer ce profil',
                  style: TextStyle(color: p.suspect),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required String help,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
  }) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                format(value),
                style: TextStyle(fontWeight: FontWeight.w700, color: p.accent),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
          Text(help, style: TextStyle(color: p.muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}
