<div class="section-head"><div><p class="eyebrow">ADMINISTRATION</p><h1>Kitchen crew</h1></div><span><?=count($users)?> people</span></div>

<section class="panel admin-create"><h2>Create user</h2><form method="post" action="/admin/users" class="admin-create-form"><?=csrf()?>
<label>Username<input name="name" minlength="2" maxlength="100" required autocomplete="off"></label>
<label>Initial password<input type="password" name="password" minlength="<?=$passwordPolicy['min_length']?>" required autocomplete="new-password" data-password-meter data-min-length="<?=$passwordPolicy['min_length']?>" data-min-strength="<?=e($passwordPolicy['strength'])?>"></label>
<label>Role<select name="role"><option value="user">User</option><option value="admin">Web Admin</option></select></label>
<button>Create user</button></form></section>

<div class="user-list"><?php foreach($users as $managed):?>
<article class="panel user-row"><div class="user-identity"><h3><?=e($managed['name'])?></h3><small>Joined <?=date('M j, Y',strtotime($managed['created_at']))?></small><?php if($managed['must_change_password']):?><span class="badge password-required">Password change required</span><?php endif?></div>
<div class="user-controls">
<?php if($managed['role']==='superadmin'):?><span class="badge">Superadmin</span>
<?php elseif((int)$managed['id']===(int)$current['id']):?><span class="badge"><?=e($managed['role'])?></span>
<?php else:?><form method="post" action="/admin/users/<?=$managed['id']?>/role" class="inline"><?=csrf()?><select name="role" aria-label="Role for <?=e($managed['name'])?>"><option value="user" <?=$managed['role']==='user'?'selected':''?>>User</option><option value="admin" <?=$managed['role']==='admin'?'selected':''?>>Web Admin</option></select><button class="small">Change role</button></form><?php endif?>
<?php if($managed['role']!=='superadmin'||($current['role']==='superadmin'&&(int)$managed['id']===(int)$current['id'])):?><form method="post" action="/admin/users/<?=$managed['id']?>/password" class="inline password-reset"><?=csrf()?><input type="password" name="password" minlength="<?=$managed['role']==='superadmin'?1:$passwordPolicy['min_length']?>" required autocomplete="new-password" placeholder="New password" aria-label="New password for <?=e($managed['name'])?>" <?php if($managed['role']!=='superadmin'):?>data-password-meter data-min-length="<?=$passwordPolicy['min_length']?>" data-min-strength="<?=e($passwordPolicy['strength'])?>"<?php endif?>><button class="small secondary">Set password</button></form><?php endif?>
<?php if($managed['role']!=='superadmin'):?><form method="post" action="/admin/users/<?=$managed['id']?>/must-change" class="inline"><?=csrf()?><?php if(!$managed['must_change_password']):?><input type="hidden" name="required" value="1"><?php endif?><button class="small secondary"><?=$managed['must_change_password']?'Clear requirement':'Require password change'?></button></form><?php endif?>
</div></article><?php endforeach?></div>
