import SwiftUI

/// Petit indicateur batterie : icône + pourcentage, couleur selon niveau/charge.
struct BatteryBadge: View {
    @ObservedObject var monitor: BatteryMonitor

    private var symbol: String {
        if monitor.isCharging { return "battery.100.bolt" }
        switch monitor.percentage {
        case ...10: return "battery.0"
        case ...35: return "battery.25"
        case ...60: return "battery.50"
        case ...85: return "battery.75"
        default: return "battery.100"
        }
    }

    private var tint: Color {
        if monitor.isCharging { return .green }
        return monitor.percentage <= 15 ? .red : .white
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text("\(monitor.percentage)%")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
            if monitor.isPluggedIn && !monitor.isCharging {
                Text("branché")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

/// Version compacte pour flanquer l'encoche physique repliée (hauteur menu
/// bar) : juste l'icône et le pourcentage, sans le texte "branché".
struct CompactBatteryBadge: View {
    @ObservedObject var monitor: BatteryMonitor

    private var symbol: String {
        if monitor.isCharging { return "battery.100.bolt" }
        switch monitor.percentage {
        case ...10: return "battery.0"
        case ...35: return "battery.25"
        case ...60: return "battery.50"
        case ...85: return "battery.75"
        default: return "battery.100"
        }
    }

    private var tint: Color {
        if monitor.isCharging { return .green }
        return monitor.percentage <= 15 ? .red : .white
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            Text("\(monitor.percentage)%")
                .font(.system(size: 10, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .liquidGlassBackground(in: Capsule(), tint: .black.opacity(0.6))
    }
}
