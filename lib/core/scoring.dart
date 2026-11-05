import 'i18n.dart';
import 'models.dart';
import 'scoring_params.dart';

/// Décision finale : probabilité, verdict et justification du forçage.
class ScoreDecision {
  const ScoreDecision({
    required this.probability,
    required this.verdict,
    this.forcedByCritical = false,
    this.notes = const [],
  });

  final double probability;
  final Verdict verdict;
  final bool forcedByCritical;

  /// Explications à afficher (forçage par un contrôle critique).
  final List<String> notes;
}

/// Combinaison des contrôles en une probabilité unique.
///
/// Méthode « noisy-OR » : chaque contrôle apporte un indice indépendant
/// `poids × score`, et la probabilité finale est `1 − Π(1 − indice)`.
/// Un seul indice moyen reste donc sous le seuil, alors que plusieurs indices
/// concordants le dépassent. C'est volontaire : un faux positif coûte une
/// vérification manuelle, un faux négatif laisse passer un faux.
///
/// Les contrôles d'origine (sans statut) contribuent comme avant. Les nouveaux
/// contrôles ne contribuent que s'ils sont en WARNING ou en FAILED.
///
/// Ces poids sont des valeurs de départ à calibrer sur de vrais certificats
/// (authentiques et falsifiés) avec le jeu d'essai du ministère.
class Scoring {
  const Scoring._();

  static const Map<CheckId, double> weights = {
    CheckId.copyMove: 0.75,
    CheckId.sealOverlay: 0.60,
    CheckId.signatureOverlay: 0.55,
    CheckId.textConsistency: 0.45,
    CheckId.noiseConsistency: 0.35,
    CheckId.ela: 0.25,
    CheckId.metadata: 0.40,
    // Référentiel annuel (ne contribuent qu'en WARNING ou FAILED).
    CheckId.sealComparison: 0.55,
    CheckId.sealCopy: 0.85,
    CheckId.originalModified: 0.90,
    // Signature : fiabilité moyenne (variation naturelle du geste).
    CheckId.signatureComparison: 0.35,
    CheckId.signatureCopy: 0.80,
    // Mise en page, position, texte (spécification : 0,12 ; 0,06 ; 0,10,
    // ramenés à l'échelle des poids existants, × 2,2).
    CheckId.layoutComparison: 0.26,
    CheckId.sealSignaturePosition: 0.13,
    CheckId.textYear: 0.22,
    // Papier (0,04 → 0,09, fiabilité faible) ; cohérence d'année (0,15 →
    // 0,33, critique).
    CheckId.paperComparison: 0.09,
    CheckId.yearConsistency: 0.33,
  };

  static double combine(
    Iterable<CheckResult> results,
    VerificationProfile profile,
  ) {
    var keep = 1.0;
    for (final r in results) {
      if (r.skipped || !profile.enabled.contains(r.id)) continue;
      final st = r.status;
      if (st != null && !st.contributes) continue;
      final w = ((weights[r.id] ?? 0.3) * profile.sensitivity)
          .clamp(0.0, 0.95)
          .toDouble();
      keep *= 1 - w * r.score.clamp(0.0, 1.0).toDouble();
    }
    return (1 - keep).clamp(0.0, 1.0).toDouble();
  }

  /// Au-dessus du seuil : suspect. À partir de 55 % du seuil : à examiner.
  static Verdict verdict(double probability, double threshold) {
    if (probability >= threshold) return Verdict.suspect;
    if (probability >= threshold * ScoringParams.reviewFraction) {
      return Verdict.review;
    }
    return Verdict.authentic;
  }

  /// Décision complète :
  /// 1. probabilité et verdict par seuil (inchangés) ;
  /// 2. un contrôle critique en FAILED force « suspect » si sa confiance est
  ///    suffisante, ou impose au moins « à examiner » sur un seuil provisoire ;
  /// 3. une qualité insuffisante donne « non concluant », quoi qu'il arrive.
  static ScoreDecision decide(
    Iterable<CheckResult> results,
    VerificationProfile profile, {
    bool qualityInsufficient = false,
  }) {
    final list = results.toList(growable: false);
    final p = combine(list, profile);
    var v = verdict(p, profile.threshold);
    var forced = false;
    final notes = <String>[];
    for (final r in list) {
      if (!r.critical || r.status != CheckStatus.failed) continue;
      if (!profile.enabled.contains(r.id)) continue;
      final conf = r.confidence ?? 0;
      if (conf >= ScoringParams.criticalForceConfidence) {
        if (v != Verdict.suspect) forced = true;
        v = Verdict.suspect;
        notes.add(tr('fusion.force_suspect', {'controle': r.id.label}));
      } else if (conf >= ScoringParams.criticalReviewConfidence) {
        if (v == Verdict.authentic) {
          v = Verdict.review;
          forced = true;
        }
        notes.add(tr('fusion.force_a_examiner', {'controle': r.id.label}));
      }
    }
    if (qualityInsufficient) v = Verdict.inconclusive;
    return ScoreDecision(
      probability: p,
      verdict: v,
      forcedByCritical: forced,
      notes: notes,
    );
  }
}
