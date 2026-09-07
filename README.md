# Bitchin' Kitchen

A mobile-first PHP recipe community for Debian where cooks publish recipes, keep notes, and make editable versions of recipes shared by others.

## Example screenshot

![Route Analysis Screenshot](Docs/ExampleScreenshot.JPG)

## Features

- Public recipe discovery with fast PostgreSQL full-text search
- Recipe pagination with a remembered 9, 18, 36, 60, or All page-size preference
- Cuisine and multi-tag classification with combined filtering
- Private recipes visible only to their owners
- Ownership-enforced editing and one-click "Make my version" recipe forking
- Multi-photo galleries; the first upload automatically becomes the search thumbnail
- Per-user recipe favorites with a dedicated Favorites page
- Superadmin-customizable brand icon
- Automatic photo resizing to a maximum of 1000×1000 pixels and optimized image encoding
- JPEG EXIF rotation and mirror correction for phone photos, with filename-specific upload rejection messages
- Adaptive (default), light, and dark baking-inspired themes
- Cooking calculators for volume, weight, oven temperature, and recipe scaling
- Three roles: one immutable superadmin, Web Admins who manage user roles, and regular users
- Superadmin-controlled global inactivity timeout, including a no-timeout option
- Configurable login throttling, password strength rules, and compromised-password screening
- CSRF protection, secure password hashing, parameterized SQL, MIME-checked uploads
- Native PHP/PostgreSQL/NGINX deployment that does not replace existing NGINX applications

## Requirements

- PHP 8.2+ with PDO PostgreSQL, fileinfo, GD, and EXIF extensions
- Composer 2
- PostgreSQL 14+
- NGINX and PHP-FPM; iproute2 (`ss`) for preflight listener checks
- Port 7373 available, or another port of your choice

## Install on Debian

Run the system installer as root:

```sh
git clone https://github.com/DLTaylor02/BitchinKitchen.git
cd BitchinKitchen
cp .env.example .env
nano .env # Enter existing PostgreSQL credentials, if applicable
chmod +x setup.sh
sudo ./setup.sh
```

The installer prompts for a custom listener port and displays `7373` on first installation, or the installed port on reruns. It checks for listener conflicts before deployment. Press Enter to accept it, or specify a new port.
You can also pass a custom listener port as the first argument for unattended or scripted installation:
```sh
sudo ./setup.sh 8088
```

Configure existing PostgreSQL credentials in `.env` before setup. Environment variables override the saved values. By default, setup provisions missing roles/databases only for `127.0.0.1:5432`. Other endpoints must already contain the database and role; no local PostgreSQL server is installed or configured for them. Use `sudo DB_PROVISION=existing ./setup.sh` to disable provisioning even for the default local endpoint. This option must be supplied on each run when desired.

Setup never resets an existing role password or changes an existing database owner. It rejects privileged runtime roles and privileged role memberships. Newly created databases deny access to `PUBLIC`, and their public schema denies public object creation. Existing database permissions remain under the administrator's control. Use a dedicated application database and role with permission to apply the schema.

The installer securely prompts for the initial superadmin username and password. Accounts do not use email addresses. For automated installation, provide the credentials as environment variables:
```sh
sudo SUPERADMIN_NAME="Kitchen Owner" \
  SUPERADMIN_PASSWORD="a-strong-12+-character-password" \
  ./setup.sh 7373
```

`setup.sh` installs missing packages, deploys to `/var/www/bitchinkitchen`, applies the schema, and creates the initial superadmin. Composer runs with plugins and scripts disabled. Run setup from a separate checkout; deployment directories must be empty or carry this installer's `.bitchin-kitchen-install` marker. Source/deployment symlinks are rejected. There is no legacy migration or cleanup.

On first installation, the source `.env` is copied into the deployment. Subsequent runs read the deployed `.env` and preserve uploads, runtime data, and Composer dependencies while synchronizing code. Explicit environment overrides are saved for application settings. Keep the deployment marker intact.

