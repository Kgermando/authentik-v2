import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../services/app_controller.dart';
import '../../services/database.dart';
import '../../services/reference_controller.dart';
import '../widgets/common.dart';
import '../widgets/drop_zone.dart';
import '../widgets/result_view.dart';
import '../widgets/task_card.dart';

class AnalyzeScreen extends StatelessWidget {
  const AnalyzeScreen({
    super.key,
    required this.onGoToProfiles,
    required this.onGoToReferences,
    required this.onGoToHistory,
  });

  final VoidCallback onGoToProfiles;
  final VoidCallback onGoToReferences;

  /// Ouvre l'historique (les filtres sont posés avant l'appel).
  final VoidCallback onGoToHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final p = Palette.of(context);
    final sel = c.selected;
    final active = c.tasks.where(
      (t) => t.status == TaskStatus.running || t.status == TaskStatus.queued,
    );
    final finished = c.tasks.where(
      (t) => t.status == TaskStatus.done || t.status == TaskStatus.failed,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      children: [
        PageHeader(
          title: 'Analyser un document',
          subtitle:
              'Détecte les sceaux, signatures et dates ajoutés ou retouchés sur un certificat scanné.',
          trailing: _ProfileChip(onTap: onGoToProfiles),
        ),
        if (c.stats != null && c.stats!.total > 0) ...[
          _Stats(stats: c.stats!, onGoToHistory: onGoToHistory),
          const SizedBox(height: 22),
        ],
        _YearSelector(onGoToReferences: onGoToReferences),
        const SizedBox(height: 12),
        DropZone(
          compact: sel != null || c.tasks.isNotEmpty,
          onFiles: c.analyzePaths,
        ),
        if (c.watching) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.radar_rounded, size: 16, color: p.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dossier surveillé : ${c.settings.watchFolder}. Chaque nouveau scan est analysé automatiquement.',
                  style: TextStyle(color: p.muted, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
        if (c.tasks.isNotEmpty) ...[
          const SizedBox(height: 22),
          SectionTitle(
            'File d’analyse',
            trailing: finished.isNotEmpty
                ? TextButton(
                    onPressed: c.clearFinishedTasks,
                    child: const Text('Vider'),
                  )
                : null,
          ),
          for (final t in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TaskCard(task: t),
            ),
          for (final t in finished)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TaskCard(
                task: t,
                onOpen: t.result == null ? null : () => c.select(t.result),
                onDismiss: () => c.dismissTask(t),
              ),
            ),
        ],
        if (sel != null) ...[
          const SizedBox(height: 26),
          const SectionTitle('Résultat'),
          ResultView(key: ValueKey(sel.id), result: sel),
        ],
      ],
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final p = Palette.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Profil de vérification',
      onSelected: (v) {
        if (v == '__edit') {
          onTap();
        } else {
          c.setActiveProfile(v);
        }
      },
      itemBuilder: (_) => [
        for (final pr in c.settings.profiles)
          PopupMenuItem(
            value: pr.id,
            child: Row(
              children: [
                Icon(
                  pr.id == c.profile.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: p.accent,
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(pr.name, softWrap: true)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__edit',
          child: Text('Modifier les profils…'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 18, color: p.accent),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                c.profile.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Pill('seuil ${(c.profile.threshold * 100).round()} %'),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down_rounded, color: p.muted),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.stats, required this.onGoToHistory});

  final DbStats stats;
  final VoidCallback onGoToHistory;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = context.read<AppController>();
    // Chaque tuile ouvre l'historique filtré sur ce qu'elle compte.
    VoidCallback go({Verdict? filter, bool pending = false}) => () {
      c.showHistory(filter: filter, pendingOnly: pending);
      onGoToHistory();
    };
    final tiles = [
      StatTile(
        label: 'Documents analysés',
        value: '${stats.total}',
        icon: Icons.folder_open_rounded,
        linkLabel: 'Tout l’historique',
        onTap: go(),
      ),
      StatTile(
        label: 'Suspects',
        value: '${stats.suspect}',
        color: p.suspect,
        icon: Icons.gpp_maybe_outlined,
        linkLabel: 'Voir les suspects',
        onTap: go(filter: Verdict.suspect),
      ),
      StatTile(
        label: 'À examiner',
        value: '${stats.review}',
        color: p.review,
        icon: Icons.visibility_outlined,
        linkLabel: 'Voir les documents',
        onTap: go(filter: Verdict.review),
      ),
      StatTile(
        label: tr('stats.non_concluants'),
        value: '${stats.inconclusive}',
        color: p.inconclusive,
        icon: Icons.help_outline_rounded,
        linkLabel: 'Voir les documents',
        onTap: go(filter: Verdict.inconclusive),
      ),
      StatTile(
        label: 'En attente de décision',
        value: '${stats.pendingReview}',
        icon: Icons.hourglass_empty_rounded,
        linkLabel: 'Décider maintenant',
        onTap: go(pending: true),
      ),
      StatTile(
        label: 'Suspicion moyenne',
        value: '${(stats.avgProbability * 100).round()} %',
        icon: Icons.insights_rounded,
        linkLabel: 'Tout l’historique',
        onTap: go(),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1100 ? 6 : (c.maxWidth >= 640 ? 3 : 2);
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

/// Choix de l'« année d'émission du document » : années enregistrées avec
/// leur nombre d'originaux, « autre année… » ou aucune (analyse classique).
class _YearSelector extends StatelessWidget {
  const _YearSelector({required this.onGoToReferences});

  final VoidCallback onGoToReferences;

  Future<void> _other(BuildContext context) async {
    final ctrl = TextEditingController();
    final y = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ref.ui.autre_annee')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr('ref.ui.annee')),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('ui.annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: Text(tr('ui.valider')),
          ),
        ],
      ),
    );
    if (y != null && context.mounted) {
      context.read<AppController>().setClaimedYear(y);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final refs = context.watch<ReferenceController>();
    final p = Palette.of(context);
    final years = refs.years;
    final current = c.claimedYear;
    final known = years.any((y) => y.year.year == current);
    String label(int? y) {
      if (y == null) return tr('ref.ui.sans_annee');
      for (final s in years) {
        if (s.year.year == y) {
          return tr('ref.ui.annee_avec_n', {
            'annee': y,
            'n': s.activeOriginals,
          });
        }
      }
      return tr('ref.ui.annee_sans_referentiel', {'annee': y});
    }

    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.event_note_outlined, color: p.accent, size: 20),
          Text(
            tr('ref.ui.annee_emission'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          PopupMenuButton<int>(
            tooltip: tr('ref.ui.annee_emission'),
            onSelected: (v) {
              if (v == -1) {
                c.setClaimedYear(null);
              } else if (v == -2) {
                _other(context);
              } else {
                c.setClaimedYear(v);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: -1, child: Text(tr('ref.ui.sans_annee'))),
              if (years.isNotEmpty) const PopupMenuDivider(),
              for (final y in years.reversed)
                PopupMenuItem(
                  value: y.year.year,
                  child: Text(label(y.year.year)),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(value: -2, child: Text(tr('ref.ui.autre_annee'))),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: current == null ? p.surface : p.accentSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: current == null ? p.line : p.accent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label(current),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: current == null ? p.ink : p.accent,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down_rounded, color: p.muted),
                ],
              ),
            ),
          ),
          if (current != null && !known)
            Text(
              tr('ref.ui.annee_voisines_aide'),
              style: TextStyle(color: p.review, fontSize: 12.5),
            )
          else if (years.isEmpty)
            TextButton(
              onPressed: onGoToReferences,
              child: Text(tr('ref.ui.aller_referentiels')),
            ),
        ],
      ),
    );
  }
}
