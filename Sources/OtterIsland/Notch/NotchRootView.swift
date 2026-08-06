import SwiftUI

/// Vue racine hébergée dans le panneau. Ancrée en haut au centre, elle dessine
/// l'encoche noire et bascule collapsed / expanded au survol.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @EnvironmentObject var settings: OtterSettings
    @State private var isFileDragTargeted = false

    private var notchWidth: CGFloat { viewModel.metrics?.notchSize.width ?? 200 }
    private var notchHeight: CGFloat { viewModel.metrics?.notchSize.height ?? 32 }

    private var currentWidth: CGFloat { viewModel.isExpanded ? viewModel.expandedSize.width : notchWidth }
    private var currentHeight: CGFloat { viewModel.isExpanded ? viewModel.expandedSize.height : notchHeight }

    var body: some View {
        VStack(spacing: 8) {
            island
            if let hud = viewModel.hud, !viewModel.isExpanded {
                HUDView(state: hud)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let shot = viewModel.screenshotPreview, !viewModel.isExpanded {
                ScreenshotPreviewView(
                    shot: shot,
                    didCopy: settings.screenshotAutoCopy,
                    onOpen: { viewModel.openScreenshotPreview() },
                    onDismiss: { viewModel.dismissScreenshotPreview() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: viewModel.hud)
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
        .onHover { hovering in
            viewModel.setExpanded(hovering)
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
    private var collapsedContent: some View {
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

    private var expandedContent: some View {
        HStack(spacing: 12) {
            if settings.otterEnabled {
                OtterSceneView(mood: viewModel.otterMood, event: viewModel.otterEvent)
                    .frame(width: 72, height: 72)
            }

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
                } else {
                    HStack {
                        Spacer(minLength: 0)
                        NotchTabBar(selection: $viewModel.selectedTab)
                    }
                    panel
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, notchHeight + 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var panel: some View {
        switch viewModel.selectedTab {
        case .otter:
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
            MusicPanel(provider: viewModel.nowPlaying)
        case .agenda:
            AgendaPanel(calendar: viewModel.calendar)
        case .shelf:
            ShelfPanel(shelf: viewModel.shelf)
        case .clipboard:
            ClipboardPanel(clipboard: viewModel.clipboard) { item in
                viewModel.pasteFromClipboard(item)
            }
        case .mirror:
            MirrorPanel()
        case .screenshots:
            ScreenshotsPanel(screenshot: viewModel.screenshot) { url in
                viewModel.copyScreenshot(url)
            }
        }
    }
}
