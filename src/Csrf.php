<?php
namespace App;
final class Csrf {
    public static function token(): string { return $_SESSION['_token'] ??= bin2hex(random_bytes(24)); }
    public static function verify(): void { if(!hash_equals($_SESSION['_token'] ?? '', $_POST['_token'] ?? '')) abort(419, 'Your session expired. Please try again.'); }
}
