<?php try{$user=App\Auth::user();}catch(Throwable){$user=null;}$flashes=$_SESSION['_flash']??[];unset($_SESSION['_flash']); ?>
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title><?=e(App\Env::get('APP_NAME',"Bitchin' Kitchen"))?></title><link rel="stylesheet" href="/assets/app.css"><script defer src="/assets/app.js"></script></head>
<body><header><a class="brand" href="/"><span>🥧</span> <?=e(App\Env::get('APP_NAME',"Bitchin' Kitchen"))?></a><nav>
<?php if($user): ?>
<a href="/?mine=1">My recipes</a><a class="button small" href="/recipes/new">＋ New recipe</a>
<?php if(in_array($user['role'],['admin','superadmin'],true)):?><a href="/?all=1">All recipes</a><a href="/admin/users">Users</a><?php endif?><?php if($user['role']==='superadmin'):?><a href="/admin/settings">Settings</a><?php endif?>
<form method="post" action="/logout"><?=csrf()?><button class="link">Sign out</button></form>
<?php endif?>
<button type="button" class="theme" aria-label="Change color theme" title="Theme">◐</button></nav></header>
<main><?php foreach($flashes as [$type,$message]):?><div class="flash <?=$type?>"><?=e($message)?></div><?php endforeach?><?=$content?></main>
<footer>Made with a pinch of joy and a lot of butter. <a href="https://github.com/DLTaylor02/BitchinKitchen" target="_blank" rel="noopener noreferrer">View on GitHub</a></footer></body></html>
