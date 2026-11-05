import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../../services/app_controller.dart';
import '../../services/history_export.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.onOpenResult});

  /// Ouvre un résultat de la session dans l'écran d'analyse.
  final void Function(AnalysisResult r) onOpenResult;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  String? _open;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    // Recherche courante (effacée par un lien depuis les statistiques).
    _search.text = context.read<AppController>().historySearch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppController>().refreshHistory();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _exportExcel(AppController c) async {
    final entries = c.visibleHistory();
    if (entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune ligne à exporter pour les filtres actuels.'),
        ),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final bytes = buildHistoryXlsx(entries);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Exporter l’historique en Excel',
        fileName: 'authentik-historique-$stamp.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      if (saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export enregistré (${entries.length} ligne(s)).'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final p = Palette.of(context);
    final offline = c.dbState != DbState.connected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      children: [
        PageHeader(
          title: 'Historique',
          subtitle: offline
              ? 'Historique SQLite indisponible : seules les analyses de cette session sont listées.'
              : 'Analyses enregistrées localement (SQLite). Les documents eux-mêmes ne sont pas conservés.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonalIcon(
                onPressed: _exporting ? null : () => _exportExcel(c),
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.table_view_rounded, size: 18),
                label: const Text('Exporter Excel'),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Actualiser',
                onPressed: c.refreshHistory,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        if (offline) _DbBanner(c: c),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Rechercher un nom de fichier ou une empreinte',
                prefixIcon: Icon(Icons.search_rounded, color: p.muted),
              ),
              onSubmitted: (v) => c.setHistoryQuery(search: v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Tous'),
                  selected: c.historyFilter == null && !c.historyPendingOnly,
                  onSelected: (_) => c.setHistoryQuery(clearFilter: true),
                ),
                for (final v in Verdict.values)
                  FilterChip(
                    label: Text(v.short),
                    selected: c.historyFilter == v,
                    onSelected: (_) => c.setHistoryQuery(filter: v),
                  ),
                FilterChip(
                  avatar: const Icon(Icons.hourglass_empty_rounded, size: 16),
                  label: const Text('En attente de décision'),
                  selected: c.historyPendingOnly,
                  onSelected: (on) =>
                      c.setHistoryQuery(pendingOnly: on, clearFilter: !on),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (c.history.isEmpty)
          Panel(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 40,
                    color: p.muted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Aucune analyse pour le moment',
                    style: TextStyle(color: p.muted),
                  ),
                ],
              ),
            ),
          )
        else
          for (final h in c.visibleHistory())
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Row(
                entry: h,
                open: _open == h.id,
                onToggle: () =>
                    setState(() => _open = _open == h.id ? null : h.id),
                onOpenResult: () {
                  final r = c.sessionResults
                      .where((e) => e.id == h.id)
                      .cast<AnalysisResult?>()
                      .firstWhere((_) => true, orElse: () => null);
                  if (r != null) widget.onOpenResult(r);
                },
                hasPreview: c.sessionResults.any((e) => e.id == h.id),
              ),
            ),
      ],
    );
  }
}

class _DbBanner extends StatelessWidget {
  const _DbBanner({required this.c});

  final AppController c;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Panel(
        color: p.review.withValues(alpha: 0.08),
        borderColor: p.review.withValues(alpha: 0.35),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.storage_rounded, color: p.review),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                c.dbError == null
                    ? 'Historique SQLite non disponible.'
                    : 'SQLite indisponible : ${c.dbError}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            TextButton(onPressed: c.connectDb, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.open,
    required this.onToggle,
    required this.onOpenResult,
    required this.hasPreview,
  });

  final HistoryEntry entry;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onOpenResult;
  final bool hasPreview;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = context.read<AppController>();
    final h = entry;
    final color = p.verdictColor(h.verdict);
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Icon(
                    h.source == 'pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                    color: p.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${formatDate(h.createdAt)} · ${h.profileName}',
                          style: TextStyle(color: p.muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  if (h.decision != Decision.none) ...[
                    Pill(
                      h.decision.label,
                      color: h.decision == Decision.fraud
                          ? p.suspect
                          : p.authentic,
                      icon: h.decision == Decision.fraud
                          ? Icons.report_gmailerrorred_rounded
                          : Icons.check_circle_outline_rounded,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    '${(h.probability * 100).round()} %',
                    style: TextStyle(
                      fontFamilyFallback: kSerif,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  VerdictChip(h.verdict),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: p.muted,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(34, 4, 20, 18),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Pill('${h.pageCount} page(s)'),
                      Pill('seuil ${(h.threshold * 100).round()} %'),
                      Pill('${(h.elapsedMs / 1000).toStringAsFixed(1)} s'),
                      Pill(
                        'SHA-256 ${shortHash(h.sha256)}',
                        icon: Icons.fingerprint_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final ch in h.checks.where((e) => !e.skipped))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              '${(ch.score * 100).round()} %',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${ch.id.label} : ${ch.summary}',
                              style: TextStyle(color: p.muted, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final w in h.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '⚠ $w',
                        style: TextStyle(color: p.review, fontSize: 12.5),
                      ),
                    ),
                  if (h.note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Note : ${h.note}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (hasPreview)
                        FilledButton.tonalIcon(
                          onPressed: onOpenResult,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Rouvrir avec l’aperçu'),
                        ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _confirmDelete(context, c),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: p.suspect,
                        ),
                        label: Text(
                          'Supprimer',
                          style: TextStyle(color: p.suspect),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette analyse ?'),
        content: const Text(
          'La ligne sera retirée de l’historique. Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) await c.deleteEntry(entry.id);
  }
}
