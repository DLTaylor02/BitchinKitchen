<?php
namespace App;

final class PwnedPasswords {
    public static function contains(string $password): ?bool {
        if(!function_exists('curl_init')){error_log('Bitchin Kitchen: breached-password screening unavailable because cURL is missing.');return null;}
        $hash=strtoupper(sha1($password));$prefix=substr($hash,0,5);$suffix=substr($hash,5);
        $curl=curl_init('https://api.pwnedpasswords.com/range/'.$prefix);
        if($curl===false){error_log('Bitchin Kitchen: breached-password screening could not be initialized.');return null;}
        curl_setopt_array($curl,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_CONNECTTIMEOUT=>2,CURLOPT_TIMEOUT=>5,CURLOPT_HTTPHEADER=>['Add-Padding: true','User-Agent: BitchinKitchen Password Screening']]);
        $result=curl_exec($curl);$status=(int)curl_getinfo($curl,CURLINFO_RESPONSE_CODE);$error=curl_error($curl);curl_close($curl);
        if(!is_string($result)||$status!==200){error_log('Bitchin Kitchen: breached-password screening unavailable'.($error?': '.$error:' (HTTP '.$status.')'));return null;}
        foreach(preg_split('/\r?\n/',$result) as $line){[$candidate,$count]=array_pad(explode(':',$line,2),2,'0');if((int)$count>0&&strlen($candidate)===35&&hash_equals($suffix,strtoupper($candidate)))return true;}
        return false;
    }
}
