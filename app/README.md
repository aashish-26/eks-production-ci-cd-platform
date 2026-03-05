# EKS App (Phase 1)

Run the simple REST API locally and in Docker.

Environment variables
- `PORT` (default 8080)
- `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` — for readiness check
- `LOG_LEVEL` — pino log level

Local
1. cd app
2. npm install
3. npm start

Docker
1. docker build -t eks-app:local .
2. docker run -p 8080:8080 --env PGHOST=127.0.0.1 eks-app:local

Endpoints
- `GET /health` — simple 200 OK
- `GET /ready` — checks DB connectivity
- `GET /orders` — mock order data
- `GET /metrics` — Prometheus metrics

Docker Compose (recommended for local dev)
1. cd app
2. docker compose up --build
3. app will be available at http://localhost:8080

Notes: `docker compose up` starts a Postgres instance used by `/ready`.

Image scanning
- Use `./scan-image.sh <image>` to scan with Trivy (if installed).

