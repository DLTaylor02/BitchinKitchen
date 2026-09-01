<?php
use App\{Csrf,Database,Env,View};
$installed=false;
try{$installed=(bool)Database::connection()->query("SELECT value FROM settings WHERE key='installed_at'")->fetchColumn();}catch(Throwable){}
if($installed){ http_response_code(403);View::render('error',['code'=>403,'message'=>'The kitchen is already installed.']);return; }
if($_SERVER['REQUEST_METHOD']==='POST'){
    Csrf::verify(); $name=trim($_POST['name']??'');$email=trim($_POST['email']??'');$password=$_POST['password']??'';
    if(!$name||!filter_var($email,FILTER_VALIDATE_EMAIL)||strlen($password)<12){flash('Provide a name, valid email, and a password of at least 12 characters.','error');redirect('/install');}
    try{$pdo=Database::connection();$pdo->beginTransaction();$pdo->exec(file_get_contents(dirname(__DIR__).'/database/schema.sql'));$q=$pdo->prepare("INSERT INTO users(name,email,password_hash,role)VALUES(?,?,?,'superadmin')");$q->execute([$name,$email,password_hash($password,PASSWORD_DEFAULT)]);$q=$pdo->prepare("INSERT INTO settings(key,value)VALUES('installed_at',?)");$q->execute([date(DATE_ATOM)]);$pdo->commit();flash('Kitchen installed! Sign in with your superadmin account.');redirect('/login');}catch(Throwable $e){if(isset($pdo)&&$pdo->inTransaction())$pdo->rollBack();$error=Env::get('APP_DEBUG','false')==='true'?$e->getMessage():'Could not install. Check the database settings.';}
}
View::render('install',['error'=>$error??null]);
