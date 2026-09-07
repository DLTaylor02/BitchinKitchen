-- Explicit opt-in migration for the existing local installation.
-- Never reassign all objects owned by postgres, change its privileges, or change
-- database/schema ownership: this list bounds the objects we may transfer.
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL search_path = pg_catalog;
SELECT set_config('kitchen.migration_role', :'app_role', true);
CREATE TEMP TABLE kitchen_app_tables(name text PRIMARY KEY);
INSERT INTO kitchen_app_tables VALUES
    ('settings'), ('users'), ('login_throttles'), ('cuisines'), ('tags'),
    ('recipes'), ('recipe_tags'), ('recipe_photos'), ('user_favorites');
DO $$
DECLARE
    target text := current_setting('kitchen.migration_role');
    marker text := 'Bitchin Kitchen role migration for database ' || current_database();
BEGIN
    IF current_database() <> 'bitchin_kitchen' OR current_user <> 'postgres' OR target <> 'bitchin_kitchen_app' THEN
        RAISE EXCEPTION 'Unexpected migration database or administrator';
    END IF;
    IF to_regclass('public.settings') IS NULL OR to_regclass('public.users') IS NULL
       OR to_regclass('public.recipes') IS NULL OR to_regclass('public.recipe_photos') IS NULL THEN
        RAISE EXCEPTION 'Existing application tables were not found';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.settings WHERE key = 'installed_at') THEN
        RAISE EXCEPTION 'Database is not an initialized Bitchin Kitchen installation';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_temp.kitchen_app_tables t ON t.name = c.relname
        WHERE n.nspname = 'public' AND (c.relkind <> 'r' OR pg_get_userbyid(c.relowner) NOT IN ('postgres', target))
    ) THEN
        RAISE EXCEPTION 'An application table has an unexpected type or owner';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = target) AND NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = target
        AND shobj_description(oid, 'pg_authid') = marker
        AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
        AND NOT EXISTS (SELECT 1 FROM pg_auth_members m WHERE m.member = pg_roles.oid)
    ) THEN
        RAISE EXCEPTION 'Target role already exists and is not a restricted role from this migration';
    END IF;
END $$;
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L', :'app_role', :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_role') \gexec
SELECT format('COMMENT ON ROLE %I IS %L', :'app_role', 'Bitchin Kitchen role migration for database ' || current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'app_role') \gexec
SELECT format('GRANT USAGE, CREATE ON SCHEMA public TO %I', :'app_role') \gexec
SELECT format('ALTER TABLE public.%I OWNER TO %I', c.relname, :'app_role')
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_temp.kitchen_app_tables t ON t.name = c.relname
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname \gexec
-- ALTER TABLE OWNER also transfers its indexes and owned serial sequences.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_class seq
        JOIN pg_depend d ON d.classid = 'pg_class'::regclass AND d.objid = seq.oid
            AND d.refclassid = 'pg_class'::regclass AND d.deptype IN ('a', 'i')
        JOIN pg_class t ON t.oid = d.refobjid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_temp.kitchen_app_tables app ON app.name = t.relname
        WHERE seq.relkind = 'S' AND n.nspname = 'public'
          AND pg_get_userbyid(seq.relowner) <> current_setting('kitchen.migration_role')
    ) THEN
        RAISE EXCEPTION 'An application sequence did not transfer to the dedicated role';
    END IF;
END $$;
COMMIT;
