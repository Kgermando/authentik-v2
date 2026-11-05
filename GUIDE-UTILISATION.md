# Authentik v2 — Guide d’utilisation

**À qui s’adresse ce guide.** Aux agents qui vérifient des certificats (ressources humaines, formation professionnelle). Aucune connaissance informatique n’est demandée : suivez les étapes dans l’ordre.

**Ce que fait le logiciel.** Authentik aide à repérer un certificat **falsifié par montage** : un sceau ou une signature copiés depuis un vrai document puis collés sur un autre, une date ou un nom retouchés à l’ordinateur.

**Ce qu’il ne fait pas.** Il ne remplace pas un œil humain. Un score élevé veut dire « à vérifier à la main ». Un score bas **ne prouve pas** que le document est authentique.

Ouvrez **Authentik v2** depuis le menu Démarrer.

---

## 1. L’écran d’accueil

À gauche (ou en bas sur un petit écran), quatre onglets :

| Onglet | À quoi ça sert |
| --- | --- |
| **Analyse** | Déposer un fichier et voir le résultat |
| **Historique** | Retrouver les analyses déjà faites |
| **Profils** | Choisir ce que le logiciel contrôle |
| **Paramètres** | Dossier du scanner, thème, fichier d’historique |

Pour le travail de tous les jours, vous resterez surtout sur **Analyse**.

En haut à droite de l’écran Analyse, le **profil actif** s’affiche (par exemple *Standard*, seuil 70 %). C’est le « mode de contrôle » utilisé pour le prochain fichier.

---

## 2. Analyser un certificat — le geste du quotidien

### Quels fichiers sont acceptés

- PDF (plusieurs pages possibles)
- Images : PNG, JPG, JPEG, TIFF, TIF, BMP, WEBP

Word, Excel ou une photo dans un e-mail ne s’ouvrent pas tels quels. Enregistrez d’abord le document en PDF ou en image.

### Comment déposer le fichier

Deux façons, au choix :

1. **Glisser-déposer** : prenez le fichier dans l’Explorateur Windows et déposez-le dans le grand cadre en pointillés.
2. **Clic** : cliquez dans ce cadre, choisissez le fichier, validez.

Vous pouvez déposer **plusieurs fichiers d’un coup**. Ils s’analysent les uns après les autres.

### Pendant l’analyse

Une carte apparaît dans la **file d’analyse** (barre de progression). Attendez qu’elle soit terminée. Un PDF de plusieurs pages peut prendre quelques secondes à une minute.

Quand c’est fini, cliquez sur la carte pour ouvrir le **résultat**.

---

## 3. Lire le résultat sans se tromper

Le résultat a trois parties : une **jauge**, le **détail des contrôles**, et l’**aperçu** du document.

### La jauge (score)

Le pourcentage est une **probabilité de falsification estimée**, pas une vérité.

| Indication | Signification | Que faire |
| --- | --- | --- |
| **Suspect** | Le score dépasse le seuil du profil (70 % par défaut) | Vérification manuelle **obligatoire** |
| **À examiner** | Des indices existent, mais pas assez pour conclure | Vérification manuelle **conseillée** |
| **Aucune anomalie majeure** / **Conforme** | Rien de marquant n’a été vu | Cela **ne prouve pas** l’authenticité. Continuez votre procédure habituelle si le dossier est sensible. |

Le trait sur la jauge marque le **seuil**. Au-delà : suspect.

### Les contrôles (liste à droite)

Chaque ligne est un test. Plus la barre est remplie, plus ce test a trouvé quelque chose.

| Contrôle | En français courant |
| --- | --- |
| Sceau superposé | Tampon qui semble collé (bords, fond, grain différents) |
| Signature superposée | Signature ajoutée après coup |
| Texte et dates modifiés | Encre ou netteté différentes sur les mots (dates, noms, numéros) |
| Éléments dupliqués | Le même sceau ou bloc copié deux fois |
| Grain du papier | Zones dont le « bruit » du papier ne ressemble pas au reste |
| Niveaux de compression (ELA) | Traces de recompression JPEG (indice faible, en renfort) |
| Métadonnées | Logiciel de retouche (Photoshop, etc.) ou date de fichier étrange |

Cliquez sur **Zone … %** pour zoomer l’aperçu sur l’endroit signalé. L’œil (icône visibilité) masque ou affiche les surlignages.

### Encadré « Fiabilité de l’analyse »

S’il apparaît, lisez-le. Exemples : scan flou, fond décoratif, filigrane. Dans ces cas, le logiciel est **moins sûr** : la décision humaine compte encore plus.

### Votre décision (obligatoire sur un dossier officiel)

En bas : **Vérification manuelle**.

1. Regardez le papier (ou le scan) vous-même.
2. Cliquez **Authentique** ou **Falsifié**.
3. Ajoutez une **note** si besoin (motif, nom du vérificateur, n° de dossier).
4. Le statut s’enregistre dans l’historique.

Cette décision est **la vôtre**. Le logiciel propose un avis ; vous tranchez.

---

## 4. Historique

Onglet **Historique**.

