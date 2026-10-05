<div align="center">

<img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" alt="Icône OtterIsland">

# OtterIsland

**L'encoche de ton MacBook devient une île vivante** : presse-papier, captures, moniteur système,
mode présentateur, agenda, musique… et une petite loutre de compagnie.

[![Dernière version](https://img.shields.io/github/v/release/RoYaL63/OtterIsland?label=version&color=5EE9D3)](https://github.com/RoYaL63/OtterIsland/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

### [⬇️ Télécharger OtterIsland.dmg](https://github.com/RoYaL63/OtterIsland/releases/latest/download/OtterIsland.dmg)

<sub>Gratuit et open source · macOS 14 ou plus récent · Mac à encoche ou non</sub>

</div>

---

## Communauté et soutien

🦦 **Rejoignez-moi sur la [communauté Cube](https://ressources.cube.fr/l/j4nb7bn)** pour échanger ou co-construire des apps.

💛 **Soutenez-moi en utilisant mes liens de parrainage :**

- [Hostinger](https://hostinger.fr?REFERRALCODE=5QYMAILLEWXJ)
- [Lovable](https://lovable.dev/invite/265ZPB4)
- [Dreamflow](https://dreamflow.app/?grsf=augustin-0dlzrd)
- [Wispr Flow](https://wisprflow.ai/r?AUGUSTIN29)
- [Comet (Perplexity)](https://www.perplexity.ai/browser/invite-ga)
- [École Cube](https://ressources.cube.fr/l/myd27c7)
- [Proton](https://pr.tn/ref/6YCJEFG7)

---

## Sommaire

- [Installer](#installer)
- [Fonctionnalités](#fonctionnalités)
  - [L'île](#lîle) · [Presse-papier](#presse-papier) · [Captures d'écran](#captures-décran) · [Moniteur](#moniteur)
  - [Live — mode présentateur](#live--mode-présentateur) · [Nettoyage du clavier](#nettoyage-du-clavier)
  - [Agenda, musique, étagère, miroir, Pomodoro](#agenda-musique-étagère-miroir-pomodoro) · [Inbox Claude Code](#inbox-claude-code)
- [Autorisations macOS](#autorisations-macos)
- [Confidentialité : clés, comptes, données personnelles](#confidentialité--clés-comptes-données-personnelles)
- [Mettre à jour · désinstaller](#mettre-à-jour--désinstaller)
- [Compiler, forker, contribuer](#compiler-forker-contribuer)
- [Communauté et soutien](#communauté-et-soutien)

---

## Installer

1. Télécharge **[OtterIsland.dmg](https://github.com/RoYaL63/OtterIsland/releases/latest/download/OtterIsland.dmg)**, ouvre-le et glisse la loutre sur **Applications**.
2. Au premier lancement, macOS bloque l'app : elle n'est pas notarisée (pas de compte Apple Developer payant). Autorise-la **une seule fois** — sans `sudo` ni droits admin :

   - **Sans Terminal** : clique **OK** sur l'alerte, puis **Réglages Système › Confidentialité et sécurité**, tout en bas : **Ouvrir quand même**, et valide (Touch ID ou mot de passe de session). Depuis macOS 15, le clic droit › Ouvrir ne suffit plus.
   - **Ou dans le Terminal** :

     ```bash
     xattr -dr com.apple.quarantine /Applications/OtterIsland.app
     ```

   > `sudo spctl --add` n'est plus supporté sur les macOS récents. Et `spctl -a -vv` affichera toujours `rejected` : il évalue l'app « comme si elle venait d'être téléchargée », alors qu'au lancement Gatekeeper ne contrôle que les apps marquées en quarantaine.

3. Lance OtterIsland. Elle vit dans l'encoche et dans la barre des menus (🦦) — pas d'icône dans le Dock.

> Lancée ailleurs que dans `/Applications` (Téléchargements, l'image disque…), l'app **propose de s'y installer toute seule**. Ce n'est pas cosmétique : hors de `/Applications`, macOS ne lui donne pas d'identité stable et les autorisations ne tiennent pas.

---

## Fonctionnalités

### L'île

- **Au survol**, l'encoche s'ouvre en carte : accueil (batterie, mémoire, prochain rendez-vous, Pomodoro), presse-papier, captures, moniteur, musique, agenda, étagère, miroir.
- **Pas d'ouverture intempestive** : il faut que le pointeur s'**arrête** sur l'encoche (délai réglable). Traverser la zone pour cliquer un onglet de navigateur n'ouvre rien.
- **Molette** au-dessus de l'encoche pour ouvrir ou fermer.
- **HUD de volume** dans l'encoche.
- **Loutre de compagnie** en pixel-art (désactivée par défaut) : elle nage quand la musique joue, s'inquiète quand la batterie ou la mémoire saturent, fête un Pomodoro terminé.
- Design Liquid Glass, réglages fins de taille et de position par écran.

### Presse-papier

- **⌥V** (modifiable) depuis n'importe quel champ de texte : l'historique s'ouvre, un clic colle l'élément là où tu étais.
- Texte, images et captures d'écran ; 30 derniers éléments.
- **Les mots de passe copiés depuis un gestionnaire** (1Password, Bitwarden, Trousseau…) **ne sont jamais enregistrés.**

### Captures d'écran

- Après ⌘⇧4, une **notification cliquable** apparaît en bas à droite : un clic ouvre la capture dans **Aperçu** pour l'annoter, glisser la dépose ailleurs.
- La capture part **directement dans le presse-papier** : ⌘⇧4 puis ⌘V.
- Onglet **Captures** : la dernière en grand, les précédentes en bande.
- Un interrupteur coupe la vignette flottante de macOS, qui retarde la capture d'environ 5 secondes.

### Moniteur

- **Un verdict en une ligne** : « Tout va bien », « Redémarrage conseillé », « Fais de la place sur le disque »… et pour chaque constat, sa cause et l'action en un clic.
- **Mémoire détaillée** : apps, système, compressée, cache, libre, swap — avec ce que chaque part veut dire.
- **Chaleur** : température de la puce et ventilateurs (lus dans le SMC), charge sur 1/5/15 min, qui fait chauffer.
- **Applications** regroupées (les 30 processus de Chrome comptent comme une app), processus système expliqués (Spotlight qui indexe, iCloud qui synchronise…), quitter ou forcer l'arrêt.
- **Historique sur 14 jours** : les apps — et les pages web — qui ralentissent ton Mac **régulièrement**.
- **Rapport Markdown** exportable.

### Live — mode présentateur

Bouton **● Live** dans l'île, ou **⌃⌥L**. Le témoin ● apparaît sur la loutre de la barre des menus, et l'île devient une barre d'outils qui s'ouvre au survol.

| | |
|---|---|
| **Dessiner** | Stylo, flèche, rectangle, cercle, surligneur, laser. Les traits **s'estompent** après 3 à 20 s (ou restent). Une flèche ou un cercle tracés à main levée sont **redressés**. Maintenir **⌃** et glisser : trait rapide sans choisir d'outil. |
| **Pastilles numérotées** | Chaque clic pose ①, ②, ③… ; tape aussitôt une **étiquette** (↩ pour valider), ou reclique ailleurs pour la pastille seule. |
| **Curseur** | Anneau fin, **comète**, **étincelles** ou **pointillés** ; animation différente au clic gauche, au double-clic et au clic droit ; projecteur qui assombrit tout sauf autour du curseur. |
| **Touches affichées** | Les raccourcis tapés (⌘C, ⌘⇧4…) s'affichent en bas de l'écran — **jamais le texte tapé**. |
| **Masquage** | Les **clés API et mots de passe visibles** sont recouverts (OpenAI, Anthropic, Stripe, GitHub, AWS, Google, Slack, Airtable, Notion, jetons JWT, webhooks Make, en-têtes `Authorization: Bearer …`, `?key=` dans les URL…). Les apps sensibles (1Password, Trousseau, Messages…) sont cachées entières. |
| **Bureau caché** | Les icônes du bureau disparaissent derrière ton fond d'écran ; option pour masquer les autres apps. |
| **Concentration** | Coupe les notifications pendant le Live (via tes raccourcis Concentration). |
| **Personnaliser** | Palette et sélecteur de couleurs avec codes hexa, effets, tailles, apps à masquer, **raccourcis configurables**. |

> **Partage l'écran entier**, pas une seule fenêtre : sinon les participants ne voient ni les dessins ni les masques.
> Le Live ne capture **aucun** raccourci des apps (⌘Z, ⌘V, Échap continuent de marcher partout) et reste sous 2 % de processeur.

### Nettoyage du clavier

Un bouton de l'accueil **verrouille tout le clavier** le temps de le nettoyer : aucune touche ne déclenche quoi que ce soit. Un clic dans l'île le déverrouille — jamais une touche, puisqu'elles sont bloquées.

### Agenda, musique, étagère, miroir, Pomodoro

- **Agenda** : évènements des prochaines 24 h et rappels, à cocher depuis l'île.
- **Musique** : titre, pochette, progression et contrôles pour **Spotify** et **Apple Music**.
- **Étagère** : glisse des fichiers sur l'encoche pour les garder sous la main, envoi **AirDrop**.
- **Miroir** : la caméra, pour vérifier sa tête avant une visio.
- **Pomodoro** avec mode Concentration, pause de la musique et carillon.

### Inbox Claude Code

Quand [Claude Code](https://claude.com/claude-code) demande une validation, la demande apparaît dans l'île : tu approuves ou refuses sans quitter ce que tu fais. Simple échange de fichiers JSON dans `~/.otterisland/`, sans réseau. Mise en place : [docs/CLAUDE_CODE.md](docs/CLAUDE_CODE.md).

---

## Autorisations macOS

OtterIsland ne demande une autorisation **qu'au moment où une fonction en a besoin**. Toutes sont facultatives : sans elles, la fonction concernée est simplement indisponible.

| Autorisation | Pourquoi | Fonctions concernées | Où l'activer |
|---|---|---|---|
| **Accessibilité** | Simuler ⌘V, lire le texte affiché et les titres de fenêtres | Collage depuis le presse-papier, masquage des clés pendant le Live, touches affichées, titres de pages dans le Moniteur | Réglages Système › Confidentialité et sécurité › Accessibilité |
| **Surveillance des saisies** (avec l'Accessibilité) | Bloquer le clavier | Nettoyage du clavier | … › Surveillance des saisies |
| **Calendriers** et **Rappels** | Lire tes évènements et rappels | Agenda, prochain rendez-vous de l'accueil | … › Calendriers / Rappels |
| **Caméra** | Afficher l'image de la caméra | Miroir | … › Caméra |
| **Automatisation** (Spotify, Musique, System Events) | Lire le morceau en cours, piloter la lecture, demander un redémarrage | Musique, bouton « Redémarrer » du Moniteur | … › Automatisation |
| **Ouverture au démarrage** | Se lancer à l'ouverture de session | Réglages › Général | Réglages Système › Général › Ouverture |

**Aucune autre autorisation** : pas d'enregistrement de l'écran, pas de micro, pas de localisation, pas de contacts.

> Après une mise à jour, macOS peut décocher une autorisation si l'app n'est pas signée avec une identité stable : décoche puis recoche-la. Les builds officielles sont signées pour l'éviter ([docs/SIGNING.md](docs/SIGNING.md)).

---

## Confidentialité : clés, comptes, données personnelles

**OtterIsland n'a besoin d'aucun compte, d'aucune clé API, d'aucun identifiant.** Rien n'est à configurer, rien n'est envoyé à un serveur d'OtterIsland — il n'y en a pas.

**Ce qui sort du Mac — uniquement :**

- **Recherche de mise à jour** : une requête à l'API publique GitHub (`api.github.com/repos/RoYaL63/OtterIsland/releases/latest`), au lancement si l'option est cochée, et le téléchargement de la mise à jour quand tu l'installes.
- **Pochette d'album** : téléchargée depuis l'adresse fournie par Spotify, pour l'afficher.

**Ce qui reste sur le Mac**, dans `~/Library/Application Support/OtterIsland/` :

| Fichier | Contenu | Pour l'effacer |
|---|---|---|
| `clipboard.json` | Les 30 derniers éléments copiés (hors mots de passe des gestionnaires) | Presse-papier › Vider |
| `screenshots.json` | Chemins des 40 dernières captures | Captures › Vider |
| `shelf.json` | Chemins des fichiers posés sur l'étagère | Étagère |
| `usage-history.json` | Consommation des apps sur 14 jours, et titres des pages web lors des emballements du navigateur | Moniteur › Historique › Effacer (désactivable) |

Les réglages sont dans les préférences macOS (`com.otterwise.otterisland`). **Aucun mot de passe, aucune clé, aucun jeton n'est stocké.** Le masquage du Live lit le texte à l'écran pour le recouvrir, sans jamais l'enregistrer.

---

## Mettre à jour · désinstaller

**Mettre à jour** : Réglages › Mise à jour › **Installer et redémarrer**. L'app se remplace elle-même, sans zip ni nouveau passage par Gatekeeper.

**Désinstaller** : quitte OtterIsland (menu 🦦 › Quitter), mets l'app à la corbeille, puis supprime si tu veux ses données :

```bash
rm -rf ~/Library/Application\ Support/OtterIsland ~/.otterisland
defaults delete com.otterwise.otterisland
```

---

## Compiler, forker, contribuer

```bash
git clone https://github.com/RoYaL63/OtterIsland.git
cd OtterIsland
brew install xcodegen
xcodegen generate        # génère OtterIsland.xcodeproj depuis project.yml
open OtterIsland.xcodeproj
```

Dans Xcode : target **OtterIsland** › Signing & Capabilities › ton équipe (ou « Sign to Run Locally »), puis ⌘R. macOS 14+ et Xcode 16 requis.

**Pour publier ton propre fork** :

1. Remplace `owner` / `repo` dans `Sources/OtterIsland/Features/Update/Updater.swift` — sinon ton app proposera les mises à jour de ce dépôt.
2. Change l'identifiant `com.otterwise.otterisland` dans `project.yml` (`bundleIdPrefix` et `PRODUCT_BUNDLE_IDENTIFIER`).
3. Publie une version : onglet **Actions › Release › Run workflow** avec le numéro de version (celui de `MARKETING_VERSION` dans `project.yml`). La signature stable est facultative : [docs/SIGNING.md](docs/SIGNING.md).

**Pour aller plus loin** : architecture dans [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), pistes dans [docs/ROADMAP.md](docs/ROADMAP.md). Les PR sont bienvenues.

<sub>Licence [MIT](LICENSE) © 2026 Otterwise Solutions — fais-en ce que tu veux, en gardant la mention de licence. 🦦</sub>
