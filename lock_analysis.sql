
create schema if not exists dbanalysis;

-- basic current lock overview
create view dbanalysis.current_locks_basic_view as
select
    l.pid,
    l.locktype,
    l.relation,
    u.relid,
    u.relname,
    l.mode,
    l.granted
from pg_locks l join pg_stat_user_tables u
on l.relation = u.relid;

-- ps -o pid,sess,cmd afx | grep -A20 "cron$"


