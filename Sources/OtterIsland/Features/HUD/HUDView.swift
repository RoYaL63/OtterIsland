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

    /// Même grammaire que les curseurs Son / Luminosité du Centre de contrôle :
    /// une tuile de verre, une glyphe, une piste épaisse. La piste de 5 pt
    /// d'avant se lisait comme un filet décoratif ; à 8 pt, c'est un curseur.
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: state.kind.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Otter.textSecondary)
                .frame(width: 18)
            OtterMeter(value: state.value, height: 8)
        }
        .padding(.horizontal, 15)
        .frame(width: 214, height: 42)
        .liquidGlassCard(
            in: RoundedRectangle(cornerRadius: Otter.Radius.large, style: .continuous)
        )
    }
}
