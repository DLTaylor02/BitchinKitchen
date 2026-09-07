-- Read-only: report the privileges that prevent using this connection as the app.
-- Normal ownership of the application's database is allowed.
SELECT format('%I: %s%s', rolname,
    CASE WHEN rolname = current_user THEN 'login role; ' ELSE 'reachable role membership; ' END,
    concat_ws(', ',
        CASE WHEN rolsuper THEN 'SUPERUSER' END,
        CASE WHEN rolcreatedb THEN 'CREATEDB' END,
        CASE WHEN rolcreaterole THEN 'CREATEROLE' END,
        CASE WHEN rolreplication THEN 'REPLICATION' END,
        CASE WHEN rolbypassrls THEN 'BYPASSRLS' END,
        CASE WHEN left(rolname, 3) = 'pg_' AND rolname <> 'pg_database_owner'
             THEN 'server-wide predefined role' END))
FROM pg_catalog.pg_roles
WHERE (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls
       OR (left(rolname, 3) = 'pg_' AND rolname <> 'pg_database_owner'))
  AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER')
ORDER BY (rolname = current_user) DESC, rolname;
