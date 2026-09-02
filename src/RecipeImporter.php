<?php
namespace App;

use DOMDocument;
use DOMXPath;
use RuntimeException;

final class RecipeImporter {
    private const HOSTS=['seriouseats.com','www.seriouseats.com'];

    public static function import(string $url): array {
        $html=self::fetch($url);$dom=new DOMDocument();libxml_use_internal_errors(true);$dom->loadHTML($html,LIBXML_NOERROR|LIBXML_NOWARNING);libxml_clear_errors();
        $xpath=new DOMXPath($dom);$recipe=null;
        foreach($xpath->query('//script[@type="application/ld+json"]') as $script){$data=json_decode($script->textContent,true);if(is_array($data)&&($found=self::findRecipe($data))){$recipe=$found;break;}}
        if(!$recipe)throw new RuntimeException('No structured recipe data was found on that page.');
        $ingredients=array_values(array_filter(array_map([self::class,'text'],(array)($recipe['recipeIngredient']??[]))));
        $instructions=self::instructions($recipe['recipeInstructions']??[]);if(!$ingredients||!$instructions)throw new RuntimeException('The recipe card is missing ingredients or instructions.');
        $author=$recipe['author']??'';if(is_array($author)&&array_is_list($author))$author=$author[0]??'';if(is_array($author))$author=$author['name']??'';
        $cuisine=$recipe['recipeCuisine']??'';if(is_array($cuisine))$cuisine=$cuisine[0]??'';
        $keywords=$recipe['keywords']??[];if(is_string($keywords))$keywords=preg_split('/\s*,\s*/',$keywords,-1,PREG_SPLIT_NO_EMPTY);
        $notes=[];if(!empty($recipe['recipeYield']))$notes[]='Yield: '.self::text(is_array($recipe['recipeYield'])?implode(', ',$recipe['recipeYield']):$recipe['recipeYield']);
        return ['title'=>self::text($recipe['name']??''),'summary'=>self::text($recipe['description']??''),'ingredients'=>implode("\n",$ingredients),'instructions'=>implode("\n\n",$instructions),'notes'=>implode("\n",$notes),'cuisine'=>self::text($cuisine),'keywords'=>array_map([self::class,'text'],(array)$keywords),'source_url'=>$url,'source_name'=>'Serious Eats','source_author'=>self::text($author)];
    }

    private static function fetch(string &$url): string {
        for($redirects=0;$redirects<4;$redirects++){$parts=parse_url($url);$host=strtolower($parts['host']??'');if(($parts['scheme']??'')!=='https'||!in_array($host,self::HOSTS,true)||isset($parts['user'])||isset($parts['pass'])||isset($parts['port']))throw new RuntimeException('Only HTTPS recipe URLs from Serious Eats are currently supported.');
            $ips=gethostbynamel($host)?:[];$ip=null;foreach($ips as $candidate){if(filter_var($candidate,FILTER_VALIDATE_IP,FILTER_FLAG_NO_PRIV_RANGE|FILTER_FLAG_NO_RES_RANGE)){$ip=$candidate;break;}}if(!$ip)throw new RuntimeException('The recipe host could not be resolved safely.');
            $headers=[];$body='';$ch=curl_init($url);curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>false,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_CONNECTTIMEOUT=>5,CURLOPT_TIMEOUT=>12,CURLOPT_USERAGENT=>'BitchinKitchen Recipe Importer/1.0',CURLOPT_RESOLVE=>[$host.':443:'.$ip],CURLOPT_HEADERFUNCTION=>function($ch,$line)use(&$headers){$headers[]=$line;return strlen($line);},CURLOPT_WRITEFUNCTION=>function($ch,$chunk)use(&$body){$body.=$chunk;return strlen($body)>5_000_000?0:strlen($chunk);}]);$ok=curl_exec($ch);$status=curl_getinfo($ch,CURLINFO_RESPONSE_CODE);$type=(string)curl_getinfo($ch,CURLINFO_CONTENT_TYPE);$error=curl_error($ch);curl_close($ch);if($ok===false)throw new RuntimeException($error?:'The recipe page could not be downloaded.');
            if(in_array($status,[301,302,303,307,308],true)){$location='';foreach($headers as $header)if(str_starts_with(strtolower($header),'location:'))$location=trim(substr($header,9));if(!$location)throw new RuntimeException('The recipe page returned an invalid redirect.');if(str_starts_with($location,'/'))$location='https://'.$host.$location;$url=$location;continue;}
            if($status!==200||!str_contains(strtolower($type),'text/html'))throw new RuntimeException('The URL did not return a supported recipe page.');return $body;}
        throw new RuntimeException('The recipe page redirected too many times.');
    }
    private static function findRecipe(array $value): ?array {$type=$value['@type']??null;if($type==='Recipe'||(is_array($type)&&in_array('Recipe',$type,true)))return $value;foreach($value as $child)if(is_array($child)&&($found=self::findRecipe($child)))return $found;return null;}
    private static function instructions(mixed $value): array {$out=[];foreach((array)$value as $step){if(is_string($step))$out[]=self::text($step);elseif(is_array($step)){if(isset($step['itemListElement']))$out=array_merge($out,self::instructions($step['itemListElement']));elseif(!empty($step['text']))$out[]=self::text($step['text']);}}return array_values(array_filter($out));}
    private static function text(mixed $value): string {return trim(preg_replace('/\s+/u',' ',html_entity_decode(strip_tags((string)$value),ENT_QUOTES|ENT_HTML5,'UTF-8')));}
}
