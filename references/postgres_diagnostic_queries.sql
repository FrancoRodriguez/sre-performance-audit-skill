-- PostgreSQL Diagnostic & Performance Audit Queries
-- Use these queries to audit table scans, index usage, slow queries, and active connection pools.

-- 1. Table Sequential Scans & Index Usage Percentage
-- Shows tables ordered by lowest index usage percentage (most critical first)
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
LIMIT 20;

-- 2. Top 10 Slowest Queries (requires pg_stat_statements extension)
SELECT 
    calls,
    round(total_exec_time::numeric, 2) AS total_time_ms,
    round(mean_exec_time::numeric, 2) AS avg_time_ms,
    round((100.0 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS percentage,
    query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- 3. Active Connection Breakdown by State
SELECT 
    COALESCE(state, 'unknown') AS state,
    count(*) AS count
FROM pg_stat_activity
GROUP BY state
ORDER BY count DESC;

-- 4. Table Disk Sizes
SELECT 
    relname AS table_name,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    pg_size_pretty(pg_relation_size(relid)) AS data_size,
    pg_size_pretty(pg_indexes_size(relid)) AS index_size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 15;
