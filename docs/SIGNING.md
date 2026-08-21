# Signature : garder les permissions d'une version à l'autre

## Le problème

Les permissions macOS (Accessibilité, Surveillance des saisies, Automatisation,
Calendrier) ne sont pas liées au **chemin** de l'app, mais à son **identité de
signature**. Aujourd'hui les builds sont signées en `ad-hoc` (`codesign -s -`) :
l'identité est recalculée à chaque build, donc à chaque version macOS voit
littéralement une autre application et remet les compteurs à zéro.

C'est ça — pas le zip, pas Gatekeeper — qui oblige à tout re-cocher après une
mise à jour. La mise à jour intégrée (Réglages › Mise à jour) supprime le
téléchargement manuel et la quarantaine, mais **elle ne peut rien contre ça**.

## Le correctif : un certificat auto-signé stable

Pas besoin de compte Apple Developer payant. Un certificat auto-signé suffit :
ce qui compte pour TCC, c'est que l'identité ne change plus.

> Gatekeeper, lui, refusera toujours l'app au premier téléchargement (elle n'est
> pas notarisée) : le `spctl --add` du README reste nécessaire **une fois**. Les
> mises à jour suivantes passeront par l'app, sans quarantaine.

### 1. Créer le certificat (une seule fois, sur le Mac)

Trousseaux d'accès › menu **Trousseaux d'accès** › *Assistant de certification*
› **Créer un certificat…**

- Nom : `OtterIsland Signing`
- Type d'identité : **Auto-signée racine**
- Type de certificat : **Signature de code**
- Cocher **Laisser moi maîtriser les réglages**, puis mettre une validité longue
  (3650 jours — un certificat expiré casse la chaîne et les permissions avec).

> **Piège** : une fois créé, `security find-identity -v -p codesigning` annonce
> **`0 valid identities found`**, et avec `-v` en moins on lit
> `CSSMERR_TP_NOT_TRUSTED`. Ce n'est PAS un problème et il n'y a rien à réparer :
> l'évaluation de la chaîne de confiance échoue parce que le certificat est
> auto-signé et qu'aucune autorité ne le contresigne — ce qui est précisément ce
> qu'on a demandé. `codesign`, lui, s'en sert sans broncher. Le vérifier en une
> commande plutôt que de partir chercher un réglage de confiance inexistant :
>
> ```bash
> cp /bin/echo /tmp/sigtest && codesign -s "OtterIsland Signing" -f /tmp/sigtest \
>   && codesign -dvv /tmp/sigtest 2>&1 | grep Authority
> ```
>
> Si la sortie affiche `Authority=OtterIsland Signing`, le certificat est bon.

### 2. Exporter en .p12

Dans Trousseaux d'accès, catégorie **Mes certificats**, clic droit sur
`OtterIsland Signing` › **Exporter…** › format `.p12`, avec un mot de passe.

Puis encoder en base64 pour le transporter dans un secret GitHub :

```bash
base64 -i OtterIsland-Signing.p12 | pbcopy
```

L'export marche aussi en ligne de commande — le mot de passe est demandé
interactivement, il ne traîne donc pas dans l'historique du shell :

```bash
security export -k login.keychain-db -t identities -f pkcs12 -o ~/Desktop/OtterIsland-Signing.p12
```

### 3. Renseigner les secrets GitHub

Depuis le terminal, avec `gh` (les valeurs ne passent pas par le presse-papier
ni par l'historique) :

```bash
base64 -i ~/Desktop/OtterIsland-Signing.p12 | gh secret set MACOS_CERT_P12
gh secret set MACOS_CERT_PASSWORD          # demande le mot de passe du .p12
gh secret set MACOS_CERT_IDENTITY --body "OtterIsland Signing"
```

Ou par l'interface : dépôt › Settings › Secrets and variables › Actions ›
**New repository secret** :

| Secret | Valeur |
|---|---|
| `MACOS_CERT_P12` | le base64 collé à l'étape 2 |
| `MACOS_CERT_PASSWORD` | le mot de passe du `.p12` |
| `MACOS_CERT_IDENTITY` | `OtterIsland Signing` (le nom exact du certificat) |

Le workflow les détecte tout seul : sans eux il continue en ad-hoc, avec eux il
signe avec l'identité stable. L'étape « Vérifier la signature obtenue » l'écrit
dans le log de build.

### 4. Vérifier côté app

Réglages › **Mise à jour** › ligne « Permissions après mise à jour » :

- `✓ conservées` → l'identité est stable, c'est bon.
- `à re-cocher` → la build tourne encore en ad-hoc.

## La transition

La première version signée avec le nouveau certificat change encore d'identité
une dernière fois : il faudra re-cocher les permissions **cette fois-là**. À
partir de la suivante, elles ne bougent plus.
