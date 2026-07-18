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

    init() {
        let scene = OtterScene(size: CGSize(width: 72, height: 72))
        scene.scaleMode = .resizeFill
        self.scene = scene
    }
}
