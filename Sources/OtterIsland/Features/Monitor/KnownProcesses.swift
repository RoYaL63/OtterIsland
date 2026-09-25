import Foundation

/// Traduction des noms de processus en langage humain.
///
/// « mds_stores à 140 % » ne dit rien à personne ; « Spotlight réindexe tes
/// fichiers, ça se calme tout seul » dit quoi faire — c'est-à-dire, ici, rien.
/// La moitié des « mon Mac chauffe » viennent de tâches système passagères, et
/// les reconnaître évite de tuer un processus qui aurait fini dans dix minutes.
enum KnownProcesses {

    enum Kind: Sendable {
        /// Tâche de fond du système : passagère, à laisser finir.
        case transient
        /// Symptôme et non cause (kernel_task qui bride).
        case symptom
        /// Composant d'une application (onglet, extension, rendu).
        case appComponent
        /// Service système permanent : élevé = anomalie à surveiller.
        case system
    }

    struct Info: Sendable {
        let label: String
        let explanation: String
        let kind: Kind
    }

    /// Correspondance par PRÉFIXE : `ps -c` tronque certains noms et les
    /// variantes (mdworker, mdworker_shared…) partagent le même sens.
    private static let table: [(prefix: String, info: Info)] = [
        ("kernel_task", Info(
            label: "Noyau macOS",
            explanation: "Quand il consomme beaucoup, c'est souvent macOS qui occupe volontairement le processeur pour le laisser refroidir. C'est un SYMPTÔME de chauffe : la cause est ce qui tournait juste avant.",
            kind: .symptom)),
        ("WindowServer", Info(
            label: "Affichage",
            explanation: "Dessine toutes les fenêtres. Élevé avec des écrans externes haute définition, beaucoup d'animations ou de vidéos. Au-delà de 1,5 Go de RAM après des jours sans redémarrer, une fermeture de session le remet à zéro.",
            kind: .system)),
        ("mds_stores", Info(
            label: "Spotlight (index)",
            explanation: "Spotlight indexe tes fichiers. Normal après une mise à jour de macOS ou la copie de nombreux fichiers : ça se calme seul.",
            kind: .transient)),
        ("mdworker", Info(
            label: "Spotlight (analyse)",
            explanation: "Spotlight lit le contenu des fichiers pour les rendre cherchables. Passager.",
            kind: .transient)),
        ("mds", Info(
            label: "Spotlight",
            explanation: "Coordonne l'indexation Spotlight. Passager.",
            kind: .transient)),
        ("photoanalysisd", Info(
            label: "Photos (analyse)",
            explanation: "Photos reconnaît visages et objets dans ta photothèque. Surtout après un import ; il travaille davantage quand le Mac est branché et inactif.",
            kind: .transient)),
        ("mediaanalysisd", Info(
            label: "Analyse multimédia",
            explanation: "Analyse d'images et de vidéos (Photos, Texte en direct). Passager.",
            kind: .transient)),
        ("photolibraryd", Info(
            label: "Photothèque",
            explanation: "Synchronisation ou maintenance de la photothèque. Passager.",
            kind: .transient)),
        ("backupd", Info(
            label: "Time Machine",
            explanation: "Une sauvegarde Time Machine est en cours. Laisse-la finir.",
            kind: .transient)),
        ("bird", Info(
            label: "iCloud Drive",
            explanation: "Synchronisation iCloud Drive. Élevé pendant l'envoi ou la réception de gros fichiers.",
            kind: .transient)),
        ("cloudd", Info(
            label: "iCloud",
            explanation: "Synchronisation iCloud (Photos, Notes, Drive…). Passager.",
            kind: .transient)),
        ("fileproviderd", Info(
            label: "Synchronisation de fichiers",
            explanation: "iCloud Drive, Dropbox, Google Drive ou OneDrive synchronisent des fichiers.",
            kind: .transient)),
        ("softwareupdated", Info(
            label: "Mise à jour macOS",
            explanation: "Téléchargement ou préparation d'une mise à jour de macOS.",
            kind: .transient)),
        ("installd", Info(
            label: "Installation",
            explanation: "Une application ou une mise à jour s'installe.",
            kind: .transient)),
        ("XProtect", Info(
            label: "Antivirus Apple",
            explanation: "XProtect vérifie les fichiers téléchargés. Passager.",
            kind: .transient)),
        ("syspolicyd", Info(
            label: "Vérification des apps",
            explanation: "Contrôle la signature d'une app récemment installée ou mise à jour. Passager.",
            kind: .transient)),
        ("trustd", Info(
            label: "Certificats",
            explanation: "Vérification de certificats (sites web, apps). Élevé seulement en cas d'anomalie.",
            kind: .system)),
        ("ReportCrash", Info(
            label: "Rapport de plantage",
            explanation: "Une application vient de planter, macOS écrit le rapport.",
            kind: .transient)),
        ("nsurlsessiond", Info(
            label: "Téléchargements de fond",
            explanation: "Téléchargements en arrière-plan (App Store, iCloud, mises à jour).",
            kind: .transient)),
        ("VTDecoderXPCService", Info(
            label: "Décodage vidéo",
            explanation: "Lecture d'une vidéo (YouTube, Netflix, visio). Normal pendant la lecture.",
            kind: .appComponent)),
        ("VTEncoderXPCService", Info(
            label: "Encodage vidéo",
            explanation: "Encodage vidéo : partage d'écran, visio, enregistrement ou export.",
            kind: .appComponent)),
        ("com.apple.WebKit.WebContent", Info(
            label: "Page web (Safari)",
            explanation: "Un onglet Safari ou une page web affichée dans une app. Une page chargée de publicités, de vidéos ou une web-app (Figma, Notion, Airtable…) peut occuper un cœur entier.",
            kind: .appComponent)),
        ("Google Chrome Helper", Info(
            label: "Onglet ou extension Chrome",
            explanation: "Chaque onglet et chaque extension de Chrome est un processus. Pour savoir lequel consomme : Chrome › Fenêtre › Gestionnaire de tâches.",
            kind: .appComponent)),
        ("Microsoft Edge Helper", Info(
            label: "Onglet ou extension Edge",
            explanation: "Onglet ou extension d'Edge. Détail dans Edge › ⋯ › Plus d'outils › Gestionnaire des tâches du navigateur.",
            kind: .appComponent)),
        ("Brave Browser Helper", Info(
            label: "Onglet ou extension Brave",
            explanation: "Onglet ou extension de Brave. Détail dans le gestionnaire de tâches de Brave.",
            kind: .appComponent)),
        ("coreaudiod", Info(
            label: "Audio",
            explanation: "Moteur audio. Élevé = plugin audio ou périphérique qui se comporte mal.",
            kind: .system)),
        ("com.docker", Info(
            label: "Docker",
            explanation: "La machine virtuelle de Docker. Elle garde sa RAM même conteneurs arrêtés : quitte Docker Desktop quand tu ne t'en sers pas.",
            kind: .appComponent)),
        ("qemu", Info(
            label: "Machine virtuelle",
            explanation: "Une machine virtuelle tourne (Docker, UTM…).",
            kind: .appComponent)),
        ("node", Info(
            label: "Node.js",
            explanation: "Un script ou serveur Node.js (outil de dev, n8n local, build…).",
            kind: .appComponent)),
    ]

    static func info(for processName: String) -> Info? {
        table.first { processName.hasPrefix($0.prefix) }?.info
    }

    /// Navigateurs dont le titre de fenêtre donne l'onglet actif.
    static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.apple.Safari",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    /// Processus de rendu web de Safari : ils ne descendent pas de Safari (ce
    /// sont des services XPC lancés par launchd), il faut les lui rattacher à
    /// la main.
    static func isSafariWebContent(_ name: String) -> Bool {
        name.hasPrefix("com.apple.WebKit.WebContent") || name.hasPrefix("Safari Web Content")
    }
}
