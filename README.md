# Bitchin' Kitchen

A mobile-first PHP recipe community for Debian where cooks publish recipes, keep private notes, and make editable versions of recipes shared by others.

## Features

- Public recipe discovery with fast PostgreSQL full-text search
- Private recipes visible only to their owners
- Ownership-enforced editing and one-click "Make my version" recipe forking
- Multi-photo galleries; the first upload automatically becomes the search thumbnail
- Adaptive (default), light, and dark baking-inspired themes
- Three roles: one immutable superadmin, Web Admins who manage user roles, and regular users
- Closed registration; Web Admins and the superadmin create accounts and reset passwords from the Users page
- CSRF protection, secure password hashing, parameterized SQL, MIME-checked uploads
- Native PHP/PostgreSQL/NGINX deployment that does not replace existing NGINX applications

## Requirements

- PHP 8.2+ with PDO PostgreSQL and fileinfo extensions
- Composer 2
- PostgreSQL 14+
- NGINX and PHP-FPM
- Port 7373 available, or another port of your choice

## Install on Debian

Run the system installer as root:

```sh
cp .env.example .env
nano .env # Enter existing PostgreSQL credentials, if applicable
chmod +x setup.sh
sudo ./setup.sh
```

The default port is 7373. Pass another port as the first argument if needed:

```sh
sudo ./setup.sh 8088
```

If PostgreSQL is already installed, copy `.env.example` to `.env` and edit `DB_HOST`, `DB_PORT`, `DB_USER`, and `DB_PASSWORD` before running setup. The installer reads these credentials from `.env`, reuses the existing service, and never resets an existing role's password or changes ownership of an existing database. If the configured role or database does not exist, setup creates only those dedicated resources without affecting other databases.

The installer securely prompts for the initial superadmin username and password. Accounts do not use email addresses. For automated installation, provide the credentials as environment variables:

```sh
sudo SUPERADMIN_NAME="Kitchen Owner" \
  SUPERADMIN_PASSWORD="a-strong-12+-character-password" \
  ./setup.sh 7373
```

`setup.sh` installs any missing NGINX, PostgreSQL, PHP 8.2+, PHP-FPM extensions, Composer, and supporting packages. It deploys the application to `/var/www/bitchinkitchen`, creates the PostgreSQL role and database, applies the complete schema, creates the sole superadmin, installs Composer packages, configures NGINX, enables services, and validates the NGINX configuration before restarting it. No browser-based installation step is required. Existing NGINX site files are not removed.

The checkout directory is used only as the installation source and is never served by NGINX. On the first installation, a source `.env` is copied into the deployment. After that, `/var/www/bitchinkitchen/.env` is the authoritative configuration. Re-running setup synchronizes application code while preserving that file, uploaded photos, and runtime data. Production code is read-only to `www-data`; only `public/uploads` and `runtime` are writable.

The upload controls in `.env` have distinct purposes: `UPLOAD_MAX_FILE_MB` limits each photograph, while `UPLOAD_MAX_REQUEST_MB` limits the complete multi-photo request. Setup applies the request limit to NGINX and writes matching PHP-FPM limits.

The application listens on `0.0.0.0:7373` by default, or on the custom port supplied to `setup.sh`. It therefore accepts connections on every network interface while remaining isolated from existing NGINX applications on other ports. Set `APP_URL` in `.env` if the automatically detected server address is not its public URL.

## Roles and privacy

- **Superadmin:** created once at installation; protected by a partial unique database index and cannot be demoted in the UI.
- **Web Admin:** can promote/demote other non-superadmin accounts and use all normal recipe features.
- **User:** can create, view, search, and fork public recipes; can view and edit only their own private recipes.

Copying a public recipe duplicates its text and gallery references into a new, public recipe owned by the copier, then opens it for editing. Original recipes are never modified.
