'use strict';
const { app, pool } = require('./index');
const logger = require('./logger');

const PORT = process.env.PORT || 8080;

const server = app.listen(PORT, () => {
  logger.info({ port: PORT }, 'HTTP server started');
});

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

  setTimeout(() => {
    logger.error('Graceful shutdown timeout — forcing exit');
    process.exit(1);
  }, 10_000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));
