import 'package:authentik_v2/core/models.dart';
import 'package:authentik_v2/core/scoring.dart';
import 'package:flutter_test/flutter_test.dart';

CheckResult _r(CheckId id, double s) => CheckResult(id: id, score: s);

void main() {
  final profile = VerificationProfile(
    id: 't',
    name: 't',
    enabled: {...CheckId.values},
  );

  test('aucun indice : probabilité nulle', () {
    final p = Scoring.combine([_r(CheckId.sealOverlay, 0)], profile);
    expect(p, 0);
  });

  test('un seul indice moyen reste sous le seuil par défaut', () {
    final p = Scoring.combine([_r(CheckId.sealOverlay, 0.8)], profile);
    expect(p, lessThan(profile.threshold));
    expect(Scoring.verdict(p, profile.threshold), isNot(Verdict.suspect));
  });

  test('plusieurs indices concordants dépassent le seuil', () {
    final p = Scoring.combine([
      _r(CheckId.sealOverlay, 0.9),
      _r(CheckId.signatureOverlay, 0.8),
      _r(CheckId.noiseConsistency, 0.7),
    ], profile);
    expect(p, greaterThan(profile.threshold));
    expect(Scoring.verdict(p, profile.threshold), Verdict.suspect);
  });

  test('un contrôle désactivé ou non évalué est ignoré', () {
    final off = profile.copy()..enabled.remove(CheckId.sealOverlay);
    expect(Scoring.combine([_r(CheckId.sealOverlay, 1)], off), 0);
    expect(
      Scoring.combine(
        [const CheckResult(id: CheckId.ela, score: 1, skipped: true)],
        profile,
      ),
      0,
    );
  });

  test('la sensibilité augmente le score', () {
    final strict = profile.copy()..sensitivity = 1.4;
    final lax = profile.copy()..sensitivity = 0.6;
    final a = Scoring.combine([_r(CheckId.textConsistency, 0.7)], strict);
    final b = Scoring.combine([_r(CheckId.textConsistency, 0.7)], lax);
    expect(a, greaterThan(b));
  });

  test('profil : sérialisation aller-retour', () {
    final j = profile.toJson();
    final back = VerificationProfile.fromJson(j);
    expect(back.enabled, profile.enabled);
    expect(back.threshold, profile.threshold);
  });

  test('restauration des profils par défaut conserve les profils personnalisés', () {
    final custom = VerificationProfile(
      id: 'mon-profil',
      name: 'Perso',
      enabled: {CheckId.metadata},
      threshold: 0.8,
    );
    final altered = VerificationProfile.defaults().first.copy()
      ..name = 'Standard modifié'
      ..threshold = 0.9;
    final list = [altered, ...VerificationProfile.defaults().skip(1), custom];
    final restored = VerificationProfile.withRestoredDefaults(list);
    expect(restored.length, 4);
    expect(restored.any((p) => p.id == 'mon-profil'), isTrue);
    final standard = restored.firstWhere((p) => p.id == 'standard');
    expect(standard.name, 'Standard');
    expect(standard.threshold, 0.70);
    expect(restored.firstWhere((p) => p.id == 'certificats').threshold, 0.65);
    expect(restored.firstWhere((p) => p.id == 'rapide').maxPages, 1);
  });
}
