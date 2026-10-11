#!/usr/bin/env bash
set -euo pipefail

# P9.A.6 — sauvegarde chiffrée de Qresto-projet-01 vers Cloudflare R2.
#
# Filet unique pendant toute la bêta (ADR-008) : le plan Supabase reste
# Free, donc l'hébergeur ne fournit aucune sauvegarde. Ce script est
# invoqué quotidiennement par .github/workflows/backup.yml (l'horloge) ;
# R2 en est la destination (jamais un dépôt Git — 100 Mo/fichier max,
# aucune purge automatique).
#
# Dépôt PUBLIC (minutes Actions gratuites et illimitées, aucune dépendance à
# une machine) : les journaux sont lisibles par tous. Le script n'affiche
# donc ni le nom du bucket ni aucune valeur de configuration ; les secrets
# sont de plus masqués par GitHub.
#
# Variables d'environnement requises :
#   SUPABASE_DB_URL          connexion Postgres de Qresto-projet-01 via le
#                            SESSION POOLER (Supavisor), pas la connexion
#                            directe : la connexion directe de Supabase
#                            (db.<ref>.supabase.co) est IPv6 uniquement
#                            depuis fin 2024, et les runners GitHub Actions
#                            sont IPv4 uniquement — pg_dump échouerait à s'y
#                            connecter. Le Session Pooler est IPv4 et
#                            disponible sur le plan Free (Dashboard →
#                            Settings → Database → Connection string →
#                            onglet "Session pooler", PAS "Transaction
#                            pooler" — ce dernier n'est pas compatible avec
#                            pg_dump) :
#                            postgresql://postgres.{ref}:{password}@aws-0-{region}.pooler.supabase.com:5432/postgres
#   BACKUP_GPG_PASSPHRASE    passphrase de chiffrement symétrique GPG
#   R2_ENDPOINT              https://<account_id>.r2.cloudflarestorage.com
#   R2_BUCKET                nom du bucket R2
#   R2_ACCESS_KEY_ID         clé d'accès S3-compatible scoppée au bucket
#   R2_SECRET_ACCESS_KEY     secret associé

: "${SUPABASE_DB_URL:?SUPABASE_DB_URL manquant}"
: "${BACKUP_GPG_PASSPHRASE:?BACKUP_GPG_PASSPHRASE manquant}"
: "${R2_ENDPOINT:?R2_ENDPOINT manquant}"
: "${R2_BUCKET:?R2_BUCKET manquant}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID manquant}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY manquant}"

STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
DUMP_FILE="qresto-projet-01-${STAMP}.dump"
ENCRYPTED_FILE="${DUMP_FILE}.gpg"

cleanup() {
  # Le dump en clair ne doit jamais survivre au script, même en cas d'échec.
  rm -f "$DUMP_FILE" "$ENCRYPTED_FILE"
}
trap cleanup EXIT

echo "→ pg_dump (format custom, compressé, schéma public uniquement) vers ${DUMP_FILE}"
# --schema=public : les données métier vivent exclusivement dans public
# (vérifié dans toutes les migrations). Les schémas gérés par Supabase
# (auth, storage, realtime, extensions...) sont volontairement exclus —
# ils existent déjà, avec leurs propres rôles propriétaires système, sur
# tout projet fraîchement provisionné. Un test de restauration réel
# (07/09/2026) a confirmé qu'un dump non scopé produit des centaines
# d'erreurs "must be owner of table ..." à la restauration sur un autre
# projet. Limitation assumée et documentée dans docs/RUNBOOK.md : ce
# script protège les données métier, pas les comptes auth.users — une
# reprise complète de compte relève du PITR natif Supabase (plan payant).
pg_dump "$SUPABASE_DB_URL" \
  --no-owner \
  --no-privileges \
  --schema=public \
  --format=custom \
  --file="$DUMP_FILE"

echo "→ chiffrement GPG symétrique (AES-256) vers ${ENCRYPTED_FILE}"
gpg --batch --yes --pinentry-mode loopback \
  --passphrase "$BACKUP_GPG_PASSPHRASE" \
  --symmetric --cipher-algo AES256 \
  --output "$ENCRYPTED_FILE" \
  "$DUMP_FILE"
rm -f "$DUMP_FILE"

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"

OBJECT_KEY="backups/${ENCRYPTED_FILE}"
echo "→ upload vers R2 (${OBJECT_KEY})"
aws s3 cp "$ENCRYPTED_FILE" "s3://${R2_BUCKET}/${OBJECT_KEY}" \
  --endpoint-url "$R2_ENDPOINT" --only-show-errors

echo "→ vérification : l'objet existe bien sur R2"
aws s3api head-object \
  --endpoint-url "$R2_ENDPOINT" \
  --bucket "$R2_BUCKET" \
  --key "$OBJECT_KEY" >/dev/null

echo "✓ Sauvegarde ${OBJECT_KEY} confirmée sur R2."
