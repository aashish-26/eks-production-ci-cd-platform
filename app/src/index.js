'use strict';
/**
 * Express application factory.
 *
 * This file creates and configures the Express app but does NOT
 * start the HTTP server. The actual listen() call lives in server.js
 * so that this module can be imported by tests without binding to a port.
 */
require('dotenv').config();
const express   = require('express');
const logger    = require('./logger');
const { Pool }  = require('pg');
const metrics   = require('./metrics');
const { register } = require('prom-client');

// --------------------------------------------------------
// PostgreSQL connection pool
//
// All PG_* variables are injected from:
//   - ConfigMap  → PGHOST, PGPORT, PGUSER, PGDATABASE  (non-sensitive)
//   - Secret     → PGPASSWORD                           (sensitive)
// max:2 limits simultaneous connections per pod instance.
// --------------------------------------------------------
const pool = new Pool({
  host:              process.env.PGHOST,
  port:              process.env.PGPORT     || 5432,
  user:              process.env.PGUSER,
  password:          process.env.PGPASSWORD,
  database:          process.env.PGDATABASE,
  max:               2,
  idleTimeoutMillis: 30000,   // release idle connections after 30 s
});

const app = express();
app.use(express.json());

// Tracks HTTP request duration in seconds labelled by method/route/status.
// Prometheus scrapes these via GET /metrics every 30 s.
app.use(metrics.middleware);

// --------------------------------------------------------
// Liveness probe  GET /health
// Kubernetes calls this to decide whether to RESTART the pod.
// We return 200 immediately — if the process is up, it is alive.
// --------------------------------------------------------
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// --------------------------------------------------------
// Readiness probe  GET /ready
// Kubernetes calls this before sending TRAFFIC to the pod.
// We check that the DB pool can obtain a connection; if not,
// the pod falls out of the Service's endpoint list.
// --------------------------------------------------------
app.get('/ready', async (req, res) => {
  try {
    const client = await pool.connect();
    client.release();
    res.status(200).json({ ready: true });
  } catch (err) {
    logger.error({ err }, 'Readiness check failed — cannot reach PostgreSQL');
    res.status(503).json({ ready: false, error: err.message });
  }
});

// --------------------------------------------------------
// Business endpoint  GET /orders
// Simulates an order-processing service.
// Replace with real DB queries in production.
// --------------------------------------------------------
app.get('/orders', (req, res) => {
  const orders = [
    { id: 1, item: 'widget', qty: 4, status: 'shipped'    },
    { id: 2, item: 'gadget', qty: 2, status: 'processing' },
  ];
  res.json({ count: orders.length, orders });
});

// --------------------------------------------------------
// Prometheus metrics endpoint  GET /metrics
// Scraped by kube-prometheus-stack every 30 s.
// Returns counters, histograms, and gauges in text format.
// --------------------------------------------------------
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// --------------------------------------------------------
// Global error handler
// Catches errors thrown in async route handlers.
// --------------------------------------------------------
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  logger.error({ err }, 'Unhandled error in route handler');
  res.status(500).json({ error: 'internal_error' });
});

// Export app and pool so tests can import them without starting the server.
module.exports = { app, pool };
