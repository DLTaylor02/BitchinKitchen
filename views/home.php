<section class="hero">
    <p class="eyebrow">COOK · SHARE · MAKE IT YOURS</p>
    <h1>What’s cooking?</h1>
    <p>Find a favorite, then remix it into something unmistakably yours.</p>
    <form class="filter-form" method="get">
        <div class="search"><input type="search" name="q" value="<?=e($query)?>" placeholder="Search recipes or ingredients…" autofocus><button>Search</button></div>
        <?php if($mine):?><input type="hidden" name="mine" value="1"><?php elseif($all):?><input type="hidden" name="all" value="1"><?php endif?>
        <div class="filter-row">
            <label>Cuisine<select name="cuisine"><option value="">All cuisines</option><?php foreach($cuisines as $c):?><option value="<?=$c['id']?>" <?=$cuisineId===(int)$c['id']?'selected':''?>><?=e($c['name'])?></option><?php endforeach?></select></label>
            <details class="filter-tags"><summary>Tags<?php if($filterTags):?> <b><?=count($filterTags)?> selected</b><?php endif?><small>Matches all selected</small></summary><div><?php foreach($tags as $tag):?><label><input type="checkbox" name="tags[]" value="<?=$tag['id']?>" <?=in_array((int)$tag['id'],$filterTags,true)?'checked':''?>><span><?=e($tag['name'])?></span></label><?php endforeach?></div></details>
            <button class="secondary">Apply filters</button>
            <?php if($query||$cuisineId||$filterTags):?><a href="<?=$favorites?'/favorites':($all?'/?all=1':($mine?'/?mine=1':'/'))?>">Clear</a><?php endif?>
        </div>
    </form>
</section>
<div class="section-head"><h2><?=$favorites?'My Favorites':($all?'All recipes':($mine?'My recipe box':($query?'Search results':'Fresh from the community')))?></h2><span data-total="<?=$total?>"><?=$total?> <?=$total===1?'recipe':'recipes'?></span></div>
<?php if(!$recipes):?>
    <div class="empty"><div>🧁</div><h2>No crumbs here yet</h2><p><?=$favorites?'Favorite a recipe and it will appear here.':($query?'Try another search.':'Create the first delicious recipe.')?></p></div>
<?php else:?>
    <div class="grid"><?php foreach($recipes as $r):?>
        <article class="card">
            <div class="thumb">
                <a class="thumb-link" href="/recipes/<?=$r['id']?>" aria-label="View <?=e($r['title'])?>"><?php if($r['thumbnail']):?><img src="/uploads/<?=e($r['thumbnail'])?>" alt=""><?php else:?><span>🍪</span><?php endif?></a>
                <form class="favorite-form" method="post" action="/recipes/<?=$r['id']?>/favorite"><?=csrf()?><input type="hidden" name="return_to" value="<?=e($_SERVER['REQUEST_URI'])?>"><button class="favorite-button <?=$r['is_favorite']?'active':''?>" title="<?=$r['is_favorite']?'Remove from favorites':'Add to favorites'?>" aria-label="<?=$r['is_favorite']?'Remove from favorites':'Add to favorites'?>"><?=$r['is_favorite']?'♥':'♡'?></button></form>
                <?php if(!$r['is_public']):?><b class="privacy">Private</b><?php endif?>
            </div>
            <a class="card-body" href="/recipes/<?=$r['id']?>"><h3><?=e($r['title'])?></h3><?php if($r['cuisine_name']||$r['tag_names']):?><div class="card-labels"><?php if($r['cuisine_name']):?><span class="cuisine-label"><?=e($r['cuisine_name'])?></span><?php endif?><?php foreach(array_slice(array_filter(explode(', ',$r['tag_names']??'')),0,2) as $tag):?><span class="tag-label"><?=e($tag)?></span><?php endforeach?></div><?php endif?><p><?=e($r['summary']?:'A recipe worth sharing.')?></p><small>by <?=e($r['owner_name'])?></small></a>
        </article>
    <?php endforeach?></div>
    <?php $pageUrl=static function(int $target)use($pageSize):string{$parameters=$_GET;$parameters['page']=$target;$parameters['per_page']=$pageSize;return (parse_url($_SERVER['REQUEST_URI'],PHP_URL_PATH)?:'/').'?'.http_build_query($parameters);};?>
    <nav class="pagination" aria-label="Recipe pages">
        <div class="pagination-links"><?php if($page>1):?><a class="button small secondary" href="<?=e($pageUrl($page-1))?>">Previous</a><?php else:?><span class="button small secondary disabled">Previous</span><?php endif?><span class="pagination-status">Page <?=$page?> of <?=$totalPages?></span><?php if($page<$totalPages):?><a class="button small secondary" href="<?=e($pageUrl($page+1))?>">Next</a><?php else:?><span class="button small secondary disabled">Next</span><?php endif?></div>
        <form method="get" class="page-size-form"><?php if($query!==''):?><input type="hidden" name="q" value="<?=e($query)?>"><?php endif?><?php if($mine):?><input type="hidden" name="mine" value="1"><?php elseif($all):?><input type="hidden" name="all" value="1"><?php endif?><?php if($cuisineId):?><input type="hidden" name="cuisine" value="<?=$cuisineId?>"><?php endif?><?php foreach($filterTags as $tagId):?><input type="hidden" name="tags[]" value="<?=$tagId?>"><?php endforeach?><label>Show <select name="per_page" onchange="this.form.submit()"><option value="9" <?=$pageSize==='9'?'selected':''?>>9</option><option value="18" <?=$pageSize==='18'?'selected':''?>>18</option><option value="36" <?=$pageSize==='36'?'selected':''?>>36</option><option value="60" <?=$pageSize==='60'?'selected':''?>>60</option><option value="all" <?=$pageSize==='all'?'selected':''?>>All</option></select></label><noscript><button class="small secondary">Apply</button></noscript></form>
    </nav>
<?php endif?>
