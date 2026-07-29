import SwiftUI
import Carbon.HIToolbox

/// Petit composant qui capture une combinaison de touches au clic, pour définir
/// un raccourci global personnalisable (ex. Option+V). Stocke le keyCode et les
/// modificateurs au format Carbon, directement consommables par `HotKey`.
struct ShortcutRecorderView: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Appuie sur une combinaison…" : display)
                .font(.system(.caption, design: .monospaced))
                .frame(minWidth: 130)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .orange : .accentColor)
        .onDisappear { stopRecording() }
    }

    private var display: String {
        Self.symbols(for: UInt32(modifiers)) + (Self.keyName(for: Int32(keyCode)) ?? "?")
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
            // Sans modificateur, trop de risques de percuter la saisie normale : on ignore.
            guard carbonModifiers != 0 else { return nil }
            keyCode = Int(event.keyCode)
            modifiers = Int(carbonModifiers)
            stopRecording()
            return nil // avale l'évènement, ne le laisse pas remonter au reste de l'app
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private static func symbols(for modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    /// Table volontairement limitée aux lettres et chiffres : suffisant pour ce
    /// raccourci (ouverture du presse-papier).
    private static func keyName(for keyCode: Int32) -> String? {
        let map: [Int32: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
            34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
            12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        ]
        return map[keyCode]
    }
}
