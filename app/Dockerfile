FROM node:18-alpine AS builder
WORKDIR /usr/src/app
COPY package.json package-lock.json* ./
# Use npm ci when lockfile exists, otherwise fall back to npm install
RUN if [ -f package-lock.json ]; then npm ci --production; else npm install --production; fi

# Copy only app sources after installing deps to leverage Docker layer caching
COPY . .

FROM node:18-alpine
WORKDIR /usr/src/app
# create non-root user and set ownership
RUN addgroup -S app && adduser -S app -G app
COPY --from=builder /usr/src/app/package.json ./package.json
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/src ./src
COPY --from=builder /usr/src/app/.env.example ./.env.example
RUN chown -R app:app /usr/src/app
USER app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/health || exit 1
CMD ["node","src/index.js"]
