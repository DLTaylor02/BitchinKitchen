<div class="narrow"><section class="panel"><p class="eyebrow">ACCOUNT SECURITY</p><h1><?=$mustChange?'Choose a new password':'Change password'?></h1>
<?php if($mustChange):?><p class="password-change-note">An administrator has required you to choose a new password before continuing.</p><?php endif?>
<form method="post" action="/account/password" class="stack"><?=csrf()?>
<label>Current password<input type="password" name="current_password" required autocomplete="current-password"></label>
<label>New password<input type="password" name="password" minlength="<?=$passwordExempt?1:$passwordPolicy['min_length']?>" required autocomplete="new-password" <?php if(!$passwordExempt):?>data-password-meter data-min-length="<?=$passwordPolicy['min_length']?>" data-min-strength="<?=e($passwordPolicy['strength'])?>"<?php endif?>></label>
<label>Confirm new password<input type="password" name="password_confirmation" minlength="<?=$passwordExempt?1:$passwordPolicy['min_length']?>" required autocomplete="new-password"></label>
<button>Change password</button>
</form></section></div>
