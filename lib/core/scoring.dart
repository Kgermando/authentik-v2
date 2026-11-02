import 'models.dart';

/// Combinaison des contrôles en une probabilité unique.
///
/// Méthode « noisy-OR » : chaque contrôle apporte un indice indépendant
/// `poids × score`, et la probabilité finale est `1 − Π(1 − indice)`.
/// Un seul indice moyen reste donc sous le seuil, alors que plusieurs indices
/// concordants le dépassent. C'est volontaire : un faux positif coûte une
/// vérification manuelle, un faux négatif laisse passer un faux.
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
  };

  static double combine(
    Iterable<CheckResult> results,
    VerificationProfile profile,
  ) {
    var keep = 1.0;
    for (final r in results) {
      if (r.skipped || !profile.enabled.contains(r.id)) continue;
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
    if (probability >= threshold * 0.55) return Verdict.review;
    return Verdict.authentic;
  }
}
