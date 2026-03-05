'use strict';
/**
 * HTTP server entry point.
 *
 * Imports the configured Express app and binds it to a port.
 * Kept separate from index.js so tests can import the app
 * without starting the server and binding to a real port.
 *
 * Handles SIGTERM and SIGINT for graceful Kubernetes shutdown:
 *   1. Stop accepting new connections.
 *   2. Wait for in-flight requests to finish (server.close).
 *   3. Close the DB pool.
 *   4. Exit cleanly so Kubernetes marks the pod as Terminated.
 */
const { app, pool } = require('./index');
const logger = require('./logger');

const PORT = process.env.PORT || 8080;

const server = app.listen(PORT, () => {
  logger.info({ port: PORT }, 'HTTP server started');
});

// --------------------------------------------------------
// Graceful shutdown
//
// Kubernetes sends SIGTERM when it wants to stop the pod.
// We stop accepting connections and wait for existing ones
// to finish before exiting. The 10 s timeout is a safety net
// in case requests hang — Kubernetes default terminationGracePeriod
// is 30 s, so 10 s gives the app time to drain cleanly.
// --------------------------------------------------------
const shutdown = async (signal) => {
  logger.info({ signal }, `${signal} received — starting graceful shutdown`);

  server.close(async () => {
    logger.info('HTTP server closed');
    try {
      await pool.end();
      logger.info('PostgreSQL pool closed');
    } catch (e) {
      logger.warn({ err: e }, 'Error closing DB pool');
    }
    process.exit(0);
  });

  // Force-exit if close() takes too long
  setTimeout(() => {
    logger.error('Graceful shutdown timeout — forcing exit');
    process.exit(1);
  }, 10_000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));
