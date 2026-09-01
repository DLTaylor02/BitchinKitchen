<?php
namespace App;
final class Auth {
    public static function user(): ?array {
        if (empty($_SESSION['user_id'])) return null;
        $q=Database::connection()->prepare('SELECT id,name,role FROM users WHERE id=?'); $q->execute([$_SESSION['user_id']]);
        return $q->fetch() ?: null;
    }
    public static function login(string $name, string $password): bool {
        $q=Database::connection()->prepare('SELECT * FROM users WHERE lower(name)=lower(?)'); $q->execute([$name]); $u=$q->fetch();
        if (!$u || !password_verify($password,$u['password_hash'])) return false;
        session_regenerate_id(true); $_SESSION['user_id']=$u['id']; return true;
    }
    public static function requireUser(): array { $u=self::user(); if(!$u){ flash('Please sign in first.','error'); redirect('/login'); } return $u; }
    public static function requireAdmin(): array { $u=self::requireUser(); if(!in_array($u['role'],['admin','superadmin'],true)) abort(403); return $u; }
}
