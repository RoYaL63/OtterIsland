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
- [ ] Suppression du HUD natif, tailles par écran, contrôles média avancés (voir `docs/ROADMAP.md`)

La suite des features est détaillée dans [docs/ROADMAP.md](docs/ROADMAP.md).

## Télécharger

Chaque tag `vX.Y.Z` poussé sur GitHub déclenche une build automatique (GitHub Actions) qui publie un `OtterIsland.zip` dans l'onglet [Releases](../../releases).

L'app n'est **pas signée** (pas de compte Apple Developer payant) : au premier lancement, macOS va bloquer l'ouverture ("Apple n'a pas pu vérifier..."). Pour l'autoriser :

1. Dézippe et glisse `OtterIsland.app` dans `/Applications`.
2. Double-clique dessus. macOS refuse de l'ouvrir.
3. Va dans **Réglages Système → Confidentialité et sécurité**, descends jusqu'à la mention d'OtterIsland bloquée, clique **Ouvrir quand même**.

Ou en une commande, avant le premier lancement :

```bash
xattr -cr /Applications/OtterIsland.app
```

Cette étape n'est nécessaire qu'une fois par machine et par version.

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

Dans Xcode: sélectionne la target `OtterIsland`, choisis ton équipe de signature (Signing & Capabilities), puis ⌘R.

L'app est un agent (pas d'icône dans le Dock). La loutre apparaît sous l'encoche au survol.

## Architecture

Voir [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). En bref: `AppDelegate` monte un `NotchWindowController` qui héberge une vue SwiftUI dans un panneau transparent collé à l'encoche. Chaque fonction (batterie, loutre, Claude Code) est un module indépendant exposé au `NotchViewModel`.

## Inbox Claude Code

OtterIsland surveille `~/.otterisland/inbox/`. Un hook Claude Code y dépose un JSON de demande d'action, la loutre te l'apporte dans l'encoche, ta réponse repart dans `~/.otterisland/outbox/`. Voir [docs/CLAUDE_CODE.md](docs/CLAUDE_CODE.md).

## Contribuer

PRs bienvenues. Le style et la structure sont dans `docs/ARCHITECTURE.md`. Projet sous MIT, donc utilisable et forkable librement.
