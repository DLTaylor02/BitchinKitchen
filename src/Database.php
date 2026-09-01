<?php
namespace App;
use PDO;
final class Database {
    private static ?PDO $pdo = null;
    public static function connection(): PDO {
        if (!self::$pdo) {
            $required=[];foreach(['DB_HOST','DB_PORT','DB_NAME','DB_USER','DB_PASSWORD'] as $key){if(Env::get($key)===null||Env::get($key)==='')$required[]=$key;}
            if($required) throw new \RuntimeException('Missing configuration: '.implode(', ',$required));
            $dsn=sprintf('pgsql:host=%s;port=%s;dbname=%s', Env::get('DB_HOST'), Env::get('DB_PORT'), Env::get('DB_NAME'));
            self::$pdo=new PDO($dsn, Env::get('DB_USER'), Env::get('DB_PASSWORD'), [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
        }
        return self::$pdo;
    }
}
