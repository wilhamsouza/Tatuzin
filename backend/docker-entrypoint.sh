#!/bin/sh

set -eu

if [ "${RUN_DB_MIGRATIONS:-true}" = "true" ]; then
  npm run prisma:deploy
fi

exec node dist/main.js
