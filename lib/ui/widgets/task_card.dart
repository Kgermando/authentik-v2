import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../../services/app_controller.dart';
import 'common.dart';
import 'score_gauge.dart';

/// Ligne de la file d'analyse : anneau animé pendant le traitement, puis
/// résultat cliquable.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, this.onOpen, this.onDismiss});

  final AnalysisTask task;
  final VoidCallback? onOpen;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = task.result;
    final running = task.status == TaskStatus.running;
    final failed = task.status == TaskStatus.failed;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Panel(
        key: ValueKey('${task.id}-${task.status.name}'),
        padding: EdgeInsets.all(running ? 22 : 14),
        borderColor: failed ? p.suspect.withValues(alpha: 0.5) : null,
        child: running ? _running(p) : _row(context, p, r, failed),
      ),
    );
  }

  Widget _running(Palette p) => Row(
    children: [
      ScanRing(progress: task.progress, size: 118),
      const SizedBox(width: 24),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                task.stage,
                key: ValueKey(task.stage),
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: task.progress),
                duration: const Duration(milliseconds: 450),
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 7,
                  backgroundColor: p.line,
                  color: p.accent,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Analyse locale : rien ne quitte cet ordinateur.',
              style: TextStyle(color: p.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _row(BuildContext context, Palette p, AnalysisResult? r, bool failed) {
    final queued = task.status == TaskStatus.queued;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: r != null ? onOpen : null,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 38,
            decoration: BoxDecoration(
              color: failed
                  ? p.suspect
                  : queued
                  ? p.muted
                  : p.verdictColor(r!.verdict),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (task.fromWatcher) ...[
                      Icon(
                        Icons.folder_special_outlined,
                        size: 15,
                        color: p.muted,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  failed
                      ? (task.error ?? 'Échec')
                      : queued
                      ? 'En attente'
                      : '${r!.pageCount} page(s) · ${(r.elapsedMs / 1000).toStringAsFixed(1)} s',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: failed ? p.suspect : p.muted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (r != null) ...[
            Text(
              '${(r.probability * 100).round()} %',
              style: TextStyle(
                fontFamilyFallback: kSerif,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: p.verdictColor(r.verdict),
              ),
            ),
            const SizedBox(width: 12),
            VerdictChip(r.verdict),
          ],
          if (onDismiss != null && (failed || r != null)) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Retirer de la liste',
              onPressed: onDismiss,
              icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
            ),
          ],
        ],
      ),
    );
  }
}
