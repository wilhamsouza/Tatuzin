#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWNER_WEB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${OWNER_WEB_DIR}"

flutter pub get
flutter analyze
flutter test
flutter build web --release --dart-define=TATUZIN_OWNER_API_URL=https://api.tatuzin.com.br/api
