'use strict';
const client = require('prom-client');

client.collectDefaultMetrics();

const httpRequestDurationSeconds = new client.Histogram({
  name:       'http_request_duration_seconds',
  help:       'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'code'],
  buckets:    [0.005, 0.01, 0.05, 0.1, 0.5, 1, 2, 5],
});

module.exports.middleware = (req, res, next) => {
  const end = httpRequestDurationSeconds.startTimer();
  res.on('finish', () => {
    const route = req.route?.path ?? req.path;
    end({ method: req.method, route, code: res.statusCode });
  });
  next();
};

module.exports.register = client.register;
