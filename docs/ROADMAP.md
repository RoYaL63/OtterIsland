# Roadmap OtterIsland

Chaque feature demandée, son état, et comment on l'aborde. Un module = un dossier sous `Sources/OtterIsland/Features/`.

## Milestone 1 — Squelette vivant (fait)

| Feature | État | Notes techniques |
|---|---|---|
| Fenêtre encoche | ✅ | `NSPanel` borderless non-activant, niveau statusBar, collé à l'encoche |
| Détection taille encoche | ✅ | `NSScreen.safeAreaInsets` + `auxiliaryTopLeftArea/RightArea` |
| Batterie + charge | ✅ | IOKit `IOPSCopyPowerSourcesInfo`, source de run loop |
| Loutre pixel animée | ✅ | SpriteKit, texture générée en code (grille de pixels), idle + clignement |
| Inbox Claude Code | ✅ | Surveillance de dossier, JSON in/out, approuver/refuser |
| Réglages | ✅ | Fenêtre SwiftUI `Settings`, persistance UserDefaults |

## Milestone 2 — Média et HUD

| Feature | Approche | Piège connu |
|---|---|---|
| 🎧 Playback live activity | Now Playing | ✅ titre/artiste/état, contrôles, **pochette d'album** (téléchargée) et **barre de progression** interpolée (AppleScript Spotify + Apple Music). Reste: pochette Apple Music (URL indispo en AppleScript), affichage état pause, secours `MediaRemote`. |
| 🎚️💡⌨️ HUD système (volume, luminosité, clavier) | Intercepter les touches média, masquer le HUD natif, redessiner dans l'encoche | Masquer le HUD Apple demande de tuer/relancer `OSDUIHelper` ou d'utiliser un overlay par-dessus. Gestion des touches via `CGEventTap` (demande accessibilité). |

## Milestone 3 — Productivité

| Feature | Approche | État |
|---|---|---|
| 📆 Calendrier | EventKit, `EKEventStore`, prochains évènements (24 h) dans l'onglet Agenda | ✅ `CalendarProvider` |
| ☑️ Rappels | EventKit rappels non terminés dans l'onglet Agenda | ✅ (affichage ; cocher = à venir) |
| 📚 Shelf + AirDrop | Onglet Étagère : dépôt drag & drop, re-glisser, `NSSharingService` .sendViaAirDrop | ✅ `ShelfModel` / `ShelfPanel` |

## Milestone 4 — Interaction et écran

| Feature | Approche | État |
|---|---|---|
| 👆🏻 Gestes | Molette globale au-dessus de l'encoche pour ouvrir/fermer | ✅ `GestureController` (swipe/tap avancés à venir) |
| 🖥️ Tailles d'encoche fines | Réglages largeur + débordement (par écran = à venir) | ⏳ partiel |
| 📷 Miroir | `AVCaptureSession` + preview layer dans l'onglet Miroir | ✅ `MirrorPanel` |
| 🔋 Charge détaillée | Temps restant, cycles, santé (IOKit `AppleSmartBattery`) | ⏳ à venir |
| 🎚️ HUD volume | CoreAudio, HUD sous l'encoche | ✅ `VolumeMonitor` (n'écrase pas encore le HUD natif) |
| 🚀 Lancement au démarrage | `SMAppService` | ✅ `LaunchAtLogin` |
| 🍅 Pomodoro + actions vibe | Minuteur focus, lancer Claude Code | ✅ `PomodoroTimer` / `QuickActions` |
| 📋 Presse-papier | Historique texte/image, raccourci global (Cmd+Shift+V par défaut), collage auto, **persistance disque** | ✅ `ClipboardManager` / `HotKey` / `Paster` / `Persistence` |
| 💾 Persistance | Presse-papier + étagère sauvegardés dans Application Support/OtterIsland | ✅ `Persistence` |

## Milestone 5 — Loutre et vibe coding

| Feature | Approche |
|---|---|
| Humeurs de la loutre | ✅ fait: idle/happy/curious/playful/swimming/worried/sleepy, expressions, respiration, queue animée, pose de nage dédiée. Effets: Zzz endormie, étincelles curieuse, bulles en nage, gouttes de stress. |
| Réactions Claude Code | ✅ fait: elle lance un coquillage 🐚 quand tu approuves une action. |
| Batterie faible | ✅ fait: sous 15% et débranchée, elle se planque et tremble (mood `worried`). |
| Nage sur la musique | ✅ fait: `AppleScriptNowPlaying` détecte Spotify/Music, la loutre passe en pose de nage. |
| Actions rapides vibe coder | Raccourcis: lancer Claude Code, coller le presse-papier vers un prompt, timer pomodoro, snippet launcher |
| Réactions Claude Code | La loutre apporte physiquement la carte de demande, animation dédiée |

## Milestone 6 — Finition

| Feature | État | Notes |
|---|---|---|
| Système visuel | ✅ | `Sources/OtterIsland/UI/OtterTheme.swift` : 3 niveaux de texte, échelle typo, accent aqua prélevé sur l'icône. L'orange redevient une couleur d'ALERTE, plus un accent. |
| Icône d'app | ✅ | Générée depuis `icone.png` par `scripts/make_appicon.swift` (squircle, grille Apple). |
| Aperçu de design sans Xcode | ✅ | `scripts/render_card.swift` rend la carte en PNG, providers non démarrés. |
| Captures | ✅ | Copie auto dans le presse-papier (⌘⇧4 → ⌘V), dernière capture en grand + bande des précédentes, cache de vignettes `CGImageSource`. |
| Mise à jour intégrée | ✅ | `Features/Update/Updater.swift` + onglet Réglages. Sans quarantaine. |
| Signature stable | ⏳ | Workflow prêt (secrets `MACOS_CERT_*`), reste à créer le certificat — `docs/SIGNING.md`. Condition pour que les permissions survivent aux mises à jour. |

## Modules stubés dès maintenant

Pour garder Milestone 1 compilable, les modules 2 à 4 exposent une interface (protocole) et un provider vide marqué `TODO`. On les remplit sans toucher au reste.
