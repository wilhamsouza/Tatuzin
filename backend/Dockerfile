FROM node:24-alpine AS base
WORKDIR /app

ENV NODE_ENV=production \
    PORT=4000 \
    HOST=0.0.0.0 \
    PRISMA_SKIP_POSTINSTALL_GENERATE=true \
    npm_config_update_notifier=false

FROM base AS deps

COPY package*.json ./
RUN npm ci --include=dev

FROM deps AS build
ENV NODE_ENV=development

COPY prisma ./prisma
COPY src ./src
COPY tsconfig.json ./
RUN npm run prisma:generate
RUN npm run build

FROM base AS prod-deps
WORKDIR /app

COPY package*.json ./
COPY prisma ./prisma
RUN npm ci --omit=dev \
 && npm run prisma:generate \
 && npm cache clean --force

FROM node:24-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production \
    PORT=4000 \
    HOST=0.0.0.0

COPY package*.json ./
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/prisma ./prisma
COPY docker-entrypoint.sh ./docker-entrypoint.sh

RUN chmod +x ./docker-entrypoint.sh \
 && chown -R node:node /app

USER node

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD wget -qO- "http://127.0.0.1:${PORT:-4000}/api/readiness" >/dev/null 2>&1 || exit 1

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["npm", "run", "start:prod"]
