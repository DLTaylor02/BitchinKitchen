#!/usr/bin/env bash
set -Eeuo pipefail

PORT="${1:-7373}"
APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DB_NAME="bitchin_kitchen"
DB_USER="bitchin"
SITE_NAME="bitchin-kitchen"
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
SERVER_IP="${SERVER_IP:-localhost}"
PUBLIC_URL="${APP_URL:-http://$SERVER_IP:$PORT}"

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run this setup as root: sudo ./setup.sh [port]"
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die "Port must be between 1 and 65535"
[[ -f /etc/debian_version ]] || die "This installer supports Debian-based systems only"
command -v apt-get >/dev/null 2>&1 || die "apt-get was not found"

export DEBIAN_FRONTEND=noninteractive
packages=(nginx postgresql postgresql-client php-fpm php-cli php-pgsql php-mbstring php-xml php-curl php-zip php-intl php-gd composer openssl ca-certificates)
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

DB_PASSWORD="$(openssl rand -hex 24)"
if runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "ALTER ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASSWORD';"
else
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASSWORD';"
fi
if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
    runuser -u postgres -- createdb --owner="$DB_USER" "$DB_NAME"
fi

if [[ ! -f "$APP_DIR/.env" ]]; then
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
fi
APP_KEY="$(openssl rand -hex 32)"
sed -i \
    -e "s|^APP_URL=.*|APP_URL=$PUBLIC_URL|" \
    -e "s|^APP_KEY=.*|APP_KEY=$APP_KEY|" \
    -e "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" \
    -e "s|^DB_NAME=.*|DB_NAME=$DB_NAME|" \
    -e "s|^DB_USER=.*|DB_USER=$DB_USER|" \
    -e "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" \
    "$APP_DIR/.env"
chmod 640 "$APP_DIR/.env"
chown root:www-data "$APP_DIR/.env"

cd "$APP_DIR"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction
install -d -o www-data -g www-data -m 775 "$APP_DIR/public/uploads" "$APP_DIR/runtime"

export PGPASSWORD="$DB_PASSWORD"
psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$APP_DIR/database/schema.sql"
SUPERADMIN_COUNT="$(psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT count(*) FROM users WHERE role='superadmin'")"
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
    psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
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
sed \
    -e "s|{{PORT}}|$PORT|g" \
    -e "s|{{PROJECT_ROOT}}|$APP_DIR|g" \
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
