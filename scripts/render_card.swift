// Rendu PNG de la carte étendue, sans lancer l'app.
//
//   swiftc -swift-version 5 -target arm64-apple-macos14.0 \
//     -sdk $(xcrun --show-sdk-path) -parse-as-library \
//     $(find Sources -name '*.swift' ! -name 'OtterIslandApp.swift') \
//     scripts/render_card.swift -o /tmp/render_card && /tmp/render_card <dossier>
//
// Sert à juger le design (espacements, contrastes, hiérarchie) sans build Xcode
// ni Mac à encoche. Les providers sont instanciés SANS `start()` : aucune
// permission demandée, aucun sondage lancé, aucune donnée personnelle lue.
//
// La composition ci-dessous reflète `NotchRootView.expandedContent` : si la
// vraie carte change de structure, la mettre à jour ici aussi.

import SwiftUI
import AppKit

@MainActor
private func card<Panel: View>(tab: NotchTab, @ViewBuilder panel: () -> Panel) -> some View {
    let notchWidth: CGFloat = 200
    let notchHeight: CGFloat = 32
    let size = CGSize(width: 460, height: 284)

    return ZStack(alignment: .top) {
        NotchGlassBackground(
            topWidth: notchWidth,
            topHeight: notchHeight,
            bottomRadius: 28,
            isExpanded: true
        )
        HStack(spacing: 12) {
            // La loutre est du SpriteKit : hors de l'app, on réserve sa place.
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 72, height: 72)
                .overlay(Text("🦦").font(.system(size: 34)))

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Spacer(minLength: 0)
                    NotchTabBar(selection: .constant(tab))
                }
                panel()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, notchHeight + 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(width: size.width, height: size.height)
    // Fond de scène : le verre est translucide, il lui faut quelque chose derrière.
    .padding(20)
    .background(
        LinearGradient(
            colors: [Color(red: 0.10, green: 0.12, blue: 0.16), Color(red: 0.16, green: 0.18, blue: 0.22)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    )
}

@MainActor
private func snapshot(_ view: some View, to path: String) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let window = NSWindow(
        contentRect: host.frame, styleMask: [.borderless],
        backing: .buffered, defer: false
    )
    window.contentView = host
    window.orderFront(nil)
    // Laisse SwiftUI résoudre layout, images asynchrones et animations d'entrée.
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    window.orderOut(nil)
    print("→ \(path)")
}

/// Petites images de test pour l'onglet Captures : pas question d'aller lire
/// les vraies captures de l'utilisateur pour faire une planche de design.
@MainActor
private func makeSampleShots(in dir: String) -> [URL] {
    let palette: [(NSColor, String)] = [
        (NSColor(red: 0.15, green: 0.55, blue: 0.85, alpha: 1), "Capture 14.02.11"),
        (NSColor(red: 0.85, green: 0.45, blue: 0.30, alpha: 1), "Capture 11.47.02"),
        (NSColor(red: 0.30, green: 0.70, blue: 0.55, alpha: 1), "Capture 09.15.38"),
        (NSColor(red: 0.55, green: 0.40, blue: 0.80, alpha: 1), "Capture 08.03.20"),
        (NSColor(red: 0.80, green: 0.70, blue: 0.25, alpha: 1), "Capture 22.51.07"),
    ]
    return palette.compactMap { color, name in
        let size = NSSize(width: 320, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSRect(x: 30, y: 40, width: 260, height: 22).fill()
        NSRect(x: 30, y: 80, width: 180, height: 22).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        let url = URL(fileURLWithPath: "\(dir)/\(name).png")
        try? png.write(to: url)
        return url
    }
}

@main
enum RenderCard {
    @MainActor static func main() {
        let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory()

        let battery = BatteryMonitor()
        let pomodoro = PomodoroTimer()
        let calendar = CalendarProvider()
        let nowPlaying = AppleScriptNowPlaying()
        let memory = MemoryMonitor()
        memory.start() // relevé mémoire : aucune permission

        snapshot(
            card(tab: .otter) {
                OtterStatusPanel(
                    battery: battery, pomodoro: pomodoro, calendar: calendar,
                    nowPlaying: nowPlaying, memory: memory, showBattery: true,
                    onToggleCleanup: {}, onOpenMirror: {}, onOpenAgenda: {}
                )
            },
            to: "\(dir)/card-accueil.png"
        )

        let shots = makeSampleShots(in: dir)
        snapshot(
            card(tab: .screenshots) {
                ScreenshotsPanel(screenshot: ScreenshotWatcher(previewHistory: shots)) { _ in }
            },
            to: "\(dir)/card-captures.png"
        )

        snapshot(
            card(tab: .agenda) { AgendaPanel(calendar: calendar) },
            to: "\(dir)/card-agenda.png"
        )

        exit(0)
    }
}
