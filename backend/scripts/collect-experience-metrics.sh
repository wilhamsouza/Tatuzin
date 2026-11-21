#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_DIR="${TATUZIN_EXPERIENCE_METRICS_DIR:?Set the existing node_exporter textfile directory}"
DB_CONTAINER="${TATUZIN_EXPERIENCE_DB_CONTAINER:-tatuzin-postgres}"
READINESS_URL="${TATUZIN_EXPERIENCE_READINESS_URL:-https://api.tatuzin.com.br/api/readiness}"
temporary_file="$(mktemp "${METRICS_DIR}/.tatuzin-experience.XXXXXX")"
trap 'rm -f "$temporary_file"' EXIT

docker exec -i "$DB_CONTAINER" sh -c \
  'exec psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At' \
  < "${SCRIPT_DIR}/../observability/experience-metrics.sql" > "$temporary_file"

readiness_status="$(curl --silent --show-error --max-time 10 --output /dev/null --write-out '%{http_code}' "$READINESS_URL" || true)"
readiness=0
if [[ "$readiness_status" == 200 ]]; then readiness=1; fi
{
  printf '# HELP tatuzin_experience_api_ready Public HTTPS readiness result.\n'
  printf '# TYPE tatuzin_experience_api_ready gauge\n'
  printf 'tatuzin_experience_api_ready %s\n' "$readiness"
  printf '# HELP tatuzin_experience_collector_timestamp_seconds Last successful database collection.\n'
  printf '# TYPE tatuzin_experience_collector_timestamp_seconds gauge\n'
  printf 'tatuzin_experience_collector_timestamp_seconds %s\n' "$(date +%s)"
} >> "$temporary_file"

chmod 0644 "$temporary_file"
mv "$temporary_file" "${METRICS_DIR}/tatuzin_experience.prom"
