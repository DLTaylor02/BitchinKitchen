<?php
namespace App;

final class LoginRateLimiter {
    public static function settings(): array {
        $values=['login_max_attempts'=>5,'login_window_minutes'=>15,'login_lockout_minutes'=>15];
        $rows=Database::connection()->query("SELECT key,value FROM settings WHERE key IN ('login_max_attempts','login_window_minutes','login_lockout_minutes')")->fetchAll();
        foreach($rows as $row)$values[$row['key']]=(int)$row['value'];
        return ['attempts'=>max(1,min(100,$values['login_max_attempts'])),'window'=>max(1,min(1440,$values['login_window_minutes'])),'lockout'=>max(1,min(1440,$values['login_lockout_minutes']))];
    }

    private static function identity(string $username, string $ip): array { $normalized=function_exists('mb_strtolower')?mb_strtolower(trim($username),'UTF-8'):strtolower(trim($username));$normalized=function_exists('mb_substr')?mb_substr($normalized,0,100,'UTF-8'):substr($normalized,0,100);return [$normalized,substr($ip,0,45)]; }

    public static function remainingLockout(string $username, string $ip): int {
        [$username,$ip]=self::identity($username,$ip);$q=Database::connection()->prepare('SELECT window_started,locked_until FROM login_throttles WHERE username=? AND ip_address=?');$q->execute([$username,$ip]);$row=$q->fetch();if(!$row)return 0;
        if($row['locked_until']){if(($remaining=strtotime($row['locked_until'])-time())>0)return $remaining;$q=Database::connection()->prepare('DELETE FROM login_throttles WHERE username=? AND ip_address=?');$q->execute([$username,$ip]);return 0;}
        $settings=self::settings();if(strtotime($row['window_started'])<time()-$settings['window']*60){$q=Database::connection()->prepare('DELETE FROM login_throttles WHERE username=? AND ip_address=?');$q->execute([$username,$ip]);}
        return 0;
    }

    public static function recordFailure(string $username, string $ip): int {
        [$username,$ip]=self::identity($username,$ip);$settings=self::settings();$pdo=Database::connection();if(random_int(1,100)===1)$pdo->exec("DELETE FROM login_throttles WHERE window_started < NOW()-INTERVAL '7 days'");$pdo->beginTransaction();
        try{$q=$pdo->prepare('SELECT failed_attempts,window_started FROM login_throttles WHERE username=? AND ip_address=? FOR UPDATE');$q->execute([$username,$ip]);$row=$q->fetch();$now=time();$attempts=1;if($row&&strtotime($row['window_started'])>=$now-$settings['window']*60)$attempts=(int)$row['failed_attempts']+1;$windowStarted=gmdate('c',$row&&strtotime($row['window_started'])>=$now-$settings['window']*60?strtotime($row['window_started']):$now);$lockedUntil=$attempts>=$settings['attempts']?gmdate('c',$now+$settings['lockout']*60):null;$q=$pdo->prepare('INSERT INTO login_throttles(username,ip_address,failed_attempts,window_started,locked_until) VALUES(?,?,?,?,?) ON CONFLICT(username,ip_address) DO UPDATE SET failed_attempts=excluded.failed_attempts,window_started=excluded.window_started,locked_until=excluded.locked_until');$q->execute([$username,$ip,$attempts,$windowStarted,$lockedUntil]);$pdo->commit();return $lockedUntil?$settings['lockout']*60:0;}catch(\Throwable $error){if($pdo->inTransaction())$pdo->rollBack();throw $error;}
    }

    public static function clear(string $username, string $ip): void { [$username,$ip]=self::identity($username,$ip);$q=Database::connection()->prepare('DELETE FROM login_throttles WHERE username=? AND ip_address=?');$q->execute([$username,$ip]); }
}
