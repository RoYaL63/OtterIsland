# Architecture

## Vue d'ensemble

```
OtterIslandApp (@main, SwiftUI App)
  └── AppDelegate (NSApplicationDelegate, agent app)
        ├── OtterSettings         (état persistant, ObservableObject)
        ├── NotchWindowController (crée et positionne le NSPanel)
        │     └── NotchWindow (NSPanel transparent, niveau statusBar)
        │           └── NSHostingView
        │                 └── NotchRootView (SwiftUI)
        │                       ├── forme de l'encoche (collapsed / expanded)
        │                       ├── OtterSceneView (SpriteView SpriteKit)
        │                       ├── BatteryBadge
        │                       └── ClaudeCodeCard
        └── Providers (injectés dans NotchViewModel)
              ├── BatteryMonitor      (IOKit)
              ├── NowPlayingProvider  (stub -> Milestone 2)
              └── ClaudeCodeInbox     (surveillance de dossier)
```

## Principes

1. **Un module par feature.** Chaque dossier sous `Features/` est autonome: un provider `ObservableObject` + sa vue. Le `NotchViewModel` agrège, il ne contient pas de logique métier.
2. **La fenêtre est bête.** `NotchWindow` ne fait que se placer et rester transparente. Toute l'UI est SwiftUI, testable en preview.
3. **Zéro dépendance externe au Milestone 1.** Pas de SPM tiers tant qu'on n'en a pas besoin. La loutre est générée en code pour éviter les assets binaires dans le dépôt au départ.
4. **Détection d'encoche robuste.** On lit `safeAreaInsets` et les zones auxiliaires. Fallback propre sur les Mac sans encoche (pilule flottante en haut au centre).

## Cycle de vie de la fenêtre

- `applicationDidFinishLaunching` passe l'app en `.accessory` (pas de Dock).
- `NotchWindowController.showOnActiveScreen()` calcule `NotchMetrics` pour l'écran actif et pose le panneau.
- On observe `NSApplication.didChangeScreenParametersNotification` pour repositionner (changement de résolution, écran externe branché).

## État collapsed / expanded

`NotchViewModel.isExpanded` bascule au survol (`onHover`). La forme de l'encoche s'anime avec un `withAnimation(.spring)`. Collapsed = largeur de l'encoche réelle. Expanded = carte plus large et plus haute qui déborde sous l'encoche.

## Concurrence

Providers annotés pour tourner sur le main actor côté UI. Les sources IOKit / FSEvents postent sur des callbacks C: on repasse sur `DispatchQueue.main` avant de toucher un `@Published`.

## Conventions de code

- Swift API design guidelines. Noms explicites, pas d'abréviations.
- Une vue SwiftUI par fichier quand elle dépasse ~40 lignes.
- Les providers exposent des `@Published` simples, pas de Combine complexe tant que ce n'est pas nécessaire.
- Commentaires en français, courts, sur le pourquoi pas le quoi.
