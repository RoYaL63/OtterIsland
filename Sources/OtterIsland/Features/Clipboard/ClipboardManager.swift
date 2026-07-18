import AppKit
import Combine

/// Historique du presse-papier. Sonde NSPasteboard et garde les dernières entrées.
@MainActor
final class ClipboardManager: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let maxItems = 30
    private let fileName = "clipboard.json"
    /// Vrai pendant qu'on remet un item nous-mêmes, pour ne pas le recapturer.
    private var isRestoring = false

    init() {
        lastChangeCount = pasteboard.changeCount
        items = Persistence.load([ClipboardItem].self, from: fileName) ?? []
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !isRestoring else { return }
        capture()
    }

    private func capture() {
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.text(string))
        } else if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            add(.image(data))
        }
    }

    private func add(_ content: ClipboardItem.Content) {
        let item = ClipboardItem(content: content)
        items.removeAll { $0.content == content } // remonte en tête si déjà présent
        items.insert(item, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        persist()
    }

    private func persist() {
        Persistence.save(items, to: fileName)
    }

    /// Remet un item dans le presse-papier système sans le recapturer.
    func restore(_ item: ClipboardItem) {
        isRestoring = true
        pasteboard.clearContents()
        switch item.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .image(let data):
            pasteboard.setData(data, forType: .png)
        }
        lastChangeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isRestoring = false
        }
    }

    func clear() {
        items.removeAll()
        persist()
    }
}
