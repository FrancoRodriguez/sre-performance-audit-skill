import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },  // Ramp-up to 50 concurrent users
    { duration: '1m', target: 100 },  // Peak traffic test: 100 concurrent users
    { duration: '30s', target: 0 },   // Ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<300'], // P95 latency below 300ms
    http_req_failed: ['rate<0.01'],    // Failure rate under 1%
  },
};

export default function () {
  const BASE_URL = __ENV.TARGET_URL || 'https://example.com';
  const res = http.get(`${BASE_URL}/`);
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(1);
}
