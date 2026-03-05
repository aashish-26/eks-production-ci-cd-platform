'use strict';
/**
 * Prometheus instrumentation middleware.
 *
 * Registers an HTTP request duration histogram and attaches an
 * Express middleware that records the duration of every request.
 *
 * Metrics exposed:
 *   http_request_duration_seconds{method, route, code}
 *     — buckets tuned for typical web APIs (5 ms to 5 s)
 *
 * Scraped by Prometheus via GET /metrics (registered in index.js).
 * In Grafana, use the metric to build:
 *   - Request rate:  rate(http_request_duration_seconds_count[5m])
 *   - p99 latency:   histogram_quantile(0.99, rate(..._bucket[5m]))
 *   - Error rate:    rate(..._count{code=~"5.."}[5m])
 */
const client = require('prom-client');

// Enable default Node.js metrics (event loop lag, GC pause, memory usage, etc.)
client.collectDefaultMetrics();

const httpRequestDurationSeconds = new client.Histogram({
  name:       'http_request_duration_seconds',
  help:       'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'code'],
  // Buckets in seconds: 5ms, 10ms, 50ms, 100ms, 500ms, 1s, 2s, 5s
  buckets:    [0.005, 0.01, 0.05, 0.1, 0.5, 1, 2, 5],
});

/**
 * Express middleware — starts a timer before the route handler runs,
 * records the duration when the response is finished.
 */
module.exports.middleware = (req, res, next) => {
  const end = httpRequestDurationSeconds.startTimer();
  res.on('finish', () => {
    // Use the matched route path (e.g. "/orders") not the full URL
    const route = req.route?.path ?? req.path;
    end({ method: req.method, route, code: res.statusCode });
  });
  next();
};

module.exports.register = client.register;
