<?php
namespace App;
use PDO;
final class Database {
    private static ?PDO $pdo = null;
    public static function connection(): PDO {
        if (!self::$pdo) {
            $dsn=sprintf('pgsql:host=%s;port=%s;dbname=%s', Env::get('DB_HOST','db'), Env::get('DB_PORT','5432'), Env::get('DB_NAME','bitchin_kitchen'));
            self::$pdo=new PDO($dsn, Env::get('DB_USER','bitchin'), Env::get('DB_PASSWORD','change-me'), [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
        }
        return self::$pdo;
    }
}
