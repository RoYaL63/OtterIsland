#!/usr/bin/env bash
# Dépose une demande d'action dans l'encoche OtterIsland et attend ta décision.
# Usage : otterisland-ask.sh "Titre de la demande" ["détail"]
# Sortie : 0 = approuvé, 2 = refusé, 1 = timeout/erreur.

set -euo pipefail

ROOT="$HOME/.otterisland"
INBOX="$ROOT/inbox"
OUTBOX="$ROOT/outbox"
mkdir -p "$INBOX" "$OUTBOX"

TITLE="${1:-Action Claude Code ?}"
DETAIL="${2:-}"
ID="ask-$(date +%s)-$$"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$INBOX/$ID.json" <<EOF
{
  "id": "$ID",
  "title": "$TITLE",
  "detail": "$DETAIL",
  "kind": "confirm",
  "createdAt": "$NOW"
}
EOF

# Attend la réponse (max 120 s).
RESPONSE="$OUTBOX/$ID.json"
for _ in $(seq 1 240); do
  if [ -f "$RESPONSE" ]; then
    if grep -q '"approved"[[:space:]]*:[[:space:]]*true' "$RESPONSE"; then
      rm -f "$RESPONSE"
      exit 0
    else
      rm -f "$RESPONSE"
      exit 2
    fi
  fi
  sleep 0.5
done

# Timeout : on nettoie et on laisse passer sans bloquer.
rm -f "$INBOX/$ID.json"
exit 1
