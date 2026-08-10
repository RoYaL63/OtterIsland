import SwiftUI
import SpriteKit

/// Enveloppe SwiftUI de la scène SpriteKit. Garde une scène persistante et lui
/// pousse l'humeur courante.
struct OtterSceneView: View {
    let mood: OtterMood
    var event: OtterEventToken?
    @StateObject private var holder = OtterSceneHolder()

    var body: some View {
        SpriteView(scene: holder.scene, options: [.allowsTransparency])
            .background(Color.clear)
            .onAppear { holder.scene.update(mood: mood) }
            .onChange(of: mood) { _, newMood in
                holder.scene.update(mood: newMood)
            }
            .onChange(of: event) { _, newEvent in
                if let newEvent { holder.scene.play(newEvent.event) }
            }
    }
}

@MainActor
final class OtterSceneHolder: ObservableObject {
    let scene: OtterScene

    /// Côté de la scène de la loutre. 56 et non 72 : elle mangeait un sixième
    /// de la largeur de la carte pour un rôle d'indicateur d'ambiance. Le
    /// contenu (indicateurs, calendrier, lecteur) reprend la place.
    static let side: CGFloat = 56

    init() {
        let scene = OtterScene(size: CGSize(width: OtterSceneHolder.side, height: OtterSceneHolder.side))
        scene.scaleMode = .resizeFill
        self.scene = scene
    }
}
