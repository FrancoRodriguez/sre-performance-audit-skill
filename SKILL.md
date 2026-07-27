---
name: sre-performance-audit
description: SRE guidelines and performance audit runbook for high-throughput Ruby on Rails applications (PostgreSQL, Redis, Puma, Sidekiq/ActiveJob).
---

# SRE & Performance Audit Guidelines

This skill provides technical guidelines, diagnostic SQL runbooks, performance optimization queries, and an SRE observability matrix to maintain high throughput, low latency, and high availability in Ruby on Rails applications.

---

## 1. Web Server (Puma) & Concurrency Tuning

### Configuration Rules
- **Threads per Worker:** Keep `RAILS_MAX_THREADS` (default 3-5 in `config/puma.rb`) to balance throughput against CRuby's Global VM Lock (GVL).
- **Cluster Workers:** Configure 1 Puma worker process per physical/virtual vCPU available in production.
- **Memory Allocator (`jemalloc`):** In production Linux containers, preload `jemalloc` (`LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2`) to prevent memory fragmentation and reduce RSS RAM consumption by up to 30%.
- **Single-Line Logging:** Use `gem "lograge"` to emit structured single-line JSON logs per HTTP request.

---

## 2. Database (PostgreSQL) & Connection Pools

### Connection Pool Sizing
- **Pool Sizing Rule:** The `pool` parameter in `config/database.yml` MUST be **greater than or equal to** `RAILS_MAX_THREADS` per worker.
- **Total Connections Formula:**
  $$\text{Total DB Connections} = (\text{Puma Workers} \times \text{RAILS\_MAX\_THREADS}) + \text{Background Worker Connections}$$
- If total connections exceed 100 on a single PostgreSQL instance, deploy **PgBouncer** in `transaction` mode.

### PostgreSQL Diagnostic SQL Runbook

#### 1. Top 5 Slow Queries (`pg_stat_statements`)
```sql
SELECT 
    calls,
    round(total_exec_time::numeric, 2) AS total_time_ms,
    round(mean_exec_time::numeric, 2) AS avg_time_ms,
    round((100.0 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS percentage,
    query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 5;
```

#### 2. Table Sequential Scans & Index Usage (`pg_stat_user_tables`)
```sql
SELECT 
    relname AS table_name,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    round(100.0 * idx_scan / nullif(seq_scan + idx_scan, 0), 2) AS idx_use_pct
FROM pg_stat_user_tables
WHERE seq_scan > 0 OR idx_scan > 0
ORDER BY round(100.0 * idx_scan / nullif(seq_scan + idx_scan, 0), 2) ASC NULLS FIRST, seq_scan DESC
LIMIT 15;
```

#### 3. Active Connection Pool Saturation (`pg_stat_activity`)
```sql
SELECT 
    COALESCE(state, 'unknown') AS state,
    count(*) AS count
FROM pg_stat_activity
GROUP BY state
ORDER BY count DESC;
```

---

## 3. Zero-Downtime Migration Pattern

When adding composite indexes to high-traffic tables in production, always use `disable_ddl_transaction!` and `algorithm: :concurrently`:

```ruby
class AddPerformanceCompositeIndexes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :teams, [:club_id, :active], algorithm: :concurrently, if_not_exists: true
    add_index :roster_entries, [:team_id, :season_id, :active], algorithm: :concurrently, if_not_exists: true
  end
end
```

---

## 4. Caching & Evaporation Policies

- **Cascading Invalidation (`touch: true`):** Associated child models MUST declare `belongs_to :parent, touch: true` to update `updated_at` timestamps automatically and invalidate fragment cache keys.
- **Redis LRU Policy:** Configure production Redis instances used for `ActiveSupport::Cache::RedisCacheStore` with `maxmemory-policy volatile-lru` to prevent Out-Of-Memory (`OOM`) crashes.

---

## 5. Observability & SRE Golden Signals

### Key Service Level Objectives (SLOs)
1. **HTTP P95 Latency:** $< 250\text{ ms}$ for HTML/Turbo Stream views; $< 100\text{ ms}$ for JSON/API responses.
2. **Error Rate (5xx):** $< 0.1\%$ of total requests.
3. **Apdex Target:** $> 0.95$ with tolerance threshold $T = 300\text{ ms}$.
4. **Background Queue Delay:** Job queue lag $< 2\text{ s}$.

### Critical Alerting Matrix

| Metric | Warning | Critical | Action Item |
| :--- | :--- | :--- | :--- |
| **HTTP P95 Latency** | $> 400\text{ ms}$ (5 min) | $> 1000\text{ ms}$ (2 min) | Scale Puma pods / Diagnose slow queries |
| **Error Rate (5xx)** | $> 0.5\%$ (5 min) | $> 2.0\%$ (1 min) | Page SRE on-call, inspect logs |
| **DB Pool Saturation** | $> 75\%$ | $> 90\%$ | Increase pool size / Deploy PgBouncer |
| **CPU Utilization** | $> 70\%$ sustained | $> 85\%$ (5 min) | Scale web instances horizontally |
| **Redis Memory** | $> 80\%$ assigned | $> 92\%$ assigned | Evict expired keys / Upgrade Redis plan |

---

## 6. k6 Load Testing Benchmark Script

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },  // Ramp-up to 50 users
    { duration: '1m', target: 100 },  // Peak traffic: 100 concurrent users
    { duration: '30s', target: 0 },   // Ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<300'], // 95% of requests under 300ms
    http_req_failed: ['rate<0.01'],    // Failure rate under 1%
  },
};

export default function () {
  const res = http.get('https://example.com/');
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
```
