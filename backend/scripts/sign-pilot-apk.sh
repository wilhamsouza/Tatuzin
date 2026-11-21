#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" != 2 ]]; then
  echo 'Usage: sign-pilot-apk.sh UNSIGNED_APK OUTPUT_APK' >&2
  exit 2
fi
SIGNING_DIR="${TATUZIN_PILOT_SIGNING_DIR:?Set the private signing directory}"
INPUT_APK="$1"
OUTPUT_APK="$2"
package_name="$(aapt dump badging "$INPUT_APK" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")"
if [[ "$package_name" != br.com.tatuzin.gestao.pilot2 ]]; then
  echo 'Refusing to sign any package other than the isolated Pilot 2.' >&2
  exit 1
fi
if apksigner verify "$INPUT_APK" >/dev/null 2>&1; then
  echo 'Expected an unsigned CI candidate.' >&2
  exit 1
fi
test -s "${SIGNING_DIR}/pilot.p12"
test -s "${SIGNING_DIR}/password"
test -s "${SIGNING_DIR}/certificate.sha256"
mkdir -p "$(dirname "$OUTPUT_APK")"
apksigner sign --ks "${SIGNING_DIR}/pilot.p12" --ks-type PKCS12 \
  --ks-key-alias tatuzin-pilot --ks-pass "file:${SIGNING_DIR}/password" \
  --out "$OUTPUT_APK" "$INPUT_APK"
actual="$(apksigner verify --print-certs "$OUTPUT_APK")"
expected="$(cat "${SIGNING_DIR}/certificate.sha256")"
if ! printf '%s\n' "$actual" | rg -Fq "$expected"; then
  rm -f "$OUTPUT_APK"
  echo 'Signing certificate did not match the pinned private key.' >&2
  exit 1
fi
printf '%s\n' "$actual"
sha256sum "$OUTPUT_APK"
