/* WARNING: executed with a non-superuser role, the query inspect only tables you are granted to read.
* This query is compatible with PostgreSQL 7.4 to 8.1
*/
SELECT current_database(), schemaname, tblname, bs*tblpages AS real_size,
  (tblpages-est_num_pages)*bs AS bloat_size, tblpages, is_na,
  CASE WHEN tblpages - est_num_pages > 0
    THEN 100 * (tblpages - est_num_pages)/tblpages::float
    ELSE 0
  END AS bloat_ratio
FROM (
  SELECT
    ceil( reltuples / ( (bs-page_hdr)/tpl_size ) ) + ceil( toasttuples / 4 ) AS est_num_pages, tblpages,
    bs, tblid, schemaname, tblname, heappages, toastpages, is_na
  FROM (
    SELECT
      ( 4 + tpl_hdr_size + tpl_data_size + (2*ma)
        - CASE WHEN tpl_hdr_size%ma = 0 THEN ma ELSE tpl_hdr_size%ma END
        - CASE WHEN ceil(tpl_data_size)::int%ma = 0 THEN ma ELSE ceil(tpl_data_size)::int%ma END
      ) AS tpl_size, bs - page_hdr AS size_per_block, (heappages + toastpages) AS tblpages, heappages,
      toastpages, reltuples, toasttuples, bs, page_hdr, tblid, schemaname, tblname, is_na
    FROM (
      SELECT
        tbl.oid AS tblid, ns.nspname AS schemaname, tbl.relname AS tblname, tbl.reltuples,
        tbl.relpages AS heappages, coalesce(toast.relpages, 0) AS toastpages,
        coalesce(toast.reltuples, 0) AS toasttuples,
        CASE WHEN cluster_version.v > 7
          THEN current_setting('block_size')::numeric
          ELSE 8192::numeric
        END AS bs,
        CASE WHEN version()~'mingw32' OR version()~'64-bit|x86_64|ppc64|ia64|amd64' THEN 8 ELSE 4 END AS ma,
        CASE WHEN cluster_version.v > 7
          THEN 24
          ELSE 20
        END AS page_hdr,
        CASE WHEN cluster_version.v > 7 THEN 27 ELSE 23 END
          + CASE WHEN MAX(coalesce(null_frac,0)) > 0 THEN ( 7 + count(*) ) / 8 ELSE 0::int END
          + CASE WHEN tbl.relhasoids THEN 4 ELSE 0 END AS tpl_hdr_size,
        sum( (1-coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024) ) AS tpl_data_size,
        max( CASE WHEN att.atttypid = 'pg_catalog.name'::regtype THEN 1 ELSE 0 END ) > 0
          OR count(att.attname) <> count(s.attname) AS is_na
      FROM pg_attribute att
        JOIN pg_class tbl ON att.attrelid = tbl.oid
        JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
        LEFT JOIN pg_stats s ON s.schemaname=ns.nspname
          AND s.tablename = tbl.relname
          AND s.attname=att.attname
        LEFT JOIN pg_class toast ON tbl.reltoastrelid = toast.oid,
        ( SELECT substring(current_setting('server_version') FROM '#"[0-9]+#"%' FOR '#')::integer ) AS cluster_version(v)
      WHERE att.attnum > 0 AND NOT att.attisdropped
        AND tbl.relkind = 'r'
      GROUP BY 1,2,3,4,5,6,7,8,9,10, cluster_version.v, tbl.relhasoids
      ORDER BY 2,3
    ) as s
  ) as s2
) AS s3
-- WHERE NOT is_na;
