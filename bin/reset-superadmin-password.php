#!/usr/bin/env php
<?php
declare(strict_types=1);

use App\Database;
use App\Env;

$root = dirname(__DIR__);
if (!is_file($root.'/vendor/autoload.php')) {
    fwrite(STDERR, "Composer dependencies are missing. Run setup.sh first.\n");
    exit(1);
}
require $root.'/vendor/autoload.php';
Env::load($root.'/.env');

function secretPrompt(string $prompt): string
{
    fwrite(STDOUT, $prompt);
    $interactive = function_exists('stream_isatty') && stream_isatty(STDIN);
    if ($interactive) shell_exec('stty -echo');
    try {
        $value = fgets(STDIN);
    } finally {
        if ($interactive) {
            shell_exec('stty echo');
            fwrite(STDOUT, PHP_EOL);
        }
    }
    return trim($value === false ? '' : $value);
}

try {
    $pdo = Database::connection();
    $superadmin = $pdo->query("SELECT id, name FROM users WHERE role='superadmin' LIMIT 1")->fetch();
    if (!$superadmin) throw new RuntimeException('No superadmin account exists. Run setup.sh first.');

    fwrite(STDOUT, "Resetting password for superadmin: {$superadmin['name']}\n");
    $password = secretPrompt('New password: ');
    if ($password === '') throw new RuntimeException('The password cannot be empty.');
    $confirmation = secretPrompt('Confirm new password: ');
    if (!hash_equals($password, $confirmation)) throw new RuntimeException('The passwords do not match.');

    $statement = $pdo->prepare('UPDATE users SET password_hash=? WHERE id=?');
    $statement->execute([password_hash($password, PASSWORD_DEFAULT), $superadmin['id']]);
    fwrite(STDOUT, "Superadmin password updated successfully.\n");
} catch (Throwable $error) {
    fwrite(STDERR, "Password reset failed: {$error->getMessage()}\n");
    exit(1);
}
