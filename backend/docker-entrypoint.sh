#!/bin/sh

set -eu

if [ "$#" -eq 0 ]; then
  set -- npm run start:prod
fi

if [ "${RUN_DB_MIGRATIONS:-false}" = "true" ] \
  && [ "$1" = "npm" ] \
  && [ "${2:-}" = "run" ] \
  && [ "${3:-}" = "start:prod" ]; then
  npm run prisma:deploy
fi

exec "$@"
