import SwiftUI

/// État transitoire d'un HUD système (volume, luminosité…).
struct HUDState: Equatable {
    enum Kind: Equatable {
        case volume

        var icon: String {
            switch self {
            case .volume: return "speaker.wave.2.fill"
            }
        }
    }

    let kind: Kind
    let value: Double // 0...1
}

/// HUD compact affiché sous l'encoche lors d'un changement système.
struct HUDView: View {
    let state: HUDState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.kind.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 18)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(.white)
                        .frame(width: max(4, geo.size.width * state.value))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 14)
        .frame(width: 200, height: 34)
        .liquidGlassBackground(in: Capsule())
    }
}
