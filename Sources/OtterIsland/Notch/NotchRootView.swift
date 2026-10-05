import SwiftUI

/// Vue racine hébergée dans le panneau. Ancrée en haut au centre, elle dessine
/// l'encoche noire et bascule collapsed / expanded au survol.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @EnvironmentObject var settings: OtterSettings
    @State private var isFileDragTargeted = false
    /// Palette personnalisée (Réglages › Apparence). Les vues lisent
    /// `Otter.accent` sans l'observer : l'île se reconstruit à chaque
    /// changement de palette pour que tout reprenne la nouvelle couleur.
    @ObservedObject private var appearance = OtterAppearance.shared

    private var notchWidth: CGFloat { viewModel.metrics?.notchSize.width ?? 200 }
    private var notchHeight: CGFloat { viewModel.metrics?.notchSize.height ?? 32 }

    private var currentWidth: CGFloat { viewModel.isExpanded ? viewModel.expandedSize.width : viewModel.collapsedSize.width }
    private var currentHeight: CGFloat { viewModel.isExpanded ? viewModel.expandedSize.height : viewModel.collapsedSize.height }

    var body: some View {
        VStack(spacing: 8) {
            island
            if let hud = viewModel.hud, !viewModel.isExpanded {
                HUDView(state: hud)
                    // Le verre se MATÉRIALISE au lieu d'apparaître : échelle et
                    // glissement partent ensemble, ancrés au bord haut. Un
                    // fondu seul lit comme une image qui s'allume, pas comme
                    // une surface qui arrive.
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.94, anchor: .top))
                    )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: viewModel.hud)
        .id(appearance.revision)
        // Onglet affiché masqué depuis les réglages : on retombe sur le premier visible.
        .onChange(of: settings.hiddenTabs) { _, _ in
            if !settings.visibleTabs.contains(viewModel.selectedTab), let first = settings.visibleTabs.first {
                viewModel.selectedTab = first
            }
        }
    }

    private var island: some View {
        ZStack(alignment: .top) {
            NotchGlassBackground(
                topWidth: viewModel.metrics?.hasRealNotch == true ? notchWidth : nil,
                topHeight: notchHeight,
                bottomRadius: viewModel.isExpanded ? 28 : 10,
                isExpanded: viewModel.isExpanded
            )
            // L'ombre décolle la carte du bureau : sans elle, un verre clair se
            // confond avec le fond d'écran au lieu de flotter au-dessus.
            .shadow(color: .black.opacity(viewModel.isExpanded ? 0.45 : 0), radius: 18, y: 9)

            if viewModel.isExpanded {
                // Le contenu émerge du verre : fondu + très légère dilatation
                // depuis le haut, dans le tempo du ressort de l'île.
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                collapsedContent
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        .contentShape(Rectangle())
        // Ce onHover ne sert plus qu'à REFERMER. L'ouverture est décidée par
        // `NotchWindowController`, qui exige un pointeur immobile : la laisser
        // aussi ici court-circuitait cette garde dès que la fenêtre acceptait
        // les clics, et l'île s'ouvrait au moindre passage.
        .onHover { hovering in
            guard !hovering else { return }
            viewModel.setExpanded(false)
        }
        // Un fichier glissé au-dessus de l'encoche l'ouvre sur l'Étagère, sinon
        // impossible d'y déposer quoi que ce soit tant qu'elle reste repliée.
        .onDrop(of: [.fileURL], isTargeted: $isFileDragTargeted) { providers in
            viewModel.shelf.handleDrop(providers)
        }
        .onChange(of: isFileDragTargeted) { _, targeted in
            guard targeted else { return }
            viewModel.selectedTab = .shelf
            viewModel.setExpanded(true)
        }
    }

    // Encoche au repos : noire, avec un signal discret si Claude Code attend.
    // Sur un écran sans encoche, c'est un onglet 🦦 qu'on survole ou clique.
    @ViewBuilder
    private var collapsedContent: some View {
        if viewModel.metrics?.hasRealNotch == false {
            Text("🦦")
                .font(.system(size: max(11, notchHeight * 0.55)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    if viewModel.inbox.pending != nil {
                        Circle().fill(Color.orange).frame(width: 6, height: 6).padding(3)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { viewModel.setExpanded(true) }
        } else {
            VStack {
                Spacer()
                if viewModel.inbox.pending != nil {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .padding(.bottom, 2)
                        .transition(.scale)
                }
            }
        }
    }

    private var expandedContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                if viewModel.keyboardLocker.isLocked || viewModel.keyboardLocker.permissionDenied {
                    // Le nettoyage passe devant tout : le clavier est bloqué, la
                    // seule sortie doit être visible immédiatement.
                    CleaningCard(permissionDenied: viewModel.keyboardLocker.permissionDenied) {
                        viewModel.unlockCleanup()
                    }
                } else if let request = viewModel.inbox.pending {
                    // Une demande Claude Code passe devant tout le reste.
                    ClaudeCodeCard(request: request) { approved in
                        viewModel.inbox.resolve(request, approved: approved)
                    }
                } else if viewModel.live.isActive, viewModel.liveDetour != nil {
                    HStack {
                        OtterActionLink(title: "Barre Live", icon: "chevron.left", tint: Otter.textSecondary) {
                            viewModel.liveDetour = nil
                        }
                        Spacer(minLength: 0)
                    }
                    panel
                } else if viewModel.live.isActive {
                    LiveToolbar(live: viewModel.live, style: viewModel.live.style)
                } else {
                    HStack(spacing: 8) {
                        // Version compacte : la loutre loge dans la rangée des
                        // onglets, où il reste ~95 pt libres, au lieu de
                        // prendre une colonne de 68 pt à toute la carte.
                        if settings.otterEnabled {
                            OtterSceneView(mood: viewModel.otterMood, event: viewModel.otterEvent)
                                .frame(width: OtterSceneHolder.side, height: OtterSceneHolder.side)
                                .padding(.vertical, -3) // déborde un peu sur l'écart, sans grandir la rangée
                        }
                        liveButton
                        Spacer(minLength: 0)
                        NotchTabBar(selection: $viewModel.selectedTab)
                    }
                    panel
                }
            }
            // Pas de Spacer ici : la colonne de contenu et un Spacer sont tous
            // deux flexibles, le HStack leur partageait donc la largeur et le
            // Spacer en volait une dizaine de points. Résultat, « Batterie » se
            // tronquait alors que la rangée tient largement (143 pt mesurés).
            // Les panneaux sont déjà en maxWidth: .infinity : ils occupent la
            // place, ce qui est exactement ce qu'on veut.
        }
        .padding(.horizontal, 16)
        .padding(.top, notchHeight + 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Lance le mode présentateur. À gauche de la barre d'onglets, à part :
    /// c'est une action, pas un onglet.
    private var liveButton: some View {
        Button {
            viewModel.live.start()
        } label: {
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("Live").font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(Otter.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Otter.ink(0.08)))
        }
        .buttonStyle(OtterPressStyle(scale: 0.93))
        .help("Mode présentateur : dessin, effets de curseur, touches, masquage (⌃⌥L)")
    }

    @ViewBuilder
    private var panel: some View {
        switch viewModel.selectedTab {
        case .home:
            OtterStatusPanel(
                battery: viewModel.battery,
                pomodoro: viewModel.pomodoro,
                calendar: viewModel.calendar,
                nowPlaying: viewModel.nowPlaying,
                memory: viewModel.memory,
                showBattery: settings.showBattery,
                onToggleCleanup: { viewModel.toggleCleanup() },
                onOpenMirror: { viewModel.selectedTab = .mirror },
                onOpenAgenda: { viewModel.selectedTab = .agenda }
            )
        case .music:
            MusicPanel(provider: viewModel.nowPlaying, volume: viewModel.volume)
        case .agenda:
            AgendaPanel(calendar: viewModel.calendar)
        case .shelf:
            ShelfPanel(shelf: viewModel.shelf)
        case .clipboard:
            ClipboardPanel(clipboard: viewModel.clipboard) { item in
                viewModel.pasteFromClipboard(item)
            }
        case .monitor:
            MonitorPanel(
                monitor: viewModel.systemMonitor,
                memory: viewModel.memory,
                battery: viewModel.battery,
                history: viewModel.usageHistory,
                showBattery: settings.showBattery,
                onOpenWindow: { viewModel.openMonitorWindow() }
            )
        case .mirror:
            MirrorPanel { withEffects in viewModel.openMirrorWindow(withEffects: withEffects) }
        case .screenshots:
            ScreenshotsPanel(screenshot: viewModel.screenshot) { url in
                viewModel.copyScreenshot(url)
            }
        }
    }
}
