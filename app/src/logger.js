const pino = require('pino');

const opts = { level: process.env.LOG_LEVEL || 'info' };
module.exports = pino(opts);
