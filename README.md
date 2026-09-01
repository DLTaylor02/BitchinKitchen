# Bitchin' Kitchen

A mobile-first PHP recipe community for Debian where cooks publish recipes, keep private notes, and make editable versions of recipes shared by others.

## Features

- Public recipe discovery with fast PostgreSQL full-text search
- Private recipes visible only to their owners
- Ownership-enforced editing and one-click "Make my version" recipe forking
- Multi-photo galleries; the first upload automatically becomes the search thumbnail
- Adaptive (default), light, and dark baking-inspired themes
- Three roles: one immutable superadmin, Web Admins who manage user roles, and regular users
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
chmod +x setup.sh
sudo ./setup.sh
```

To use a custom port:

```sh
sudo ./setup.sh 8088
```

`setup.sh` installs any missing NGINX, PostgreSQL, PHP 8.2+, PHP-FPM extensions, Composer, and supporting packages. It then creates a dedicated PostgreSQL role and database, generates strong application/database secrets, installs Composer packages, configures an isolated NGINX site, enables services, and checks the NGINX configuration before restarting it. Existing NGINX site files are not removed or overwritten.

Open `http://localhost:7373/install` (or your custom port). The web installer creates the database schema and sole superadmin, then permanently locks itself.

The generated server listens only on `127.0.0.1` and its own port, so it coexists with current NGINX applications. Change the listen address or add a reverse-proxy server block if remote access is required. Set `APP_URL` to the public URL when doing so.

## Local development on Debian

After running `setup.sh`, PHP's built-in server can be used instead of NGINX during development:

```sh
composer serve
```

Visit `/install` to initialize the schema and superadmin.

## Roles and privacy

- **Superadmin:** created once at installation; protected by a partial unique database index and cannot be demoted in the UI.
- **Web Admin:** can promote/demote other non-superadmin accounts and use all normal recipe features.
- **User:** can create, view, search, and fork public recipes; can view and edit only their own private recipes.

Copying a public recipe duplicates its text and gallery references into a new, public recipe owned by the copier, then opens it for editing. Original recipes are never modified.
