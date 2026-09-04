<?php
namespace App;

final class PasswordPolicy {
    public static function settings(): array {
        $defaults=['password_min_length'=>'12','password_min_strength'=>'strong','breach_check_enabled'=>'true'];
        try {
            $rows=Database::connection()->query("SELECT key,value FROM settings WHERE key IN ('password_min_length','password_min_strength','breach_check_enabled')")->fetchAll();
            foreach($rows as $row)$defaults[$row['key']]=$row['value'];
        } catch(\Throwable) {}
        return ['min_length'=>max(8,min(128,(int)$defaults['password_min_length'])),'strength'=>in_array($defaults['password_min_strength'],['basic','standard','strong'],true)?$defaults['password_min_strength']:'strong','breach_check'=>filter_var($defaults['breach_check_enabled'],FILTER_VALIDATE_BOOL)];
    }

    public static function validate(string $password, string $role): array {
        if($password==='')return ['errors'=>['Password cannot be empty.'],'breach_unavailable'=>false];
        if($role==='superadmin')return ['errors'=>[],'breach_unavailable'=>false];
        $settings=self::settings();$errors=[];$categories=0;
        foreach(['/\p{Ll}/u','/\p{Lu}/u','/\p{N}/u','/[^\p{L}\p{N}\s]/u'] as $pattern)if(preg_match($pattern,$password))$categories++;
        $length=function_exists('mb_strlen')?mb_strlen($password,'UTF-8'):strlen($password);if($length<$settings['min_length'])$errors[]='Password must contain at least '.$settings['min_length'].' characters.';
        if($settings['strength']==='standard'&&$categories<3)$errors[]='Password must use at least three of: uppercase letters, lowercase letters, numbers, and symbols.';
        if($settings['strength']==='strong'&&$categories<4)$errors[]='Password must include an uppercase letter, lowercase letter, number, and symbol.';
        $unavailable=false;
        if(!$errors&&$settings['breach_check']){$breached=PwnedPasswords::contains($password);if($breached===true)$errors[]='Choose another password. This password appears in a list of passwords exposed in data breaches.';elseif($breached===null)$unavailable=true;}
        return ['errors'=>$errors,'breach_unavailable'=>$unavailable];
    }
}
