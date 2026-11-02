# Authentik v2

Logiciel de bureau (Windows, macOS, Linux) qui aide à repérer les **certificats falsifiés par
montage** : sceau ou signature copiés d'un document authentique puis collés sur un autre
contenu, date ou nom retouchés avec Photoshop.

Conçu pour le département des ressources humaines du ministère de la Formation Professionnelle
(RDC). Flutter + Dart, analyse **100 % locale**, historique dans **SQLite**, sans Docker.

> **Fiabilité.** Aucun détecteur n'est fiable à 100 %. Authentik estime une probabilité de
> falsification à partir d'indices visuels. Au-delà du seuil du profil (70 % par défaut), le
> document est *suspect* et demande une vérification manuelle ; un score bas ne prouve pas
> l'authenticité. Les poids sont des valeurs de départ à calibrer sur de vrais certificats.

## Fonctions

- **Dépôt de fichier** : PDF (multi-pages), PNG, JPG, TIFF, BMP, WEBP — glisser-déposer ou clic.
- **Dossier surveillé** : le scanner dépose ses numérisations dans un dossier, chaque nouveau
  fichier est analysé automatiquement (sans pilote de scanner, identique sur tous les OS).
- **Profils de vérification** : choisir les éléments à contrôler (sceau, signature, date et
  texte, grain du papier, duplication, ELA, métadonnées), le seuil « suspect » et la sensibilité.
- **Résultat** : jauge animée avec repère du seuil, détail de chaque contrôle, aperçu de la page
  avec les zones suspectes surlignées, décision manuelle (authentique / falsifié) et note.
- **Historique SQLite** : empreinte SHA-256, score, contrôles, zones, décision humaine.
  Le document et ses images ne sont **jamais** enregistrés.
- **Export Excel** : export de l'historique filtré en fichier `.xlsx` depuis l'écran Historique.

## Comment la détection fonctionne

| Contrôle | Principe |
| --- | --- |
| Sceau / signature superposés | Autour de chaque tampon ou tracé, on mesure sur des anneaux successifs la rupture de niveau de gris, de teinte et de grain du papier. Un élément collé laisse une marche à la frontière de la découpe. |
| Texte et dates modifiés | Chaque mot est comparé aux mots de même corps : encre, épaisseur du trait, netteté des bords. |
| Grain du papier | Zones dont le bruit haute fréquence diffère du reste de la page. |
| Duplication | Points ORB quasi identiques avec un même déplacement (sceau copié deux fois). |
| ELA | Écarts de recompression JPEG, signal faible utilisé en renfort. |
| Métadonnées | Logiciel de retouche dans le fichier, date de modification postérieure à la création. |

Les scores sont combinés par « noisy-OR » : un indice isolé reste sous le seuil, plusieurs
indices concordants le dépassent.

## Icône de l'application

L'icône Authentik (lettre « A », papier chaud, sceau) remplace l'icône Flutter par défaut
sur Windows et macOS. Source : `assets/branding/icon_source.png`.

Pour régénérer les tailles après modification du visuel :

```bash
python tool/generate_icons.py   # nécessite Pillow : pip install Pillow
```

## Paquet MSIX (Windows)

| Fichier | Rôle |
| --- | --- |
| **`Build-MSIX.bat`** | Build + MSIX → `tool\dist\` |
| **`Install-Authentik.bat`** | Installe certificat + MSIX (UAC admin) |

Clés de signature : **`tool\signing\`** uniquement (PFX local, voir `tool/signing/README.md`).

Distribution : copiez **`tool\dist\`** (`Authentik_v2.msix`, `Authentik_v2_Publisher.cer`, `Install.bat`).
Ne pas installer le `.msix` seul (erreur 0x800B0109 sans certificat approuvé).

## Installation

Prérequis : Flutter (stable).

```bash
./tool/setup.sh          # ou  .\tool\setup.ps1  sous PowerShell
flutter run -d windows   # ou macos / linux
```

`setup` génère les dossiers de plateforme (`flutter create`) et ajoute les paquets :
`provider`, `file_picker`, `desktop_drop`, `pdfrx`, `opencv_dart`, `sqflite`,
`sqflite_common_ffi`, `path_provider`, `path`, `crypto`, `archive`.

### Historique SQLite

1. Au premier lancement, un fichier `history.db` est créé dans le dossier support de
   l'application (voir **Paramètres → Historique SQLite** pour le chemin exact).
2. Variable optionnelle : `AUTHENTIK_DB_PATH=C:\chemin\vers\history.db`
3. La table `analyses` est créée automatiquement. Si le fichier est inaccessible,
   l'application fonctionne et garde l'historique de la session.

## Bonnes pratiques de scan

- 300 DPI minimum, couleur, sans compression JPEG forte, document bien à plat.
- Éviter les recadrages et retouches automatiques du scanner (« amélioration de document »).
- Pour les certificats à fond décoratif ou filigrane, certains contrôles sont moins fiables :
  l'application l'indique dans le résultat.

## Développement

```bash
flutter analyze
flutter test        # algorithmes testés en Dart pur, sans bibliothèque native
```

Structure : `lib/core` (modèles, scoring, thème), `lib/services` (base, réglages, chargeur de
documents, contrôleur), `lib/services/analyzer` (moteur : `image_ops`, `page_context`, contrôles,
`cv_adapter` = seul fichier qui utilise OpenCV), `lib/ui` (écrans et composants).
