#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_PORT=7373
PORT="${1:-}"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/var/www/bitchinkitchen"
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run this setup as root: sudo ./setup.sh [port]"
if [[ -z "$PORT" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Application port [$DEFAULT_PORT]: " PORT
    fi
    PORT="${PORT:-$DEFAULT_PORT}"
fi
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die "Port must be between 1 and 65535"
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
SITE_NAME="bitchin-kitchen"
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
SERVER_IP="${SERVER_IP:-localhost}"
PUBLIC_URL="${APP_URL:-$(read_env APP_URL)}"; PUBLIC_URL="${PUBLIC_URL:-http://$SERVER_IP:$PORT}"

[[ "$DB_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die "DB_USER must be a valid PostgreSQL identifier"
[[ "$DB_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die "DB_NAME must be a valid PostgreSQL identifier"
[[ "$UPLOAD_MAX_FILE_MB" =~ ^[0-9]+$ ]] && (( UPLOAD_MAX_FILE_MB > 0 )) || die "UPLOAD_MAX_FILE_MB must be a positive integer"
[[ "$UPLOAD_MAX_REQUEST_MB" =~ ^[0-9]+$ ]] && (( UPLOAD_MAX_REQUEST_MB >= UPLOAD_MAX_FILE_MB )) || die "UPLOAD_MAX_REQUEST_MB must be at least UPLOAD_MAX_FILE_MB"
[[ -f /etc/debian_version ]] || die "This installer supports Debian-based systems only"
command -v apt-get >/dev/null 2>&1 || die "apt-get was not found"

export DEBIAN_FRONTEND=noninteractive
packages=(nginx postgresql postgresql-client php-fpm php-cli php-pgsql php-mbstring php-xml php-curl php-zip php-intl php-gd composer openssl ca-certificates rsync)
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
systemctl enable --now postgresql

# Reuse PostgreSQL safely: never change an existing role's password or take
# ownership of an existing database. Custom DB_* values support shared hosts.
ROLE_EXISTS="$(runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'")"
DATABASE_EXISTS="$(runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")"
if [[ "$DATABASE_EXISTS" == "1" && "$ROLE_EXISTS" != "1" ]]; then
    die "Database '$DB_NAME' already exists and was not modified. Choose another DB_NAME or supply its existing DB_USER and DB_PASSWORD."
fi
if [[ "$ROLE_EXISTS" == "1" ]]; then
    [[ -n "${DB_PASSWORD:-}" ]] || die "PostgreSQL role '$DB_USER' already exists. Supply its DB_PASSWORD or choose another DB_USER. No existing password was changed."
else
    DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 24)}"
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -v role_name="$DB_USER" -v role_password="$DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role_name', :'role_password') \gexec
SQL
fi
if [[ "$DATABASE_EXISTS" != "1" ]]; then
    runuser -u postgres -- createdb --owner="$DB_USER" "$DB_NAME"
fi

install -d -o root -g www-data -m 750 "$APP_DIR"
rsync -a --delete \
    --exclude='.git/' \
    --exclude='.env' \
    --exclude='runtime/' \
    --exclude='public/uploads/' \
    "$SOURCE_DIR/" "$APP_DIR/"
ENV_FILE="$APP_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -f "$SOURCE_DIR/.env" ]]; then
        install -o root -g www-data -m 640 "$SOURCE_DIR/.env" "$ENV_FILE"
    else
        install -o root -g www-data -m 640 "$SOURCE_DIR/.env.example" "$ENV_FILE"
    fi
fi
sed -i -e '/^APP_ENV=/d' -e '/^APP_KEY=/d' -e '/^UPLOAD_MAX_MB=/d' "$ENV_FILE"
grep -q '^UPLOAD_MAX_FILE_MB=' "$ENV_FILE" || printf 'UPLOAD_MAX_FILE_MB=%s\n' "$UPLOAD_MAX_FILE_MB" >> "$ENV_FILE"
grep -q '^UPLOAD_MAX_REQUEST_MB=' "$ENV_FILE" || printf 'UPLOAD_MAX_REQUEST_MB=%s\n' "$UPLOAD_MAX_REQUEST_MB" >> "$ENV_FILE"
SED_DB_PASSWORD="$(printf '%s' "$DB_PASSWORD" | sed 's/[&|\\]/\\&/g')"
sed -i \
    -e "s|^APP_URL=.*|APP_URL=$PUBLIC_URL|" \
    -e "s|^DB_HOST=.*|DB_HOST=$DB_HOST|" \
    -e "s|^DB_PORT=.*|DB_PORT=$DB_PORT|" \
    -e "s|^DB_NAME=.*|DB_NAME=$DB_NAME|" \
    -e "s|^DB_USER=.*|DB_USER=$DB_USER|" \
    -e "s|^DB_PASSWORD=.*|DB_PASSWORD=$SED_DB_PASSWORD|" \
    -e "s|^UPLOAD_MAX_FILE_MB=.*|UPLOAD_MAX_FILE_MB=$UPLOAD_MAX_FILE_MB|" \
    -e "s|^UPLOAD_MAX_REQUEST_MB=.*|UPLOAD_MAX_REQUEST_MB=$UPLOAD_MAX_REQUEST_MB|" \
    "$ENV_FILE"
chmod 640 "$ENV_FILE"
chown root:www-data "$ENV_FILE"

cd "$APP_DIR"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction
install -d -o www-data -g www-data -m 775 "$APP_DIR/public/uploads" "$APP_DIR/runtime"
chown -R root:www-data "$APP_DIR/public" "$APP_DIR/src" "$APP_DIR/views" "$APP_DIR/vendor"
chmod -R g+rX,o-rwx "$APP_DIR/public" "$APP_DIR/src" "$APP_DIR/views" "$APP_DIR/vendor"
chown -R www-data:www-data "$APP_DIR/public/uploads" "$APP_DIR/runtime"
chmod -R u+rwX,g+rwX,o-rwx "$APP_DIR/public/uploads" "$APP_DIR/runtime"

export PGPASSWORD="$DB_PASSWORD"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$APP_DIR/database/schema.sql" || die "Could not initialize '$DB_NAME' using '$DB_USER'. Existing PostgreSQL resources were not changed."
SUPERADMIN_COUNT="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT count(*) FROM users WHERE role='superadmin'")"
if [[ "$SUPERADMIN_COUNT" == "0" ]]; then
    if [[ -z "${SUPERADMIN_NAME:-}" || -z "${SUPERADMIN_PASSWORD:-}" ]]; then
        [[ -t 0 ]] || die "Set SUPERADMIN_NAME and SUPERADMIN_PASSWORD for non-interactive setup"
        read -r -p "Superadmin username: " SUPERADMIN_NAME
        read -r -s -p "Superadmin password (12+ characters): " SUPERADMIN_PASSWORD
        printf '\n'
        read -r -s -p "Confirm password: " password_confirmation
        printf '\n'
        [[ "$SUPERADMIN_PASSWORD" == "$password_confirmation" ]] || die "Passwords do not match"
    fi
    ((${#SUPERADMIN_NAME} >= 2 && ${#SUPERADMIN_NAME} <= 100)) || die "Superadmin username must contain 2–100 characters"
    ((${#SUPERADMIN_PASSWORD} >= 12)) || die "Superadmin password must contain at least 12 characters"
    PASSWORD_HASH="$(SETUP_PASSWORD="$SUPERADMIN_PASSWORD" php -r 'echo password_hash(getenv("SETUP_PASSWORD"), PASSWORD_DEFAULT);')"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
        -v admin_name="$SUPERADMIN_NAME" -v password_hash="$PASSWORD_HASH" <<'SQL'
INSERT INTO users (name, password_hash, role)
VALUES (:'admin_name', :'password_hash', 'superadmin');
INSERT INTO settings (key, value)
VALUES ('installed_at', CURRENT_TIMESTAMP::text)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
SQL
fi
unset PGPASSWORD SUPERADMIN_PASSWORD PASSWORD_HASH

FPM_SOCKET="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' -print -quit 2>/dev/null || true)"
[[ -n "$FPM_SOCKET" ]] || die "No PHP-FPM socket was found under /run/php"
PHP_FPM_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
PHP_UPLOAD_CONFIG="/etc/php/$PHP_FPM_VERSION/fpm/conf.d/99-bitchin-kitchen.ini"
printf 'upload_max_filesize = %sM\npost_max_size = %sM\nmax_file_uploads = 20\n' "$UPLOAD_MAX_FILE_MB" "$UPLOAD_MAX_REQUEST_MB" > "$PHP_UPLOAD_CONFIG"
sed \
    -e "s|{{PORT}}|$PORT|g" \
    -e "s|{{PROJECT_ROOT}}|$APP_DIR|g" \
    -e "s|{{UPLOAD_MAX_REQUEST_MB}}|$UPLOAD_MAX_REQUEST_MB|g" \
    -e "s|fastcgi_pass 127.0.0.1:9000;|fastcgi_pass unix:$FPM_SOCKET;|" \
    "$APP_DIR/config/nginx.conf.example" > "/etc/nginx/sites-available/$SITE_NAME"
ln -sfn "/etc/nginx/sites-available/$SITE_NAME" "/etc/nginx/sites-enabled/$SITE_NAME"

nginx -t
systemctl enable nginx
systemctl restart nginx
systemctl restart "$(basename "$FPM_SOCKET" .sock)"

printf '\nBitchin’ Kitchen is installed and ready.\n'
printf 'Open %s and sign in with the superadmin account.\n' "$PUBLIC_URL"
printf 'Database credentials were saved to %s/.env (mode 640).\n' "$APP_DIR"
