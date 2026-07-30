# 🦦 OtterIsland

Une encoche vivante pour ton MacBook. Dans l'esprit de la Dynamic Island, avec plus de fonctions et une petite loutre de compagnie animée qui vit dans ton notch.

> macOS 14+ · Swift · SwiftUI · AppKit · SpriteKit · Licence MIT

## Pourquoi

Les apps d'encoche existantes (TheBoringNotch, NotchNook) gèrent bien la musique et la batterie. OtterIsland ajoute deux choses que personne ne fait:

- **Une loutre de compagnie** en pixel-art qui réagit à ce qui se passe (charge, musique, focus).
- **Une inbox Claude Code**: quand Claude Code a besoin d'une validation (permission, action risquée), la demande apparaît dans l'encoche et tu approuves d'un geste, sans quitter ton flow.

## État du projet

Milestone 1 (ce dépôt) est un squelette qui **compile et tourne** sur un Mac à encoche:

- [x] Fenêtre `NSPanel` positionnée sur l'encoche, détection auto de la taille
- [x] Vue étendue à onglets (Loutre, Musique, Agenda, Étagère, Miroir)
- [x] Batterie: pourcentage, état de charge, temps restant (IOKit)
- [x] Loutre pixel-art animée: 7 humeurs, pose de nage, queue, effets (SpriteKit, zéro asset)
- [x] Inbox Claude Code (surveillance de fichiers, approuver/refuser, coquillage à l'approbation)
- [x] Musique: Now Playing + contrôles (Spotify / Apple Music via AppleScript)
- [x] Agenda: évènements + rappels (EventKit), cocher depuis l'encoche
- [x] Étagère avec dépôt de fichiers et AirDrop
- [x] Miroir caméra
- [x] HUD volume (CoreAudio), contrôle à la molette, lancement au démarrage, Pomodoro
- [x] Fenêtre de réglages
- [x] Système visuel unifié (jetons de couleur/typo, accent aqua repris de l'icône)
- [x] Mise à jour depuis l'app (Réglages › Mise à jour), sans zip ni quarantaine
- [x] Captures : copie automatique dans le presse-papier, dernière capture en grand
- [x] Installeur `.dmg` et proposition d'installation dans /Applications au premier lancement
- [ ] Suppression du HUD natif, tailles par écran, contrôles média avancés (voir `docs/ROADMAP.md`)

La suite des features est détaillée dans [docs/ROADMAP.md](docs/ROADMAP.md).

## Installer

Télécharge **`OtterIsland.dmg`** dans l'onglet [Releases](../../releases), ouvre-le,
glisse la loutre sur le dossier Applications. La fenêtre te montre quoi faire.

Si tu lances l'app depuis ailleurs (Téléchargements, l'image disque elle-même),
**elle te propose de s'installer toute seule** au premier lancement et redémarre
dans la foulée. Ce n'est pas cosmétique : hors de `/Applications`, macOS ne donne
pas d'identité stable à l'app, donc l'Accessibilité, la Surveillance des saisies
et le lancement au démarrage ne peuvent pas fonctionner.

> Chaque tag `vX.Y.Z` déclenche une build automatique qui publie le `.dmg` et un
> `.zip`. Le zip sert uniquement à la mise à jour intégrée — inutile de le
> télécharger à la main.

### Le passage obligé de Gatekeeper

L'app n'est **pas notarisée** (pas de compte Apple Developer payant) : au premier
lancement, macOS bloque l'ouverture ("Apple n'a pas pu vérifier..."). Pour
l'autoriser, une fois l'app dans `/Applications`, dans le Terminal :

```bash
sudo spctl --add /Applications/OtterIsland.app
```

(demande ton mot de passe admin). Sur macOS 15/26+, Gatekeeper rejette purement et simplement les apps ad-hoc au téléchargement — `xattr -cr` seul (qui suffisait sur les anciennes versions) ne change rien à ce verdict, vérifié avec `spctl -a -vv`.

**À faire une seule fois.** Les versions suivantes s'installent depuis l'app (voir « Mettre à jour » ci-dessus) : le téléchargement ne passe pas par le navigateur, donc pas de quarantaine, donc pas de nouveau `spctl --add`.

## Mettre à jour

**Réglages › Mise à jour › Installer et redémarrer** :
OtterIsland récupère la dernière release, remplace l'app à son emplacement et
relance. Pas de zip à dézipper, et surtout pas de quarantaine Gatekeeper — donc
plus de `spctl --add` à chaque version.

Les permissions (Accessibilité, Surveillance des saisies) ne survivent en
revanche à une mise à jour que si les builds sont signées avec une identité
stable. L'onglet Mise à jour affiche l'état réel ; la marche à suivre est dans
[docs/SIGNING.md](docs/SIGNING.md).

## Build

Tu es sur Windows, la compilation se fait sur le MacBook Air M5. Sur le Mac:

```bash
# 1. Récupérer le dépôt
git clone https://github.com/<toi>/OtterIsland.git
cd OtterIsland

# 2. Générer le projet Xcode depuis project.yml
brew install xcodegen
xcodegen generate

# 3. Ouvrir et lancer
open OtterIsland.xcodeproj
```

### Icône

`Resources/Assets.xcassets/AppIcon.appiconset` est **généré**, pas édité à la
main. Pour repartir d'une nouvelle illustration, remplace `icone.png` (carré,
fond uni) puis :

```bash
swift scripts/make_appicon.swift
```

Le script rogne le fond, découpe la tuile en squircle (coins transparents),
la recentre sur la grille Apple et écrit les 7 tailles + le `Contents.json`.

Dans Xcode: sélectionne la target `OtterIsland`, choisis ton équipe de signature (Signing & Capabilities), puis ⌘R.

L'app est un agent (pas d'icône dans le Dock). La loutre apparaît sous l'encoche au survol.

## Architecture

Voir [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). En bref: `AppDelegate` monte un `NotchWindowController` qui héberge une vue SwiftUI dans un panneau transparent collé à l'encoche. Chaque fonction (batterie, loutre, Claude Code) est un module indépendant exposé au `NotchViewModel`.

## Inbox Claude Code

OtterIsland surveille `~/.otterisland/inbox/`. Un hook Claude Code y dépose un JSON de demande d'action, la loutre te l'apporte dans l'encoche, ta réponse repart dans `~/.otterisland/outbox/`. Voir [docs/CLAUDE_CODE.md](docs/CLAUDE_CODE.md).

## Contribuer

PRs bienvenues. Le style et la structure sont dans `docs/ARCHITECTURE.md`. Projet sous MIT, donc utilisable et forkable librement.
