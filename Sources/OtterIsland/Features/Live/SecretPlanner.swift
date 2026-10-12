import CoreGraphics
import Foundation

// MARK: - Abstraction d'un élément d'interface

/// Un élément de l'interface, tel que le voit le planificateur de masquage.
///
/// La vraie implémentation lit l'Accessibilité (`AXScanNode`, dans
/// `LivePrivacy.swift`) ; les tests en fournissent de fausses, ce qui permet de
/// vérifier la logique de masquage sans autorisation système ni vraie page web.
protocol ScanNode: AnyObject {
    var role: String { get }
    var subrole: String { get }
    /// Texte de l'élément (valeur), s'il en a un.
    var value: String? { get }
    /// Tout ce que l'élément dit de lui-même : placeholder, description,
    /// titre, aide, identifiant et classes du DOM. C'est la « configuration
    /// du site » : un champ `id="password"`, `placeholder="Clé API"`…
    var descriptors: [String] { get }
    /// Cadre à l'écran, repère AppKit.
    var frame: CGRect? { get }
    var parent: ScanNode? { get }
    var children: [ScanNode] { get }
    /// Cadre d'une plage de caractères, si l'app sait le donner.
    func textBounds(location: Int, length: Int) -> CGRect?
    /// Le texte à l'écran (champ actif : pas tout l'historique d'un terminal).
    func visibleText() -> (text: String, offset: Int)?
    func isSame(as other: ScanNode) -> Bool
}

// MARK: - Heuristiques

enum SecretHeuristics {

    /// Minuscules, sans accents, tout ce qui n'est pas une lettre ou un chiffre
    /// devient une espace, et les mots collés en casse mixte sont séparés
    /// (`apiKeyInput` → « api key input »).
    static func normalize(_ raw: String) -> String {
        var spaced = ""
        var previous: Character = " "
        for ch in raw {
            if ch.isUppercase, previous.isLowercase { spaced.append(" ") }
            spaced.append(ch)
            previous = ch
        }
        let folded = spaced
            .replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "Œ", with: "oe")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        var out = ""
        for ch in folded {
            out.append(ch.isLetter || ch.isNumber ? ch : " ")
        }
        let words = out.split(separator: " ").joined(separator: " ")
        return " " + words + " "
    }

    private static func containsAny(_ normalized: String, words: [String]) -> Bool {
        words.contains { normalized.contains(" \($0) ") }
    }

    /// Fragments sûrs en sous-chaîne (jamais de faux positif courant).
    private static let secretSubstrings = [
        "password", "passwd", "passwort", "motdepasse", "contrasena", "apikey", "secretkey",
        "privatekey", "accesstoken", "authtoken", "clientsecret", "apisecret",
    ]
    /// Mots et expressions à frontières de mots.
    private static let secretWords = [
        "pwd", "mdp", "passphrase", "passcode", "secret", "mot de passe", "pass phrase",
        "api key", "api token", "api secret", "secret key", "private key", "access key",
        "access token", "auth token", "bearer token", "client secret", "signing key",
        "service role", "personal access token",
        "cle api", "cle secrete", "cle privee", "cle d acces", "jeton api", "jeton d acces", "jeton secret",
    ]

    /// Ce champ de saisie est-il, d'après ce qu'il dit de lui-même, un champ
    /// de mot de passe ou de secret ?
    static func looksLikeSecretField(_ descriptors: [String]) -> Bool {
        for descriptor in descriptors where !descriptor.isEmpty {
            let n = normalize(descriptor)
            if secretSubstrings.contains(where: { n.replacingOccurrences(of: " ", with: "").contains($0) }) { return true }
            if containsAny(n, words: secretWords) { return true }
        }
        return false
    }

    /// Libellé qui annonce une clé juste à côté : « API key », « Secret key »,
    /// « Clé API », « Token »… (le mot seul suffit ICI, parce qu'il doit en
    /// plus être suivi d'une valeur qui ressemble à un jeton).
    static func isKeyLabel(_ text: String) -> Bool {
        let n = normalize(text)
        if n.trimmingCharacters(in: .whitespaces).count > 80 { return false }   // une phrase n'est pas un libellé
        if secretSubstrings.contains(where: { n.replacingOccurrences(of: " ", with: "").contains($0) }) { return true }
        return containsAny(n, words: secretWords + ["token", "jeton", "bearer", "credentials", "cle"])
    }

    /// Mots qui désignent un bouton afficher / masquer le mot de passe.
    private static let revealWords = [
        "show", "hide", "reveal", "visible", "visibility", "toggle", "unmask", "display",
        "afficher", "masquer", "montrer", "cacher", "voir", "dissimuler",
        "oeil", "eye", "mostrar", "ocultar", "anzeigen", "verbergen", "zeigen",
    ]

    static func looksLikeRevealToggle(_ descriptors: [String]) -> Bool {
        descriptors.contains { containsAny(normalize($0), words: revealWords) }
    }

    /// Une chaîne qui a l'allure d'un jeton : longue, sans espace, mêlant
    /// lettres et chiffres. Ne suffit PAS à masquer : il faut aussi un libellé.
    static func looksLikeToken(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (20...512).contains(s.count), !s.contains("://"), !s.hasPrefix("/") else { return false }
        var letters = 0, digits = 0
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A: letters += 1
            case 0x30...0x39: digits += 1
            case 0x2D, 0x5F, 0x2B, 0x2F, 0x3D, 0x2E, 0x3A, 0x7E: break      // - _ + / = . : ~
            default: return false                                            // espace, ponctuation, accents : pas un jeton
            }
        }
        return letters >= 4 && digits >= 2
    }

    // MARK: Géométrie

    /// Retire de `rect` les zones de `holes` et renvoie les morceaux restants.
    /// Sert à couvrir un champ SANS recouvrir l'œil qui l'accompagne.
    static func subtract(_ rect: CGRect, holes: [CGRect]) -> [CGRect] {
        var pieces = [rect]
        for hole in holes {
            var next: [CGRect] = []
            for piece in pieces {
                guard piece.intersects(hole) else { next.append(piece); continue }
                let cut = piece.intersection(hole)
                // Gauche, droite, bas, haut : jamais de chevauchement entre morceaux.
                next.append(CGRect(x: piece.minX, y: piece.minY, width: cut.minX - piece.minX, height: piece.height))
                next.append(CGRect(x: cut.maxX, y: piece.minY, width: piece.maxX - cut.maxX, height: piece.height))
                next.append(CGRect(x: cut.minX, y: piece.minY, width: cut.width, height: cut.minY - piece.minY))
                next.append(CGRect(x: cut.minX, y: cut.maxY, width: cut.width, height: piece.maxY - cut.maxY))
            }
            pieces = next.filter { $0.width >= 6 && $0.height >= 6 }
        }
        return pieces
    }
}

