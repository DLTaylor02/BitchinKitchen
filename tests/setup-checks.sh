#!/usr/bin/env bash
# Portable behavior checks; never run the installer or alter host services.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash -n setup.sh
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
die() { printf '%s\n' "$*" >&2; exit 1; }
extract_function() { sed -n "/^$1() {/,/^}/p" setup.sh; }

# Recognize a real pre-marker installation, but never adopt an unrelated directory.
eval "$(extract_function recognize_deployment)"
SITE_NAME=bitchin-kitchen
deployment="$TEST_DIR/deployment"
mkdir -p "$deployment/public" "$deployment/src" "$deployment/database"
if recognize_deployment "$deployment"; then die 'Recognized an empty directory'; fi
cp composer.json "$deployment/"
cp public/index.php "$deployment/public/"
cp src/Database.php src/Auth.php "$deployment/src/"
cp database/schema.sql "$deployment/database/"
recognize_deployment "$deployment" || die 'Rejected an existing app without a marker'
printf 'unrelated-app\n' > "$deployment/.bitchin-kitchen-install"
if recognize_deployment "$deployment"; then die 'Ignored a conflicting marker'; fi
printf '%s\n' "$SITE_NAME" > "$deployment/.bitchin-kitchen-install"
recognize_deployment "$deployment" || die 'Rejected a marked installation'
unrelated="$TEST_DIR/unrelated"
mkdir -p "$unrelated/public" "$unrelated/src" "$unrelated/database"
cp composer.json "$unrelated/"
touch "$unrelated/public/index.php" "$unrelated/src/Database.php" "$unrelated/src/Auth.php" "$unrelated/database/schema.sql"
if recognize_deployment "$unrelated"; then die 'Recognized a directory from its manifest alone'; fi

# Environment rewrites preserve special characters and unrelated settings.
eval "$(extract_function write_env)"
chown() { :; }
APP_DIR="$TEST_DIR"
ENV_FILE="$TEST_DIR/.env"
SYSTEM_USER=test
printf 'DB_PASSWORD=old\nAPP_DEBUG=false\nDB_PASSWORD=duplicate\n' > "$ENV_FILE"
password='a&b|c\d$(not-a-command)`literal`'
write_env DB_PASSWORD "$password"
[[ "$(grep -c '^DB_PASSWORD=' "$ENV_FILE")" == 1 ]]
grep -Fxq "DB_PASSWORD=$password" "$ENV_FILE"
grep -Fxq 'APP_DEBUG=false' "$ENV_FILE"
write_env DB_HOST db.example.test
grep -Fxq 'DB_HOST=db.example.test' "$ENV_FILE"

# Exercise actual provisioning selection without contacting a database.
selection="$(sed -n '/^case "$DB_PROVISION" in/,/^esac/p' setup.sh)"
DB_PROVISION=auto DB_HOST=127.0.0.1 DB_PORT=5432
eval "$selection"
[[ "$DB_PROVISION" == local ]]
DB_PROVISION=auto DB_HOST=db.example.test DB_PORT=5432
eval "$selection"
[[ "$DB_PROVISION" == existing ]]
DB_PROVISION=auto DB_HOST=127.0.0.1 DB_PORT=5433
eval "$selection"
[[ "$DB_PROVISION" == existing ]]
DB_PROVISION=existing DB_HOST=127.0.0.1 DB_PORT=5432
eval "$selection"
[[ "$DB_PROVISION" == existing ]]

# Nginx -T reports enabled paths; reruns must recognize their own site.
nginx() { if [[ "$1" == -T ]]; then printf '%s\n' "$NGINX_DUMP"; fi; }
SITE_NAME=bitchin-kitchen
SITE_FILE=/etc/nginx/sites-available/bitchin-kitchen
PORT=7373
preflight="$(sed -n '/^if command -v nginx /,/^fi/p' setup.sh)"
NGINX_DUMP=$'# configuration file /etc/nginx/sites-enabled/bitchin-kitchen:\n    listen 0.0.0.0:7373;'
eval "$preflight"
for address in 7373 0.0.0.0:7373 '[::]:7373'; do
    NGINX_DUMP=$(printf '# configuration file /etc/nginx/conf.d/neighbor.conf:\n    listen %s;\n' "$address")
    if (eval "$preflight") 2>/dev/null; then die "Missed listener conflict: $address"; fi
done
NGINX_DUMP=$'# configuration file /etc/nginx/conf.d/neighbor.conf:\n    listen 8080;'
eval "$preflight"

# Failed activation restores existing files and removes newly created ones.
eval "$(extract_function backup_config)"
eval "$(extract_function finish)"
CONFIG_BACKUP="$TEST_DIR/backup"
mkdir "$CONFIG_BACKUP"
CONFIG_TARGETS=()
CONFIG_COMMITTED=0
FPM_BINARY=true
FPM_SERVICE=test
systemctl() { :; }
printf 'original\n' > "$TEST_DIR/existing"
backup_config "$TEST_DIR/existing"
backup_config "$TEST_DIR/new"
printf 'changed\n' > "$TEST_DIR/existing"
printf 'new\n' > "$TEST_DIR/new"
if (trap finish EXIT; exit 7) 2>/dev/null; then die 'Rollback lost failure status'; else [[ $? == 7 ]]; fi
[[ "$(cat "$TEST_DIR/existing")" == original ]]
[[ ! -e "$TEST_DIR/new" ]]

printf 'Installer behavior checks passed.\n'
