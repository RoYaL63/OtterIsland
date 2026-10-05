# Intégration Claude Code

> **Le plus simple** : Réglages › Assistants IA › Claude Code › **Brancher**. OtterIsland ajoute lui-même un hook `Notification` qui relaie « Claude a besoin de ta permission » / « Claude attend ta réponse » dans l'île (script `~/.otterisland/claude-notify.sh`, copie de sauvegarde de `~/.claude/settings.json`). Rien à écrire.
>
> La suite de ce document décrit l'**inbox par dossier**, pour brancher tes propres scripts avec Approuver / Refuser.

OtterIsland surveille un dossier et affiche les demandes d'action dans l'encoche. Ta décision (approuver / refuser) repart dans un dossier de sortie. Aucun réseau, aucune permission spéciale.

## Dossiers

```
~/.otterisland/
├── inbox/    demandes déposées par Claude Code (JSON)
└── outbox/   réponses écrites par OtterIsland (JSON)
```

## Format d'une demande (inbox)

Un fichier `<id>.json` :

```json
{
  "id": "run-2026-07-18-abc123",
  "title": "Lancer les tests ?",
  "detail": "npm test dans otters-api",
  "kind": "confirm",
  "createdAt": "2026-07-18T10:30:00Z"
}
```

`id` doit être unique. `title` est ce que la loutre affiche. `detail` et `kind` sont optionnels.

## Format d'une réponse (outbox)

OtterIsland écrit `<id>.json` :

```json
{
  "id": "run-2026-07-18-abc123",
  "approved": true,
  "respondedAt": "2026-07-18T10:30:12Z"
}
```

## Brancher un hook Claude Code

Exemple de hook `Notification` ou `PreToolUse` qui demande une validation via l'encoche et attend la réponse. Voir `examples/otterisland-ask.sh`. Tu peux l'appeler depuis un hook dans `~/.claude/settings.json` :

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.otterisland/otterisland-ask.sh \"Exécuter une commande shell ?\"" }
        ]
      }
    ]
  }
}
```

Le script sort avec le code 0 si tu approuves, 2 si tu refuses (ce qui bloque l'action côté Claude Code).
