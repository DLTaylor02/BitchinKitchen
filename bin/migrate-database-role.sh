#!/usr/bin/env bash
# Sourced by setup.sh only when --migrate-database-role is explicitly requested.
migrate_database_role() {
    local target=bitchin_kitchen_app state_dir=/var/lib/bitchin-kitchen/setup
    local role_exists backup_dir migration_password
    [[ "$DB_HOST" == 127.0.0.1 && "$DB_PORT" == 5432 && "$DB_NAME" == bitchin_kitchen ]] || die "Automatic role migration supports only the local bitchin_kitchen database on port 5432"
    [[ "$RECOGNIZED_DEPLOYMENT" == 1 && "$CONFIG_ENV_FILE" == "$APP_DIR/.env" ]] || die "Role migration requires a recognized deployed installation and its .env"
    if [[ "$DB_USER" == "$target" ]]; then
        printf 'Application already uses %s; continuing normal setup.\n' "$target"
        return
    fi
    [[ "$DB_USER" == postgres ]] || die "Role migration supports the existing postgres login only"
    [[ ! -L /var/lib/bitchin-kitchen && ! -L "$state_dir" ]] || die "Unexpected migration state directory"
    install -d -o root -g root -m 0700 "$state_dir"
    MIGRATION_STATE="$state_dir/database-role-password"
    [[ ! -L "$MIGRATION_STATE" ]] || die "Unexpected migration state symlink"
    role_exists="$(runuser -u postgres -- psql -X -p "$DB_PORT" -v ON_ERROR_STOP=1 -Atc "SELECT 1 FROM pg_roles WHERE rolname='$target'")"
    if [[ -f "$MIGRATION_STATE" ]]; then
        [[ "$(stat -c '%u:%a' "$MIGRATION_STATE")" == 0:600 ]] || die "Migration recovery file must be owned by root with mode 600"
        migration_password="$(cat "$MIGRATION_STATE")"
        [[ "$migration_password" =~ ^[a-f0-9]{48}$ ]] || die "Invalid migration recovery file"
    else
        [[ "$role_exists" != 1 ]] || die "Role '$target' already exists without migration recovery state; it was not changed"
        migration_password="$(openssl rand -hex 24)"
        (umask 077; printf '%s\n' "$migration_password" > "$MIGRATION_STATE")
    fi

    # Preserve both the data and the old connection settings before changing ownership.
    [[ ! -L /var/backups/bitchin-kitchen ]] || die "Unexpected backup directory symlink"
    install -d -o root -g root -m 0700 /var/backups/bitchin-kitchen
    backup_dir="$(mktemp -d /var/backups/bitchin-kitchen/database-role.XXXXXX)"
    runuser -u postgres -- pg_dump -p "$DB_PORT" -Fc "$DB_NAME" > "$backup_dir/database.dump"
    install -m 0600 "$CONFIG_ENV_FILE" "$backup_dir/env.before"
    printf 'Database and configuration backup: %s\n' "$backup_dir"
    runuser -u postgres -- psql -X -p "$DB_PORT" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
        -v app_role="$target" -v app_password="$migration_password" \
        -f "$SOURCE_DIR/config/migrate-database-role.sql" || die "Role migration failed. Its SQL transaction was rolled back; recovery credentials are retained for a retry"
    PGPASSWORD="$migration_password" psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$target" -d "$DB_NAME" \
        -v ON_ERROR_STOP=1 -Atc 'SELECT count(*) FROM public.users' >/dev/null || die "New role could not connect. Existing .env is unchanged; rerun migration after resolving authentication"
    DB_USER="$target"
    DB_PASSWORD="$migration_password"
    printf 'Using dedicated role %s for the existing database.\n' "$DB_USER"
}
