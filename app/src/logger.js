'use strict';
/**
 * Structured JSON logger using Pino.
 *
 * Why Pino?
 *   - Outputs newline-delimited JSON — parseable by CloudWatch Logs Insights,
 *     Grafana Loki, and any log aggregator without plugins.
 *   - Fastest Node.js logger in benchmarks (async transport, minimal overhead).
 *   - LOG_LEVEL env var controls verbosity:
 *       debug  — verbose, use during local development
 *       info   — default, one line per meaningful event
 *       warn   — only warnings and errors
 *       error  — errors only
 */
const pino = require('pino');

module.exports = pino({
  level: process.env.LOG_LEVEL || 'info',
});
