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

    /// Côté de la scène de la loutre. 30 : version compacte, logée dans la
    /// rangée des onglets. À 56, elle prenait une colonne entière à la carte
    /// pour un rôle d'indicateur d'ambiance. Les animations se règlent sur
    /// cette taille (`OtterScene.u`).
    static let side: CGFloat = 30

    init() {
        let scene = OtterScene(size: CGSize(width: OtterSceneHolder.side, height: OtterSceneHolder.side))
        scene.scaleMode = .resizeFill
        self.scene = scene
    }
}
