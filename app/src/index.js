'use strict';
require('dotenv').config();
const express = require('express');
const logger = require('./logger');
const { Pool } = require('pg');
const metrics = require('./metrics');
const { register } = require('prom-client');

const PORT = process.env.PORT || 8080;

const pool = new Pool({
  host: process.env.PGHOST,
  port: process.env.PGPORT || 5432,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE,
  max: 2,
  idleTimeoutMillis: 30000
});

const app = express();
app.use(express.json());
app.use(metrics.middleware);

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.get('/ready', async (req, res) => {
  try {
    const client = await pool.connect();
    client.release();
    res.status(200).json({ ready: true });
  } catch (err) {
    logger.error({ err }, 'readiness check failed');
    res.status(503).json({ ready: false, error: err.message });
  }
});

app.get('/orders', (req, res) => {
  const orders = [
    { id: 1, item: 'widget', qty: 4, status: 'shipped' },
    { id: 2, item: 'gadget', qty: 2, status: 'processing' }
  ];
  res.json({ count: orders.length, orders });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.use((err, req, res, next) => {
  logger.error({ err }, 'Unhandled error');
  res.status(500).json({ error: 'internal_error' });
});

const server = app.listen(PORT, () => {
  logger.info({ port: PORT }, 'App started');
});

const shutdown = async () => {
  logger.info('Shutting down');
  server.close(async () => {
    try { await pool.end(); } catch (e) { logger.warn(e); }
    process.exit(0);
  });
  setTimeout(() => { logger.error('Forcing shutdown'); process.exit(1); }, 10000);
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
