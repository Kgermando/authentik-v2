import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/score_explanation.dart' show inconclusiveExplanation;
import '../../core/theme.dart';
import '../../services/app_controller.dart';
import 'common.dart';
import 'page_viewer.dart';
import 'reference_panel.dart';
import 'score_explanation_view.dart';
import 'score_gauge.dart';

/// Résultat complet d'une analyse : jauge, contrôles, aperçu annoté,
/// avertissements et décision manuelle.
class ResultView extends StatefulWidget {
  const ResultView({super.key, required this.result});

  final AnalysisResult result;

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  late Set<CheckId> _visible;
  Region? _focus;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _visible = {...CheckId.values};
    _note.text = widget.result.note;
  }

  @override
  void didUpdateWidget(ResultView old) {
    super.didUpdateWidget(old);
    if (old.result.id != widget.result.id) {
      _visible = {...CheckId.values};
      _focus = null;
      _note.text = widget.result.note;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1000;
        final viewer = SizedBox(
          height: wide ? 760 : 520,
          child: Panel(
            padding: const EdgeInsets.all(14),
            child: PageViewer(result: r, visible: _visible, focus: _focus),
          ),
        );
        final side = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summary(context, r),
            const SizedBox(height: 14),
            ScoreExplanationView(result: r, sensitivity: _sensitivity(r)),
            if (r.claimedYear != null) ...[
              const SizedBox(height: 14),
              ReferencePanel(result: r),
            ],
            if (r.warnings.isNotEmpty) ...[
              const SizedBox(height: 14),
              _warnings(context, r),
            ],
            const SizedBox(height: 14),
            _checks(context, r),
            const SizedBox(height: 14),
            _decision(context, r),
          ],
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 11, child: viewer),
              const SizedBox(width: 18),
              Expanded(flex: 10, child: side),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [side, const SizedBox(height: 14), viewer],
        );
      },
    );
  }

  /// Sensibilité du profil utilisé (retrouvé par son nom), 1 à défaut.
  double _sensitivity(AnalysisResult r) {
    final profiles = context.read<AppController>().settings.profiles;
    for (final p in profiles) {
      if (p.name == r.profileName) return p.sensitivity;
    }
    return 1;
  }

  Widget _summary(BuildContext context, AnalysisResult r) {
    final p = Palette.of(context);
    return Panel(
      child: Column(
        children: [
          ScoreGauge(
            probability: r.probability,
            threshold: r.threshold,
            verdict: r.verdict,
          ),
          const SizedBox(height: 8),
          VerdictChip(r.verdict, big: true),
          const SizedBox(height: 6),
          Text(
            switch (r.verdict) {
              Verdict.suspect =>
                'Score au-dessus du seuil : vérification manuelle obligatoire.',
              Verdict.review =>
                'Indices partiels : une vérification manuelle est conseillée.',
              Verdict.authentic =>
                'Aucune anomalie majeure. Cela ne prouve pas l’authenticité.',
              Verdict.inconclusive => inconclusiveExplanation(r),
            },
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Divider(color: p.line, height: 1),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              r.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill('${r.pageCount} page(s)', icon: Icons.description_outlined),
              Pill(
                '${(r.elapsedMs / 1000).toStringAsFixed(1)} s',
                icon: Icons.timer_outlined,
              ),
              Pill(r.profileName, icon: Icons.tune_rounded),
              Pill(formatDate(r.createdAt), icon: Icons.event_outlined),
              InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: r.sha256));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Empreinte SHA-256 copiée')),
                  );
                },
                child: Pill(
                  'SHA-256 ${shortHash(r.sha256)}',
                  icon: Icons.fingerprint_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _warnings(BuildContext context, AnalysisResult r) {
    final p = Palette.of(context);
    return Panel(
      color: p.review.withValues(alpha: 0.08),
      borderColor: p.review.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: p.review),
              const SizedBox(width: 8),
              Text(
                'Fiabilité de l’analyse',
                style: TextStyle(fontWeight: FontWeight.w700, color: p.review),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final w in r.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                w,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }

  Widget _checks(BuildContext context, AnalysisResult r) {
    final p = Palette.of(context);
    final sorted = [...r.checks]
      ..sort((a, b) {
        if (a.skipped != b.skipped) return a.skipped ? 1 : -1;
        return b.score.compareTo(a.score);
      });
    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Contrôles effectués'),
          for (final c in sorted) _checkRow(context, p, c),
        ],
      ),
    );
  }

  Widget _checkRow(BuildContext context, Palette p, CheckResult c) {
    final color = c.skipped
        ? p.muted
        : c.score >= 0.6
        ? p.suspect
        : c.score >= 0.3
        ? p.review
        : p.authentic;
    final hasRegions = c.regions.isNotEmpty;
    final shown = _visible.contains(c.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: p.checkColor(c.id),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  c.id.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (c.skipped)
                Pill('Non évalué', color: p.muted)
              else
                Text(
                  '${(c.score * 100).round()} %',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 14,
                  ),
                ),
              if (hasRegions)
                IconButton(
                  tooltip: shown
                      ? 'Masquer sur l’aperçu'
                      : 'Afficher sur l’aperçu',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    shown ? _visible.remove(c.id) : _visible.add(c.id);
                  }),
                  icon: Icon(
                    shown
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: p.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: c.skipped ? 0 : c.score),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: p.line,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            c.summary,
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35),
          ),
          if (hasRegions)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final reg in c.regions.take(6))
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        'Zone ${(reg.score * 100).round()} %',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      onPressed: () => setState(() {
                        _visible.add(c.id);
                        _focus = reg;
                      }),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _decision(BuildContext context, AnalysisResult r) {
    final p = Palette.of(context);
    final ctrl = context.read<AppController>();
    Widget btn(String label, Decision d, IconData icon, Color color) {
      final selected = r.decision == d;
      return Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            backgroundColor: selected ? color.withValues(alpha: 0.12) : null,
            side: BorderSide(
              color: selected ? color : p.line,
              width: selected ? 1.6 : 1,
            ),
            foregroundColor: selected ? color : p.ink,
          ),
          onPressed: () async {
            await ctrl.setDecision(
              r.id,
              selected ? Decision.none : d,
              note: _note.text.trim(),
            );
            setState(() {});
          },
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      );
    }

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Vérification manuelle'),
          Row(
            children: [
              btn(
                'Authentique',
                Decision.authentic,
                Icons.check_circle_outline_rounded,
                p.authentic,
              ),
              const SizedBox(width: 10),
              btn(
                'Falsifié',
                Decision.fraud,
                Icons.report_gmailerrorred_rounded,
                p.suspect,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Note de vérification (facultatif)',
            ),
            onSubmitted: (_) =>
                ctrl.setDecision(r.id, r.decision, note: _note.text.trim()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Statut : ${r.decision.label}',
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: r.toPrettyJson()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Rapport JSON copié')),
                  );
                },
                icon: const Icon(Icons.copy_all_rounded, size: 18),
                label: const Text('Copier le rapport'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
