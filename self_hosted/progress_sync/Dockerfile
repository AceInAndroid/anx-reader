FROM node:20-alpine AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
RUN apk add --no-cache python3 make g++ \
  && npm ci --omit=dev

FROM node:20-alpine
ENV NODE_ENV=production \
    PORT=8080 \
    DATABASE_PATH=/data/progress.sqlite
WORKDIR /app
COPY --from=dependencies /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
RUN mkdir -p /data && chown -R node:node /app /data
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health >/dev/null || exit 1
CMD ["node", "src/server.js"]
