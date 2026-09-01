<?php
namespace App;
final class Env {
    public static function load(string $file): void {
        if (!is_file($file)) return;
        foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            if (str_starts_with(trim($line), '#') || !str_contains($line, '=')) continue;
            [$key, $value] = explode('=', $line, 2);
            $value = trim($value, " \t\n\r\0\x0B\"'");
            if (getenv(trim($key)) === false) putenv(trim($key).'='.$value);
        }
    }
    public static function get(string $key, mixed $default = null): mixed { $v=getenv($key); return $v === false ? $default : $v; }
    public static function bool(string $key, bool $default=false): bool { $v=self::get($key); return $v===null?$default:filter_var($v,FILTER_VALIDATE_BOOL); }
}
