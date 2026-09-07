#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_PORT=7373
PORT="${1:-}"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/var/www/bitchinkitchen"
SITE_NAME="bitchin-kitchen"
SYSTEM_USER="$SITE_NAME"
MARKER="$APP_DIR/.bitchin-kitchen-install"
PHP_MEMORY_MB="${PHP_MEMORY_MB:-256}"
PHP_MAX_CHILDREN="${PHP_MAX_CHILDREN:-4}"
PHP_REQUEST_SECONDS="${PHP_REQUEST_SECONDS:-60}"
DB_PROVISION="${DB_PROVISION:-auto}"
umask 027
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run this setup as root: sudo ./setup.sh [port]"
[[ -f /etc/debian_version ]] || die "This installer supports Debian-based systems only"
[[ ! -L "$APP_DIR" ]] || die "Deployment directory must not be a symlink"
APP_DIR="$(realpath -m "$APP_DIR")"
[[ "$APP_DIR" == /var/www/bitchinkitchen ]] || die "Unexpected resolved deployment directory"
case "$SOURCE_DIR/" in "$APP_DIR/"*) die "Run setup from a separate source checkout" ;; esac
[[ -f "$SOURCE_DIR/composer.json" && -f "$SOURCE_DIR/public/index.php" ]] || die "Incomplete source checkout"
for tree in "$SOURCE_DIR" "$APP_DIR"; do
    [[ -d "$tree" ]] || continue
    [[ -z "$(find "$tree" -path "$tree/.git" -prune -o -type l -print -quit)" ]] || die "Symlinks inside source or deployment are not supported"