// MARK: - Planificateur

enum SecretPlanner {

    /// Motifs de clés connues. Le groupe 1, quand il existe, est la seule
    /// partie à masquer (la valeur, pas le nom de la variable).
    static let patterns: [NSRegularExpression] = [
        #"sk-(?:proj-|ant-|svcacct-|admin-)?[A-Za-z0-9_\-]{16,}"#, // OpenAI, Anthropic
        #"(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}"#,       // Stripe
        #"gh[pousr]_[A-Za-z0-9]{30,}"#,                         // GitHub
        #"github_pat_[A-Za-z0-9_]{40,}"#,
        #"AKIA[0-9A-Z]{16}"#,                                   // AWS
        #"AIza[0-9A-Za-z_\-]{35}"#,                             // Google
        #"xox[abposr]-[A-Za-z0-9\-]{10,}"#,                     // Slack
        #"pat[A-Za-z0-9]{14}\.[a-f0-9]{40,}"#,                  // Airtable
        #"(?:secret_|ntn_)[A-Za-z0-9]{30,}"#,                   // Notion
        #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#, // JWT (Supabase…)
        #"hooks\.slack\.com/services/[A-Za-z0-9/]{20,}"#,
        #"hook\.[a-z0-9]+\.make\.com/([A-Za-z0-9]{12,})"#,      // webhook Make
        #"(?i)\b(?:bearer|basic|token|digest)\s+([A-Za-z0-9._~+/=\-]{16,})"#,  // Authorization: Bearer …
        // En-têtes HTTP d'authentification : on garde le nom (et « Bearer »),
        // on masque la valeur.
        #"(?i)(?:authorization|proxy-authorization|x-api-key|api-key|x-auth-token|x-access-token|x-goog-api-key|x-make-apikey|apikey|cookie|set-cookie)["']?\s*[:=]\s*["']?(?:(?:bearer|basic|token|digest)\s+)?([^\s"',;]{8,})"#,
        // Paramètres d'URL : ?key=… &api_key=… &access_token=…
        #"(?i)[?&](?:key|api_?key|apikey|token|access_token|auth|secret|password|sig|signature)=([^&\s"'#]{8,})"#,
        // Identifiants dans une URL : https://user:motdepasse@hote
        #"(?i)[a-z][a-z0-9+.\-]*://[^\s/:@]+:([^\s/@]{4,})@"#,
        // Clés privées PEM
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"(?i)(?:password|passwd|pwd|secret|token|api[_\-]?key|access[_\-]?key|private[_\-]?key)["']?\s*[:=]\s*["']?([^\s"',;]{6,})"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Rôles qui portent du texte lisible.
    static let textRoles: Set<String> = [
        "AXStaticText", "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
    ]

    private static let inputRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Contrôles susceptibles d'être l'œil d'un champ mot de passe.
    private static let controlRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXMenuButton", "AXPopUpButton", "AXImage", "AXLink",
    ]

    /// Au-delà, ce n'est plus une icône mais un conteneur.
    private static let maxControlSize: CGFloat = 64

    // MARK: Éléments

    static func isSecure(_ node: ScanNode) -> Bool {
        node.role == "AXSecureTextField" || node.subrole == "AXSecureTextField"
    }

    /// Champ à couvrir d'avance : un vrai champ mot de passe, ou un champ de
    /// saisie qui se déclare comme tel (même rendu en clair par l'œil).
    static func isSecretField(_ node: ScanNode) -> Bool {
        isSecure(node) || (inputRoles.contains(node.role) && SecretHeuristics.looksLikeSecretField(node.descriptors))
    }

    static func isRevealCandidate(_ node: ScanNode) -> Bool {
        guard let frame = node.frame, frame.width <= maxControlSize, frame.height <= maxControlSize else { return false }
        return controlRoles.contains(node.role) || SecretHeuristics.looksLikeRevealToggle(node.descriptors)
    }

    /// Zones à laisser découvertes : tout contrôle de la taille d'une icône qui
    /// touche le champ (l'œil afficher / masquer, mais aussi une croix
    /// d'effacement). Un œil recouvert empêcherait de voir qu'on peut cliquer.
    static func holes(for field: CGRect, controls: [CGRect]) -> [CGRect] {
        controls
            .filter { $0.insetBy(dx: -6, dy: -6).intersects(field) }
            .map { $0.insetBy(dx: -3, dy: -3) }
    }

    /// Les rectangles qui couvrent un champ, œil exclu.
    static func cover(field: CGRect, controls: [CGRect]) -> [CGRect] {
        SecretHeuristics.subtract(field.insetBy(dx: -2, dy: -2), holes: holes(for: field, controls: controls))
    }

    // MARK: Champ actif

    /// Le champ où l'on tape : couvert d'avance s'il se déclare secret, sinon
    /// on cherche une clé dans son texte (ou près d'un libellé de clé).
    static func planFocused(_ node: ScanNode, anticipate: Bool) -> [CGRect] {
        if anticipate, isSecretField(node) {
            guard let frame = node.frame, frame.width <= 1600, frame.height <= 300 else { return [] }
            return cover(field: frame, controls: nearbyControls(of: node))
        }
        // Un vrai champ mot de passe affiche déjà des points : rien à faire
        // (comportement d'origine, sans anticipation).
        if isSecure(node) { return [] }
        guard let visible = node.visibleText(), !visible.text.isEmpty else { return [] }
        var found = matches(in: visible.text, offset: visible.offset, node: node)
        if found.isEmpty, anticipate, textRoles.contains(node.role),
           SecretHeuristics.looksLikeToken(visible.text), hasKeyLabel(near: node) {
            found = tokenRect(node, text: visible.text, offset: visible.offset)
        }
        return found
    }

    /// Contrôles voisins du champ : ses frères, puis ceux de son parent (le
    /// bouton œil est souvent à côté de l'enveloppe du champ plutôt que dedans).
    private static func nearbyControls(of node: ScanNode) -> [CGRect] {
        var frames: [CGRect] = []
        var level: ScanNode? = node
        for _ in 0..<2 {
            guard let parent = level?.parent else { break }
            for sibling in parent.children.prefix(40) where !sibling.isSame(as: node) && isRevealCandidate(sibling) {
                if let f = sibling.frame { frames.append(f) }
            }
            level = parent
        }
        return frames
    }

    // MARK: Fenêtre active

    /// Parcours en largeur de la fenêtre, limité à ce qui est À L'ÉCRAN : un
    /// sous-arbre dont le cadre ne touche pas la fenêtre (le bas d'une page de
    /// résultats, un onglet caché) n'est pas visité. Sans cet élagage, une page
    /// Google épuisait le budget dans son en-tête avant d'atteindre le bloc de
    /// code affiché.
    static func planTree(root: ScanNode, anticipate: Bool, nodeBudget: Int = 2500) -> [CGRect] {
        let windowFrame = root.frame
        var queue: [ScanNode] = [root]
        var head = 0
        var rects: [CGRect] = []
        var secretFields: [CGRect] = []
        var controls: [CGRect] = []
        var tokenChecks = 0

        while head < queue.count, head < nodeBudget, rects.count + secretFields.count < 40 {
            let node = queue[head]
            head += 1

            // Élagage : hors de la fenêtre visible, on ne descend pas.
            if let windowFrame, let f = node.frame, f.width > 0, f.height > 0, !f.intersects(windowFrame) {
                continue
            }

            if anticipate {
                if isSecretField(node) {
                    if let f = node.frame, f.width <= 1600, f.height <= 300 { secretFields.append(f) }
                    continue    // champ entier couvert : inutile d'y chercher des motifs
                }
                if isRevealCandidate(node), let f = node.frame { controls.append(f) }
            } else if isSecure(node) {
                continue
            }

            if textRoles.contains(node.role), let text = node.value, text.count >= 8 {
                let clipped = String(text.prefix(4000))
                var found = matches(in: clipped, offset: 0, node: node)
                if found.isEmpty, anticipate, tokenChecks < 8, SecretHeuristics.looksLikeToken(clipped) {
                    tokenChecks += 1
                    if hasKeyLabel(near: node) { found = tokenRect(node, text: clipped, offset: 0) }
                }
                rects += found
            }
            queue.append(contentsOf: node.children.prefix(300))
        }

        let covers = secretFields.flatMap { cover(field: $0, controls: controls) }
        return Array((covers + rects).prefix(60))
    }

    // MARK: Libellé d'une clé

    /// Un libellé de clé se trouve-t-il juste avant cette valeur ?
    ///
    /// Le libellé LE PLUS PROCHE décide : sous « Commit », le SHA d'un commit
    /// n'est pas une clé, même si « API key » se trouve plus haut dans la
    /// carte. On regarde ce que l'élément dit de lui-même, puis ses frères
    /// précédents (en passant les valeurs voisines), puis ceux de son parent.
    static func hasKeyLabel(near node: ScanNode) -> Bool {
        if node.descriptors.contains(where: SecretHeuristics.isKeyLabel) { return true }
        var current: ScanNode = node
        for _ in 0..<3 {
            guard let parent = current.parent else { return false }
            let siblings = parent.children
            if let index = siblings.firstIndex(where: { $0.isSame(as: current) }) {
                var skipped = 0
                for sibling in siblings[..<index].reversed() {
                    let texts = labelTexts(of: sibling)
                    if texts.isEmpty { continue }
                    // Une valeur voisine (un jeton de plus) n'est pas un libellé.
                    if texts.allSatisfy(SecretHeuristics.looksLikeToken) {
                        skipped += 1
                        if skipped >= 3 { break }
                        continue
                    }
                    return texts.contains(where: SecretHeuristics.isKeyLabel)
                }
            }
            if parent.descriptors.contains(where: SecretHeuristics.isKeyLabel) { return true }
            current = parent
        }
        return false
    }

    /// Le texte d'un voisin : le sien, sinon celui de ses premiers enfants (une
    /// cellule de tableau contient son libellé un niveau plus bas).
    private static func labelTexts(of node: ScanNode) -> [String] {
        let own = (node.value.map { [$0] } ?? []) + node.descriptors
        if !own.isEmpty { return own }
        return node.children.prefix(4).flatMap { child in
            (child.value.map { [$0] } ?? []) + child.descriptors
        }
    }

    private static func tokenRect(_ node: ScanNode, text: String, offset: Int) -> [CGRect] {
        let length = (text as NSString).length
        if let r = node.textBounds(location: offset, length: length) { return [r.insetBy(dx: -3, dy: -2)] }
        if let f = node.frame, f.width < 4000, f.height < 600 { return [f.insetBy(dx: -2, dy: -2)] }
        return []
    }

    // MARK: Correspondances

    static func matches(in text: String, offset: Int, node: ScanNode) -> [CGRect] {
        let ns = text as NSString
        var out: [CGRect] = []
        var usedFrame = false
        for regex in patterns {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let range = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                    ? match.range(at: 1) : match.range
                if let rect = node.textBounds(location: range.location + offset, length: range.length) {
                    out.append(rect.insetBy(dx: -3, dy: -2))
                } else if !usedFrame, let frame = node.frame, frame.width < 4000, frame.height < 600 {
                    // L'app ne sait pas situer un caractère : on couvre tout
                    // l'élément. Moins élégant, mais rien ne fuit.
                    usedFrame = true
                    out.append(frame.insetBy(dx: -2, dy: -2))
                }
                if out.count >= 20 { return out }
            }
        }
        return out
    }
}
