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
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}
