# qresto-backup

Sauvegarde quotidienne, chiffrée, de la base de production de QResto vers
Cloudflare R2.

- **Quand** : chaque jour à 03:00 UTC, ou à la main (Actions → Backup → Run workflow).
- **Quoi** : `pg_dump` du schéma `public` (données métier), chiffré en AES-256
  avec GPG avant tout envoi. Rien n'est stocké dans ce dépôt.
- **Où** : un bucket Cloudflare R2 privé, dossier `backups/`.
- **Pourquoi un dépôt public séparé** : les minutes GitHub Actions y sont
  gratuites et illimitées ; la sauvegarde ne dépend d'aucune machine
  personnelle ni du quota du dépôt de l'application (privé).

## Secrets requis (Settings → Secrets and variables → Actions)

| Secret | Contenu |
|---|---|
| `SUPABASE_DB_URL` | URI du **Session pooler** Supabase (port 5432) |
| `BACKUP_GPG_PASSPHRASE` | Passphrase de chiffrement (la même que pour la restauration) |
| `R2_ENDPOINT` | `https://<account_id>.r2.cloudflarestorage.com` |
| `R2_BUCKET` | Nom du bucket |
| `R2_ACCESS_KEY_ID` | Clé d'accès R2 limitée au bucket |
| `R2_SECRET_ACCESS_KEY` | Secret associé |

La restauration est décrite dans le dépôt de l'application
(`scripts/restore-db.sh`, `docs/RUNBOOK.md`).