- Chaque analyse laisse une **fiche** (nom du fichier, date, score, votre décision).
- Le **document lui-même n’est jamais enregistré** (ni l’image, ni le PDF). Seul le compte-rendu reste.
- Champ de recherche : nom de fichier ou empreinte.
- Puces **Tous / Conforme / À examiner / Suspect** : filtrer la liste.
- **Exporter Excel** : enregistre un tableau `.xlsx` des lignes **actuellement filtrées**. Choisissez où le sauver.
- L’icône de rafraîchissement recharge la liste.

Si un bandeau orange indique que l’historique est indisponible, cliquez **Réessayer**. L’analyse continue quand même ; seules les fiches de **cette session** restent visibles jusqu’à la réouverture.

---

## 5. Profils de vérification

Onglet **Profils**. Un profil = « ce que je contrôle, et à partir de quel score c’est suspect ».

### Les trois profils fournis

| Profil | Quand l’utiliser |
| --- | --- |
| **Standard** | Usage habituel. Tous les contrôles, seuil 70 %, jusqu’à 3 pages, 300 DPI. |
| **Certificats (sceau + signature + date)** | Certificats de formation / diplômes. Seuil un peu plus bas (65 %). |
| **Rapide** | File d’attente longue. Sceau, signature et métadonnées seulement, 1 page, 200 DPI. Moins précis. |

### Changer de profil pour la prochaine analyse

Sur l’écran **Analyse**, cliquez le bandeau du profil (en haut à droite) et choisissez-en un autre.

### Adapter un profil (si on vous le demande)

1. Onglet **Profils**.
2. Cliquez le profil à gauche.
3. Activez ou désactivez les interrupteurs (il doit en rester au moins un).
4. **Seuil « suspect »** : plus il est bas, plus de documents seront marqués suspects.
5. **Sensibilité** : plus elle est haute, plus le logiciel « voit » — y compris des fausses alertes.
6. **Pages** et **DPI** : 300 DPI est recommandé pour un certificat. 150 DPI va plus vite, mais voit moins bien.

**Nouveau profil** : copie le profil affiché. Renommez-le. Les profils fournis peuvent être **restaurés** sans effacer vos copies.

Avant un usage officiel, faites un essai sur quelques **vrais** certificats et quelques **faux connus**, puis ajustez le seuil avec un responsable.

---

## 6. Paramètres utiles

### Dossier surveillé (scanner)

Si le scanner enregistre déjà les pages dans un dossier Windows :

1. Onglet **Paramètres**.
2. **Choisir** le dossier (celui où tombent les scans).
3. Activez **Analyser automatiquement les nouveaux fichiers**.

Dès qu’un PDF ou une image arrive dans ce dossier, Authentik l’analyse **sans glisser-déposer**. Un bandeau « Dossier surveillé » s’affiche sur l’écran Analyse.

Désactivez l’interrupteur pour arrêter la surveillance.

### Thème sombre

Paramètres → **Thème sombre**. Confort visuel seulement ; cela ne change pas l’analyse.

### Fichier d’historique

Les fiches sont stockées **sur cet ordinateur**, dans un fichier local. Le chemin s’affiche sous **Historique SQLite**. Bouton **Copier** pour le donner au service informatique si besoin.

Rien n’est envoyé sur Internet.

---

## 7. Bien scanner, pour de meilleurs résultats

Le logiciel voit ce que le scan lui donne.

**À faire**

- 300 DPI minimum
- Couleur
- Document bien à plat, sans coin plié
- Enregistrement PNG, TIFF, ou PDF **peu compressé**

**À éviter**

- Photo floue au téléphone, de travers, avec de l’ombre
- Compression JPEG forte (« qualité faible »)
- Recadrage agressif
- Options du scanner du type « améliorer le document », « blanchir le fond », « netteté automatique »

Un certificat à **fond décoratif** ou **filigrane** est plus difficile : lisez l’encadré de fiabilité et confirmez à la main.

---

## 8. Questions fréquentes

**Le logiciel dit « aucune anomalie majeure ». Je peux classer le dossier ?**  
Non, pas sur ce seul avis. C’est un indice parmi d’autres (original papier, cachet humide, registres, etc.).

**Le logiciel dit « suspect ». Le document est forcément faux ?**  
Non. Un mauvais scan, un tampon usé ou un fond chargé peuvent aussi faire monter le score. Ouvrez l’aperçu, regardez les zones, puis décidez.

**Puis-je analyser un document Word ?**  
Exportez-le d’abord en PDF, ou scannez le papier.

**Où sont stockées les images ?**  
Les images ne sont **pas** conservées. Elles restent en mémoire le temps de l’analyse, puis disparaissent. Seuls le nom du fichier, le score, les contrôles et votre décision sont gardés.

**J’ai perdu le résultat à l’écran.**  
Onglet **Historique**. La fiche est là. L’aperçu annoté n’est disponible que pour les analyses de **la session en cours** (tant que le logiciel n’a pas été fermé).

**Plusieurs personnes sur le même PC.**  
L’historique est celui de **cet ordinateur**. Exportez Excel si vous devez transmettre un tableau.

---

## 9. Rappel pour le service

- Analyse **100 % locale** : pas de serveur, pas d’envoi du certificat.
- Outil d’**aide à la décision**, pas un verdict juridique.
- En cas de doute : vérifier le papier, comparer à un spécimen authentique, consigner la décision dans Authentik.

---

*Authentik v2 · MFP · Guide de prise en main*