PHP runs as the non-login `bitchin-kitchen` account in its own FPM pool, using `/run/php/bitchin-kitchen.sock`. Root owns application code and `.env`; the app can read them but only write `runtime`, `public/uploads`, and its private session/temp directories. Nginx receives read/traverse ACLs for public content, including newly uploaded files, and cannot read `.env`. The filesystem must support POSIX ACLs. Only `/index.php` is passed to PHP.

Upload limits apply to this pool and Nginx site only. Resource defaults are 256 MB per PHP request, four workers, and a 60-second request timeout. Override these on each setup run as needed:

```sh
sudo PHP_MEMORY_MB=256 PHP_MAX_CHILDREN=4 PHP_REQUEST_SECONDS=60 ./setup.sh
```

These limits do not provide a total memory or CPU quota. Nginx and the PHP-FPM service remain shared, and processes running as `www-data` can access the FPM socket. Stronger isolation requires a separate service or container.

Sessions and temporary files live under `/var/lib/bitchin-kitchen/` with private permissions. PHP session garbage collection runs probabilistically during requests and uses the application's configured timeout, including its no-timeout setting. PHP errors go to `/var/log/bitchin-kitchen/php-error.log` with daily rotation (14 retained files). Nginx app logs live under `/var/log/nginx/` and use Debian's existing Nginx rotation rule.

Setup validates FPM, Nginx, and log rotation configuration, then reloads running services or starts inactive ones. It checks permissions and requests the homepage through Nginx/FPM before declaring success. Failed configuration activation restores the previous app configuration and attempts to reload it. Package installation, code deployment, and database/schema changes are not rolled back; take backups before updates. Other site configurations are preserved.

Run `bash tests/setup-checks.sh` for portable installer behavior checks. Full deployment validation requires a Debian host: test a fresh installation and rerun alongside another site, confirm uploads and sessions work, and verify the neighboring site remains available. Test an existing remote database separately.

## Image uploads

Rejected photos display their filename and a reason, such as an unsupported format, file-size limit, interrupted upload, unreadable image, excessive dimensions, or storage failure. Valid photos in a submitted batch still save. The browser checks file sizes, counts, and combined image size before submission; select fewer or smaller files if it reports a problem. Entire requests rejected by PHP or Nginx receive a clear “upload too large” response; filenames are unavailable when the server discards the request.

JPEG EXIF orientation is applied before saving, including mirrored orientations. Resizing and re-encoding remove the original EXIF metadata. Brand icons use the same processing. Images above 40 megapixels or the estimated available processing-memory budget are rejected with a resize suggestion. The installer checks for GD and EXIF support; rerun setup to deploy the new Nginx upload-error page.

Run `php tests/image-upload.php` with GD and EXIF enabled to check all eight orientations, resizing, transparency, malformed images, upload error messages, and storage failures. These tests do not need a database.

## Roles and privacy

- **Superadmin:** created once at installation; controls all settings and can rename or delete other accounts. The account is protected by a partial unique database index and cannot be demoted or deleted in the UI.
- **Web Admin:** can promote/demote other non-superadmin accounts, manage cuisines and tags, and use all normal recipe features.
- **User:** can create, view, search, and fork public recipes; can view and edit only their own private recipes.

## Resetting the superadmin password

If the superadmin password is lost, run the recovery utility directly on the Debian server:

```sh
sudo php /var/www/bitchinkitchen/bin/reset-superadmin-password.php
```

The command identifies the sole superadmin and securely prompts for the new password twice without displaying the input. The superadmin is exempt from configurable password rules; the operator is responsible for choosing a suitably strong password. The command changes only the superadmin password; the username, role, recipes, and other users are unaffected.

## Session timeout

The default inactivity timeout is 24 minutes, matching the application's previous behavior. The superadmin can change it from **Settings** in the Web UI. The value applies to every user:

- Enter the number of inactive minutes allowed before users must sign in again.
- Enter `0` to disable inactivity expiration.

Web Admins and regular users cannot view or change this setting. Existing sessions begin using a changed value on their next request.

## Login and password security

The superadmin can configure login and password protection from **Settings**

Read more in `Docs\Login and Security.md`

## License

Bitchin' Kitchen is available under the [MIT License](LICENSE). You may use, copy, modify, distribute, sublicense, or sell the software, provided the copyright and license notice are retained. The software is provided without warranty.
