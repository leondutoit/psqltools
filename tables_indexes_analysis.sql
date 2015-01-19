
-- useful queries for analyzing the database performance
-- gives some introspection into table and index usage
-- to list all views in the schame: => \dv dbanalysis.*

create schema if not exists dbanalysis;


-- vacuum and analyze stats
-- evidence on whether we need to readjust, for which tables, and why
drop view if exists dbanalysis.autovac_usage_view;
create view dbanalysis.autovac_usage_view as
select
    schemaname schem,
    relname rel,
    n_live_tup,
    n_dead_tup,
    case
        when n_live_tup != 0
            then round((n_dead_tup::numeric / n_live_tup), 2) * 100
        else 0.00
    end as perc_dead_tup,
    date(last_vacuum) l_vac,
    date(last_analyze) l_an,
    date(last_autovacuum) l_autovac,
    date(last_autoanalyze) l_autoan,
    extract(day from (now() - last_autoanalyze)) since_autoan,
    autovacuum_count autovac_c,
    autoanalyze_count autoan_c
from pg_stat_user_tables
order by n_live_tup desc;


-- seq or index scans per table?
drop view if exists dbanalysis.index_scans_per_table_view;
create view dbanalysis.index_scans_per_table_view as
select
    schemaname,
    relname,
    seq_scan,
    idx_scan,
    case
        when (idx_scan + seq_scan) != 0
            then round(idx_scan::numeric / (idx_scan + seq_scan), 2)
        else 0.00
    end as idx_scan_pct
from pg_stat_user_tables
order by idx_scan_pct desc;

-- how many tuples were processed by the idx and sec scans?
drop view if exists dbanalysis.tuples_processed_per_scan;
create view dbanalysis.tuples_processed_per_scan as
select
    relname,
    seq_tup_read,
    idx_tup_fetch,
    case
        when (idx_tup_fetch + seq_tup_read) != 0
            then round(idx_tup_fetch::numeric / (idx_tup_fetch + seq_tup_read), 2)
        else 0.00
    end as idx_tup_pct
from pg_stat_user_tables
order by idx_tup_pct desc;


-- how often is HOT being used?
drop view if exists dbanalysis.hot_usage_view;
create view dbanalysis.hot_usage_view as
select
    relname,
    n_tup_upd,
    n_tup_hot_upd,
    case
        when n_tup_upd != 0
            then (n_tup_hot_upd::numeric / n_tup_upd)
        else 0.00
    end as hot_pct
from pg_stat_user_tables
order by hot_pct desc;

-- insert/update/delete characteristics?
drop view if exists dbanalysis.ins_upd_del_characteristics_view;
create view dbanalysis.ins_upd_del_characteristics_view as
select
    relname,
    case
        when (n_tup_ins + n_tup_upd + n_tup_del) != 0
            then round(n_tup_ins::numeric / (n_tup_ins + n_tup_upd + n_tup_del), 2)
        else 0.00
    end as insert_pct,
    case
        when (n_tup_ins + n_tup_upd + n_tup_del) != 0
            then round(n_tup_upd::numeric / (n_tup_ins + n_tup_upd + n_tup_del), 2)
        else 0.00
    end as update_pct,
    case
        when (n_tup_ins + n_tup_upd + n_tup_del) != 0
            then round(n_tup_del::numeric / (n_tup_ins + n_tup_upd + n_tup_del), 2)
        else 0.00
    end as delete_pct
from pg_stat_user_tables
order by relname;

-- table IO: read from buffer cache or os cache / disk?
drop view if exists dbanalysis.table_io_view;
create view dbanalysis.table_io_view as
select
    relname,
    case
        when (heap_blks_hit + heap_blks_read) != 0
            then round(heap_blks_hit::numeric / (heap_blks_hit + heap_blks_read), 2)
        else 0.00
    end as hit_pct,
    heap_blks_hit,
    heap_blks_read
from pg_statio_user_tables
order by hit_pct desc;


-- table index IO: read from cache or disk?
drop view if exists dbanalysis.table_index_io_view;
create view dbanalysis.table_index_io_view as
select
    relname,
    case
        when (idx_blks_hit + idx_blks_read) != 0
            then round(idx_blks_hit::numeric / (idx_blks_hit + idx_blks_read), 2)
        else 0.00
    end as hit_pct,
    idx_blks_hit,
    idx_blks_read
from pg_statio_user_tables
order by hit_pct desc;


-- index stats; average rows returned
drop view if exists dbanalysis.index_rows_reutrned_view;
create view dbanalysis.index_rows_reutrned_view as
select
    indexrelname,
    case
        when idx_scan != 0
            then round(idx_tup_read::numeric / idx_scan, 2)
        else 0.0
    end as avg_tuples,
    idx_scan,
    idx_tup_read
from pg_stat_user_indexes
order by avg_tuples desc;


drop view if exists dbanalysis.index_usage_summary_view;
drop view if exists dbanalysis.index_usage_view cascade;
drop view if exists dbanalysis.index_io_view cascade;

-- which indexes can be removed due to low usage?
create view dbanalysis.index_usage_view as
select
    schemaname,
    relname,
    indexrelname,
    idx_scan,
    pg_size_pretty(pg_relation_size(i.indexrelid)) index_size
from pg_stat_user_indexes i
join pg_index using (indexrelid)
where indisunique is false
order by idx_scan desc;

-- index IO
create view dbanalysis.index_io_view as
select
    indexrelname,
    case
        when (idx_blks_hit + idx_blks_read) != 0
            then round(idx_blks_hit::numeric / (idx_blks_hit + idx_blks_read) , 2)
            else 0.00
    end as hit_pct,
    idx_blks_hit,
    idx_blks_read
from pg_statio_user_indexes
order by hit_pct desc;


-- combine index usage and io
create view dbanalysis.index_usage_summary_view as
select
    io.indexrelname,
    io.hit_pct,
    usage.index_size,
    usage.idx_scan,
    io.idx_blks_hit,
    io.idx_blks_read
from dbanalysis.index_io_view io
join dbanalysis.index_usage_view usage using (indexrelname)
order by hit_pct desc;


-- what is currently running?
drop view if exists dbanalysis.currently_queries_view;
create view dbanalysis.currently_queries_view as
select
    pid,
    waiting,
    state,
    current_timestamp - least(query_start, xact_start) runtime,
    substr(query, 1, 110) query
from pg_stat_activity
where not pid = pg_backend_pid()
order by runtime desc;

-- to kill a long query: select pg_terminate_backend(pid);

