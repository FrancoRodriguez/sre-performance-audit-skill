# ⚡ SRE Performance Audit Skill

> **An Autonomous AI Agent Skill & SRE Runbook for Auditing, Diagnosing, and Optimizing High-Performance Web Applications (Ruby on Rails, PostgreSQL, Redis, Puma).**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Antigravity AI](https://img.shields.io/badge/AI%20Platform-Google%20Antigravity-purple.svg)](https://github.com/google-gemini)
[![Stack: Ruby on Rails 7+](https://img.shields.io/badge/Framework-Ruby%20on%20Rails%207+-red.svg)](https://rubyonrails.org/)

---

## 📌 Overview

This repository contains a production-tested **AI Agent Skill** (`SKILL.md`) designed to equip autonomous coding assistants (such as **Google Antigravity**, Cursor, or Claude Code) and SRE teams with exact guidelines, SQL diagnostic runbooks, Puma/PostgreSQL concurrency tuning rules, and k6 benchmark scripts.

---

## 🚀 Key Capabilities

- **PostgreSQL Index & Query Audit:** SQL queries to detect slow queries via `pg_stat_statements`, measure table scan rates via `pg_stat_user_tables`, and monitor active connection saturation via `pg_stat_activity`.
- **Zero-Downtime Migration Patterns:** Best practices for creating composite indexes using `disable_ddl_transaction!` and `algorithm: :concurrently`.
- **Puma & Concurrency Sizing:** Mathematical formulas to align `RAILS_MAX_THREADS`, Puma cluster workers, and ActiveRecord DB connection pools.
- **Memory & Resource Optimization:** `jemalloc` preloading rules to reduce Ruby MRI memory fragmentation by up to 30%.
- **SRE Golden Signals & Alerting Matrix:** Explicit threshold rules for P95 latency, 5xx error rates, DB pool exhaustion, and Redis memory evaporation policies.
- **k6 Load Testing Benchmarks:** Pre-configured JavaScript load testing scenarios for peak traffic events.

---

## 📦 Installation & Usage

### 1. In Google Antigravity / Agentic Workspaces
Copy the `sre-performance-audit` directory into your project's agent skills directory:

```bash
mkdir -p .agents/skills/sre_performance_audit
cp SKILL.md .agents/skills/sre_performance_audit/SKILL.md
```

### 2. Manual SRE Runbook Usage
You can execute the SQL queries directly in `references/postgres_diagnostic_queries.sql` against your production or staging database via `psql` or `rails console`.

---

## 📁 Repository Structure

```
.
├── SKILL.md                              # The core AI Agent Skill specification
├── README.md                             # Project documentation
├── LICENSE                               # MIT License
└── references/
    ├── postgres_diagnostic_queries.sql   # Ready-to-run PostgreSQL audit queries
    └── k6_load_test.js                   # Load testing scenario for k6
```

---

## 📄 License

Distributed under the [MIT License](LICENSE). Created by [Franco Rodríguez](https://github.com/FrancoRodriguez).
