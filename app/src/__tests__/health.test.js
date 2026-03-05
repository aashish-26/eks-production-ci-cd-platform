'use strict';
/**
 * Basic route tests for the Express application.
 *
 * Uses supertest to make in-process HTTP calls without starting a
 * real server. The `pg` module is mocked so these tests run without
 * a live PostgreSQL instance (CI has no DB sidecar).
 *
 * Run with: npm test
 */
const request = require('supertest');

// ----- Mock the pg module BEFORE requiring the app -----
// The Pool constructor and connect() must be in place before index.js
// is loaded, otherwise the real pg driver tries to connect.
jest.mock('pg', () => {
  const mockRelease = jest.fn();
  const mockConnect = jest.fn().mockResolvedValue({ release: mockRelease });
  const MockPool = jest.fn().mockImplementation(() => ({
    connect: mockConnect,
    end:     jest.fn().mockResolvedValue(undefined),
    query:   jest.fn(),
  }));
  return { Pool: MockPool };
});

let app;

beforeAll(() => {
  // Require after the mock is registered
  ({ app } = require('../index'));
});

afterAll(async () => {
  // Let any open handles drain
  await new Promise(resolve => setTimeout(resolve, 200));
});

// -------------------------------------------------------

describe('GET /health', () => {
  test('returns 200 and { status: "ok" }', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });
});

describe('GET /orders', () => {
  test('returns 200 with an orders array', async () => {
    const res = await request(app).get('/orders');
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body.orders)).toBe(true);
    expect(res.body.orders.length).toBeGreaterThan(0);
    expect(res.body.count).toBe(res.body.orders.length);
  });
});

describe('GET /ready', () => {
  test('returns 200 when DB mock resolves', async () => {
    const res = await request(app).get('/ready');
    expect(res.statusCode).toBe(200);
    expect(res.body.ready).toBe(true);
  });

  test('returns 503 when DB pool throws', async () => {
    // Override the mock to simulate a DB failure for this test only
    const { Pool } = require('pg');
    Pool.mockImplementationOnce(() => ({
      connect: jest.fn().mockRejectedValue(new Error('connection refused')),
      end:     jest.fn(),
    }));
    // Re-require the app to pick up the new mock instance
    jest.resetModules();
    jest.mock('pg', () => {
      const MockPool = jest.fn().mockImplementation(() => ({
        connect: jest.fn().mockRejectedValue(new Error('connection refused')),
        end: jest.fn(),
      }));
      return { Pool: MockPool };
    });
    const { app: freshApp } = require('../index');
    const res = await request(freshApp).get('/ready');
    expect(res.statusCode).toBe(503);
    expect(res.body.ready).toBe(false);
  });
});