done
if [[ -d "$APP_DIR" && -n "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    [[ -f "$MARKER" && ! -L "$MARKER" && "$(cat "$MARKER")" == "$SITE_NAME" ]] || die "Destination is not a recognized Bitchin Kitchen deployment"
fi
for value in "$PHP_MEMORY_MB" "$PHP_MAX_CHILDREN" "$PHP_REQUEST_SECONDS"; do
    [[ "$value" =~ ^[1-9][0-9]{0,5}$ ]] || die "PHP limits must be positive integers (at most six digits)"
done
SITE_FILE="/etc/nginx/sites-available/$SITE_NAME"
if [[ -f "$SITE_FILE" ]]; then
    [[ -f "$MARKER" ]] || die "Nginx site name is already in use"
    existing_port="$(sed -nE 's/^[[:space:]]*listen[[:space:]]+(0\.0\.0\.0:)?([0-9]+);.*/\2/p' "$SITE_FILE" | head -n 1)"
    DEFAULT_PORT="${existing_port:-$DEFAULT_PORT}"
fi
if [[ -z "$PORT" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Application port [$DEFAULT_PORT]: " PORT
    fi
    PORT="${PORT:-$DEFAULT_PORT}"
fi
[[ "$PORT" =~ ^[1-9][0-9]{0,4}$ ]] && (( PORT <= 65535 )) || die "Port must be between 1 and 65535, without leading zeros"
# Inspect the effective configuration, including conf.d and included site files.
if command -v nginx >/dev/null 2>&1; then
    nginx -t
    conflicts="$(nginx -T 2>/dev/null | awk -v own="$SITE_FILE:" -v enabled="/etc/nginx/sites-enabled/$SITE_NAME:" -v port="$PORT" '
        /^# configuration file / {file=$4}
        /^[[:space:]]*listen[[:space:]]/ {
            address=$2; sub(/;.*/, "", address); sub(/^.*:/, "", address)
            if (address == port && file != own && file != enabled) print file
        }')"
    [[ -z "$conflicts" ]] || die "Port $PORT is configured by another Nginx site: $conflicts"
fi
command -v ss >/dev/null 2>&1 || die "Install iproute2 before setup so listener conflicts can be checked"
if ss -H -ltn | awk -v port=":$PORT" '$4 ~ (port "$") {found=1} END {exit !found}'; then
    [[ -f "$MARKER" && "${existing_port:-}" == "$PORT" ]] || die "Port $PORT is already in use"
    ss -H -ltnp "sport = :$PORT" | grep -q '"nginx"' || die "Port $PORT is not owned by Nginx"
fi
if [[ -f "$APP_DIR/.env" ]]; then
    CONFIG_ENV_FILE="$APP_DIR/.env"
elif [[ -f "$SOURCE_DIR/.env" ]]; then
    CONFIG_ENV_FILE="$SOURCE_DIR/.env"
else
    CONFIG_ENV_FILE="$SOURCE_DIR/.env.example"
fi
read_env() {
    local key="$1" line value
    [[ -f "$CONFIG_ENV_FILE" ]] || return 0
    line="$(grep -m1 -E "^${key}=" "$CONFIG_ENV_FILE" 2>/dev/null || true)"
    value="${line#*=}"
    if ((${#value} >= 2)) && [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then value="${value:1:${#value}-2}"; fi
    if ((${#value} >= 2)) && [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then value="${value:1:${#value}-2}"; fi
    printf '%s' "$value"
}
DB_NAME="${DB_NAME:-$(read_env DB_NAME)}"; DB_NAME="${DB_NAME:-bitchin_kitchen}"
DB_USER="${DB_USER:-$(read_env DB_USER)}"; DB_USER="${DB_USER:-bitchin}"
DB_HOST="${DB_HOST:-$(read_env DB_HOST)}"; DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-$(read_env DB_PORT)}"; DB_PORT="${DB_PORT:-5432}"
DB_PASSWORD="${DB_PASSWORD:-$(read_env DB_PASSWORD)}"
UPLOAD_MAX_FILE_MB="${UPLOAD_MAX_FILE_MB:-$(read_env UPLOAD_MAX_FILE_MB)}"; UPLOAD_MAX_FILE_MB="${UPLOAD_MAX_FILE_MB:-8}"
UPLOAD_MAX_REQUEST_MB="${UPLOAD_MAX_REQUEST_MB:-$(read_env UPLOAD_MAX_REQUEST_MB)}"; UPLOAD_MAX_REQUEST_MB="${UPLOAD_MAX_REQUEST_MB:-32}"
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
SERVER_IP="${SERVER_IP:-localhost}"
PUBLIC_URL="${APP_URL:-$(read_env APP_URL)}"; PUBLIC_URL="${PUBLIC_URL:-http://$SERVER_IP:$PORT}"

[[ "$DB_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die "DB_USER must be a valid PostgreSQL identifier"
[[ "$DB_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die "DB_NAME must be a valid PostgreSQL identifier"
[[ "$UPLOAD_MAX_FILE_MB" =~ ^[1-9][0-9]{0,5}$ ]] || die "UPLOAD_MAX_FILE_MB must be a positive integer without leading zeros"
[[ "$UPLOAD_MAX_REQUEST_MB" =~ ^[1-9][0-9]{0,5}$ ]] && (( UPLOAD_MAX_REQUEST_MB >= UPLOAD_MAX_FILE_MB )) || die "UPLOAD_MAX_REQUEST_MB must be at least UPLOAD_MAX_FILE_MB"
[[ -f /etc/debian_version ]] || die "This installer supports Debian-based systems only"
command -v apt-get >/dev/null 2>&1 || die "apt-get was not found"
[[ "$DB_PORT" =~ ^[1-9][0-9]{0,4}$ ]] && (( DB_PORT <= 65535 )) || die "Invalid DB_PORT"
case "$DB_PROVISION" in
    auto) if [[ "$DB_HOST" == 127.0.0.1 && "$DB_PORT" == 5432 ]]; then DB_PROVISION=local; else DB_PROVISION=existing; fi ;;
    local|existing) ;;
    *) die "DB_PROVISION must be auto, local, or existing" ;;
esac
[[ "$DB_PROVISION" != local || ( "$DB_HOST" == 127.0.0.1 && "$DB_PORT" == 5432 ) ]] || die "Local provisioning requires 127.0.0.1:5432"
for value in "$DB_HOST" "$DB_PASSWORD" "$PUBLIC_URL"; do
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "Configuration values must be single-line"
done

export DEBIAN_FRONTEND=noninteractive
packages=(nginx postgresql-client php-fpm php-cli php-pgsql php-mbstring php-xml php-curl php-zip php-intl php-gd composer openssl ca-certificates rsync acl logrotate)
[[ "$DB_PROVISION" != local ]] || packages+=(postgresql)
missing=()
for package in "${packages[@]}"; do
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed' || missing+=("$package")
done
if ((${#missing[@]})); then
    printf 'Installing missing packages: %s\n' "${missing[*]}"
    apt-get update
    apt-get install -y --no-install-recommends "${missing[@]}"
else
    echo "All system packages are already installed."
fi

PHP_VERSION="$(php -r 'echo PHP_VERSION;')"
php -r 'exit(version_compare(PHP_VERSION, "8.2.0", ">=") ? 0 : 1);' || die "PHP 8.2+ is required; installed version is $PHP_VERSION"
php -m | grep -qi '^pdo_pgsql$' || die "The PHP PDO PostgreSQL extension is not enabled"
PHP_FPM_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
FPM_BINARY="$(command -v "php-fpm$PHP_FPM_VERSION")" || die "Matching PHP-FPM is not installed"
FPM_SERVICE="php$PHP_FPM_VERSION-fpm"
"$FPM_BINARY" -t
for target in "/etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SITE_NAME.conf" "$SITE_FILE" "/etc/logrotate.d/$SITE_NAME"; do
    [[ ! -L "$target" && ! -d "$target" ]] || die "Unexpected configuration target: $target"
    [[ ! -e "$target" || -f "$MARKER" ]] || die "Configuration name already in use: $target"
done
if [[ -e "/etc/nginx/sites-enabled/$SITE_NAME" || -L "/etc/nginx/sites-enabled/$SITE_NAME" ]]; then
    [[ -f "$MARKER" && "$(readlink "/etc/nginx/sites-enabled/$SITE_NAME")" == "$SITE_FILE" ]] || die "Enabled site name already in use"
fi

# Reuse PostgreSQL safely: never change an existing role's password or take
# ownership of an existing database. Custom DB_* values support shared hosts.
if [[ "$DB_PROVISION" == local ]]; then
systemctl enable --now postgresql
ROLE_EXISTS="$(runuser -u postgres -- psql -X -p "$DB_PORT" -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'")"
DATABASE_EXISTS="$(runuser -u postgres -- psql -X -p "$DB_PORT" -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")"
if [[ "$DATABASE_EXISTS" == "1" && "$ROLE_EXISTS" != "1" ]]; then
    die "Database '$DB_NAME' already exists and was not modified. Choose another DB_NAME or supply its existing DB_USER and DB_PASSWORD."
fi
if [[ "$ROLE_EXISTS" == "1" ]]; then
    [[ -n "${DB_PASSWORD:-}" ]] || die "PostgreSQL role '$DB_USER' already exists. Supply its DB_PASSWORD or choose another DB_USER. No existing password was changed."
else
    DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 24)}"
    runuser -u postgres -- psql -X -p "$DB_PORT" -v ON_ERROR_STOP=1 -v role_name="$DB_USER" -v role_password="$DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L', :'role_name', :'role_password') \gexec
SQL
fi
if [[ "$DATABASE_EXISTS" != "1" ]]; then
    runuser -u postgres -- createdb -p "$DB_PORT" --owner="$DB_USER" "$DB_NAME"
    runuser -u postgres -- psql -X -p "$DB_PORT" -v ON_ERROR_STOP=1 -v db_name="$DB_NAME" <<'SQL'
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'db_name') \gexec
SQL
    runuser -u postgres -- psql -X -p "$DB_PORT" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c 'REVOKE CREATE ON SCHEMA public FROM PUBLIC'
fi
fi
[[ -n "$DB_PASSWORD" ]] || die "Supply DB_PASSWORD for the existing database"
export PGPASSWORD="$DB_PASSWORD" PGCONNECT_TIMEOUT=10
DB_CLIENT=(psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1)
unsafe_role="$("${DB_CLIENT[@]}" -tAc "SELECT EXISTS (SELECT 1 FROM pg_roles WHERE (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls OR (rolname LIKE 'pg\\_%' AND rolname <> 'pg_database_owner')) AND pg_has_role(current_user, oid, 'MEMBER'))")"
[[ "$unsafe_role" == f ]] || die "Use a dedicated unprivileged database role without privileged memberships"
unset PGPASSWORD

if id -u "$SYSTEM_USER" >/dev/null 2>&1; then
    [[ -f "$MARKER" ]] || die "System account $SYSTEM_USER already exists without this deployment"
    case "$(getent passwd "$SYSTEM_USER" | cut -d: -f7)" in */nologin|*/false) ;; *) die "App account must not allow login" ;; esac
else
    getent group "$SYSTEM_USER" >/dev/null && die "App group already exists without app account"
    useradd --system --user-group --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$SYSTEM_USER"
fi
[[ "$(id -G "$SYSTEM_USER" | wc -w)" == 1 ]] || die "App account must not have supplementary groups"

install -d -o root -g "$SYSTEM_USER" -m 750 "$APP_DIR"
printf '%s\n' "$SITE_NAME" > "$MARKER"
rsync -a --delete \
    --exclude='.git/' \
    --exclude='.bitchin-kitchen-install' \
    --exclude='vendor/' \
    --exclude='.env' \
    --exclude='runtime/' \
    --exclude='public/uploads/' \
    "$SOURCE_DIR/" "$APP_DIR/"
ENV_FILE="$APP_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -f "$SOURCE_DIR/.env" ]]; then
        install -o root -g "$SYSTEM_USER" -m 640 "$SOURCE_DIR/.env" "$ENV_FILE"
    else
        install -o root -g "$SYSTEM_USER" -m 640 "$SOURCE_DIR/.env.example" "$ENV_FILE"
    fi
fi
# Replace complete keys without sed replacement escaping or shell evaluation.
write_env() {
    local key="$1" value="$2" temporary
    temporary="$(mktemp "$APP_DIR/.env.XXXXXX")"
    awk -v key="$key" 'index($0, key "=") != 1' "$ENV_FILE" > "$temporary"
    printf '%s=%s\n' "$key" "$value" >> "$temporary"
    chown root:"$SYSTEM_USER" "$temporary"; chmod 0640 "$temporary"
    mv -f "$temporary" "$ENV_FILE"
}
write_env APP_URL "$PUBLIC_URL"
write_env DB_HOST "$DB_HOST"
write_env DB_PORT "$DB_PORT"
write_env DB_NAME "$DB_NAME"
write_env DB_USER "$DB_USER"
write_env DB_PASSWORD "$DB_PASSWORD"
write_env UPLOAD_MAX_FILE_MB "$UPLOAD_MAX_FILE_MB"
write_env UPLOAD_MAX_REQUEST_MB "$UPLOAD_MAX_REQUEST_MB"

cd "$APP_DIR"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --no-plugins --no-scripts --optimize-autoloader --no-interaction
composer check-platform-reqs --no-dev
# Private code is root-owned; Nginx gets read/traverse ACLs only on public files.
chown -R root:"$SYSTEM_USER" "$APP_DIR"
find "$APP_DIR" -type d -exec chmod 0750 {} +
find "$APP_DIR" -type f -exec chmod 0640 {} +
chmod 0750 "$APP_DIR/setup.sh"
setfacl -m u:www-data:--x "$APP_DIR"
find "$APP_DIR/public" -type d -exec setfacl -m u:www-data:r-x {} +
find "$APP_DIR/public" -type f -exec setfacl -m u:www-data:r-- {} +
install -d -o "$SYSTEM_USER" -g "$SYSTEM_USER" -m 0700 "$APP_DIR/runtime"
install -d -o "$SYSTEM_USER" -g "$SYSTEM_USER" -m 0750 "$APP_DIR/public/uploads"
chown -R "$SYSTEM_USER:$SYSTEM_USER" "$APP_DIR/public/uploads" "$APP_DIR/runtime"
chmod -R u+rwX,go-rwx "$APP_DIR/runtime"
find "$APP_DIR/public/uploads" -type d -exec setfacl -m u:www-data:r-x,d:u::rwx,d:u:www-data:r-x,d:g::---,d:m::r-x,d:o::--- {} +
find "$APP_DIR/public/uploads" -type f -exec setfacl -m u:www-data:r-- {} +

export PGPASSWORD="$DB_PASSWORD"
psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$APP_DIR/database/schema.sql" || die "Could not initialize '$DB_NAME' using '$DB_USER'. Schema initialization may have partially completed; correct the error and rerun setup."
SUPERADMIN_COUNT="$(psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT count(*) FROM users WHERE role='superadmin'")"
if [[ "$SUPERADMIN_COUNT" == "0" ]]; then
    if [[ -z "${SUPERADMIN_NAME:-}" || -z "${SUPERADMIN_PASSWORD:-}" ]]; then
        [[ -t 0 ]] || die "Set SUPERADMIN_NAME and SUPERADMIN_PASSWORD for non-interactive setup"
        read -r -p "Superadmin username: " SUPERADMIN_NAME
        read -r -s -p "Superadmin password: " SUPERADMIN_PASSWORD
        printf '\n'
        read -r -s -p "Confirm password: " password_confirmation
        printf '\n'
        [[ "$SUPERADMIN_PASSWORD" == "$password_confirmation" ]] || die "Passwords do not match"
    fi
    ((${#SUPERADMIN_NAME} >= 2 && ${#SUPERADMIN_NAME} <= 100)) || die "Superadmin username must contain 2–100 characters"
    [[ -n "$SUPERADMIN_PASSWORD" ]] || die "Superadmin password cannot be empty"
    PASSWORD_HASH="$(SETUP_PASSWORD="$SUPERADMIN_PASSWORD" php -r 'echo password_hash(getenv("SETUP_PASSWORD"), PASSWORD_DEFAULT);')"
    psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
        -v admin_name="$SUPERADMIN_NAME" -v password_hash="$PASSWORD_HASH" <<'SQL'
INSERT INTO users (name, password_hash, role)
VALUES (:'admin_name', :'password_hash', 'superadmin');
INSERT INTO settings (key, value)
VALUES ('installed_at', CURRENT_TIMESTAMP::text)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
SQL
fi
unset PGPASSWORD SUPERADMIN_PASSWORD PASSWORD_HASH

FPM_SOCKET="/run/php/$SITE_NAME.sock"
SESSION_DIR="/var/lib/$SITE_NAME/sessions"
TEMP_DIR="/var/lib/$SITE_NAME/tmp"
LOG_DIR="/var/log/$SITE_NAME"
install -d -o root -g "$SYSTEM_USER" -m 0750 "/var/lib/$SITE_NAME" "$LOG_DIR"
install -d -o "$SYSTEM_USER" -g "$SYSTEM_USER" -m 0700 "$SESSION_DIR" "$TEMP_DIR"
touch "$LOG_DIR/php-error.log"
chown "$SYSTEM_USER:$SYSTEM_USER" "$LOG_DIR/php-error.log"
chmod 0640 "$LOG_DIR/php-error.log"

# Back up only configuration managed by this installer. Restore it on failure.
CONFIG_BACKUP="$(mktemp -d)"
CONFIG_TARGETS=()
CONFIG_COMMITTED=0
backup_config() {
    local target="$1" index="${#CONFIG_TARGETS[@]}"
    if [[ -e "$target" || -L "$target" ]]; then cp -a -- "$target" "$CONFIG_BACKUP/$index"; fi
    CONFIG_TARGETS+=("$target")
}
finish() {
    local status=$? index target
    trap - EXIT
    if (( ! CONFIG_COMMITTED )); then
        for index in "${!CONFIG_TARGETS[@]}"; do
            target="${CONFIG_TARGETS[$index]}"
            rm -f -- "$target"
            if [[ -e "$CONFIG_BACKUP/$index" || -L "$CONFIG_BACKUP/$index" ]]; then
                cp -a -- "$CONFIG_BACKUP/$index" "$target"
            fi
        done
        "$FPM_BINARY" -t && systemctl reload "$FPM_SERVICE" || true
        nginx -t && systemctl reload nginx || true
        printf 'Configuration restored. Application files and database changes are not rolled back.\n' >&2
    fi
    rm -rf -- "$CONFIG_BACKUP"
    exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
POOL_FILE="/etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SITE_NAME.conf"
ENABLED_SITE="/etc/nginx/sites-enabled/$SITE_NAME"
ROTATE_FILE="/etc/logrotate.d/$SITE_NAME"
for target in "$POOL_FILE" "$SITE_FILE" "$ENABLED_SITE" "$ROTATE_FILE"; do
    [[ ! -d "$target" ]] || die "Configuration target is a directory: $target"
    backup_config "$target"
done
cat > "$CONFIG_BACKUP/pool" <<FPM
[$SITE_NAME]
user = $SYSTEM_USER
group = $SYSTEM_USER
listen = $FPM_SOCKET
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = ondemand
pm.max_children = $PHP_MAX_CHILDREN
pm.process_idle_timeout = 15s
pm.max_requests = 250
request_terminate_timeout = ${PHP_REQUEST_SECONDS}s
clear_env = yes
security.limit_extensions = .php
php_admin_value[memory_limit] = ${PHP_MEMORY_MB}M
php_admin_value[max_execution_time] = $PHP_REQUEST_SECONDS
php_admin_value[max_input_time] = $PHP_REQUEST_SECONDS
php_admin_value[upload_max_filesize] = ${UPLOAD_MAX_FILE_MB}M
php_admin_value[post_max_size] = ${UPLOAD_MAX_REQUEST_MB}M
php_admin_value[max_file_uploads] = 20
php_admin_value[upload_tmp_dir] = $TEMP_DIR
php_admin_value[sys_temp_dir] = $TEMP_DIR
php_admin_value[session.save_handler] = files
php_admin_value[session.save_path] = $SESSION_DIR
php_value[session.name] = bitchin_kitchen
php_admin_value[session.use_strict_mode] = 1
php_admin_value[session.cookie_httponly] = 1
php_admin_value[session.gc_probability] = 1
php_admin_value[session.gc_divisor] = 100
php_admin_flag[display_errors] = off
php_admin_flag[display_startup_errors] = off
php_admin_flag[log_errors] = on
php_admin_value[error_log] = $LOG_DIR/php-error.log
FPM
install -m 0644 "$CONFIG_BACKUP/pool" "$POOL_FILE"
sed \
    -e "s|{{PORT}}|$PORT|g" \
    -e "s|{{PROJECT_ROOT}}|$APP_DIR|g" \
    -e "s|{{UPLOAD_MAX_REQUEST_MB}}|$UPLOAD_MAX_REQUEST_MB|g" \
    -e "s|{{FPM_SOCKET}}|$FPM_SOCKET|g" \
    -e "s|{{PHP_REQUEST_SECONDS}}|$PHP_REQUEST_SECONDS|g" \
    "$APP_DIR/config/nginx.conf.example" > "$CONFIG_BACKUP/nginx"
install -m 0644 "$CONFIG_BACKUP/nginx" "$SITE_FILE"
ln -sfn "$SITE_FILE" "$ENABLED_SITE"
# Nginx logs reside under /var/log/nginx and use Debian's nginx rotation rule.
cat > "$CONFIG_BACKUP/logrotate" <<ROTATE
$LOG_DIR/php-error.log {
    daily
    rotate 14
    maxsize 10M
    missingok
    notifempty
    compress
    delaycompress
    create 0640 $SYSTEM_USER $SYSTEM_USER
}
ROTATE
install -m 0644 "$CONFIG_BACKUP/logrotate" "$ROTATE_FILE"
"$FPM_BINARY" -t
nginx -t
logrotate --debug "$ROTATE_FILE"
systemctl enable "$FPM_SERVICE" nginx
for service in "$FPM_SERVICE" nginx; do
    if systemctl is-active --quiet "$service"; then systemctl reload "$service"; else systemctl start "$service"; fi
done
for _ in {1..20}; do [[ -S "$FPM_SOCKET" ]] && break; sleep 0.25; done
[[ -S "$FPM_SOCKET" ]] || die "App PHP-FPM socket was not created"
systemctl is-active --quiet "$FPM_SERVICE"
systemctl is-active --quiet nginx
runuser -u "$SYSTEM_USER" -- test -r "$ENV_FILE"
runuser -u "$SYSTEM_USER" -- test -w "$APP_DIR/runtime"
runuser -u "$SYSTEM_USER" -- test -w "$APP_DIR/public/uploads"
if runuser -u "$SYSTEM_USER" -- test -w "$APP_DIR/public/index.php"; then die "Application code is writable by PHP"; fi
if runuser -u www-data -- test -r "$ENV_FILE"; then die "Nginx can read app credentials"; fi
runuser -u www-data -- test -r "$APP_DIR/public/index.php"
# Exercise Nginx -> dedicated FPM -> database through a real application route.
php -r '$u=$argv[1]; $c=curl_init($u); curl_setopt_array($c,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_TIMEOUT=>15]); $r=curl_exec($c); $s=curl_getinfo($c,CURLINFO_HTTP_CODE); exit($r!==false && $s===200 ? 0 : 1);' "http://127.0.0.1:$PORT/" || die "Application HTTP health check failed"
CONFIG_COMMITTED=1
printf '\nBitchin Kitchen is installed and ready.\n'
printf 'Open %s and sign in with the superadmin account.\n' "$PUBLIC_URL"
printf 'Private configuration: %s/.env; PHP pool: %s\n' "$APP_DIR" "$POOL_FILE"
