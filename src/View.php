<?php
namespace App;
final class View {
    public static function render(string $name, array $data=[]): void {
        extract($data); ob_start(); require dirname(__DIR__).'/views/'.$name.'.php'; $content=ob_get_clean(); require dirname(__DIR__).'/views/layout.php';
    }
}
