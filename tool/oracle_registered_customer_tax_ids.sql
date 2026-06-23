whenever sqlerror exit sql.sqlcode
set heading off feedback off pagesize 0 verify off echo off trimspool on linesize 32767

SELECT DISTINCT
    REGEXP_REPLACE(pc.cgcent, '[^0-9]')
FROM pcclient pc
WHERE LENGTH(REGEXP_REPLACE(pc.cgcent, '[^0-9]')) IN (11, 14)
  AND SUBSTR(REGEXP_REPLACE(pc.cgcent, '[^0-9]'), 1, 1) = '&1';

exit
