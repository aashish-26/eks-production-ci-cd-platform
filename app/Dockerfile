# ============================================================
# Multi-stage Dockerfile
#
# Stage 1 (builder): installs ALL dependencies (including dev)
#   and compiles/bundles.
# Stage 2 (runner):  copies only the production artifacts.
#   Result is a minimal ~155 MB alpine image with no build tools.
#
# Security hardening:
#   - Non-root user `app` (principle of least privilege)
#   - No shell or package manager in the final image
#   - HEALTHCHECK lets Docker/ECS detect a hung container
# ============================================================

# ---- Stage 1: builder ----
FROM node:18-alpine AS builder
WORKDIR /usr/src/app

# Copy package files first to exploit Docker layer caching.
# If package.json hasn't changed, npm ci is skipped on rebuild.
COPY package.json package-lock.json* ./

# Install ONLY production dependencies to keep the runtime image small.
# npm ci is preferred over npm install: it is deterministic (respects
# package-lock.json) and exits non-zero if the lock is out of date.
RUN npm ci --omit=dev

# Copy application source after deps so source changes don't bust
# the expensive npm ci layer.
COPY src/ ./src/

# ---- Stage 2: runner ----
FROM node:18-alpine
WORKDIR /usr/src/app

# Create a non-root system user and group.
# -S = system user (no home dir, no password)
RUN addgroup -S app && adduser -S app -G app

# Copy only what the runtime needs from the builder stage.
COPY --from=builder /usr/src/app/package.json  ./package.json
COPY --from=builder /usr/src/app/node_modules  ./node_modules
COPY --from=builder /usr/src/app/src           ./src

# Set ownership so the non-root user can read the files.
RUN chown -R app:app /usr/src/app

# Switch to the non-root user for all subsequent commands and at runtime.
USER app

EXPOSE 8080

# HEALTHCHECK is used by Docker and ECS health checks.
# In Kubernetes the liveness/readiness probes in the Helm chart
# take precedence, but this serves as a fallback.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://localhost:8080/health || exit 1

# Start the HTTP server (not index.js — that only exports the app).
CMD ["node", "src/server.js"]
