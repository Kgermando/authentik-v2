import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/app_controller.dart';
import '../../services/database.dart';
import '../widgets/common.dart';
import '../widgets/drop_zone.dart';
import '../widgets/result_view.dart';
import '../widgets/task_card.dart';

class AnalyzeScreen extends StatelessWidget {
  const AnalyzeScreen({super.key, required this.onGoToProfiles});

  final VoidCallback onGoToProfiles;

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
          _Stats(stats: c.stats!),
          const SizedBox(height: 22),
        ],
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
                Text(pr.name),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '__edit', child: Text('Modifier les profils…')),
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
  const _Stats({required this.stats});

  final DbStats stats;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tiles = [
      StatTile(
        label: 'Documents analysés',
        value: '${stats.total}',
        icon: Icons.folder_open_rounded,
      ),
      StatTile(
        label: 'Suspects',
        value: '${stats.suspect}',
        color: p.suspect,
        icon: Icons.gpp_maybe_outlined,
      ),
      StatTile(
        label: 'À examiner',
        value: '${stats.review}',
        color: p.review,
        icon: Icons.visibility_outlined,
      ),
      StatTile(
        label: 'En attente de décision',
        value: '${stats.pendingReview}',
        icon: Icons.hourglass_empty_rounded,
      ),
      StatTile(
        label: 'Suspicion moyenne',
        value: '${(stats.avgProbability * 100).round()} %',
        icon: Icons.insights_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 980 ? 5 : (c.maxWidth >= 640 ? 3 : 2);
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
