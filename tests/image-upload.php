<?php
declare(strict_types=1);
require __DIR__.'/../src/ImageUpload.php';
use App\ImageUpload;

function check(bool $ok, string $message): void {
    if (!$ok) throw new RuntimeException($message);
}
function rejects(callable $action, string $message): void {
    try { $action(); } catch (RuntimeException $error) {
        check(str_contains($error->getMessage(), $message), 'Unexpected rejection: '.$error->getMessage());
        return;
    }
    throw new RuntimeException('Expected rejection: '.$message);
}
check(extension_loaded('gd') && extension_loaded('exif'), 'GD and EXIF are required');
$directory = sys_get_temp_dir().'/kitchen-image-test-'.bin2hex(random_bytes(8));
mkdir($directory);
try {
    foreach ([UPLOAD_ERR_INI_SIZE,UPLOAD_ERR_FORM_SIZE,UPLOAD_ERR_PARTIAL,UPLOAD_ERR_NO_TMP_DIR,UPLOAD_ERR_CANT_WRITE,UPLOAD_ERR_EXTENSION,99] as $code) {
        check(ImageUpload::errorMessage($code, 8) !== null, 'Upload error was silently ignored');
        rejects(fn()=>ImageUpload::receive(['error'=>$code], $directory, 8), ImageUpload::errorMessage($code, 8));
    }
    check(ImageUpload::receive(['error'=>UPLOAD_ERR_NO_FILE], $directory, 8) === null, 'Empty optional input should be ignored');
    rejects(fn()=>ImageUpload::receive(['error'=>0,'size'=>9*1024*1024], $directory, 8), 'larger than 8 MB');
    rejects(fn()=>ImageUpload::receive(['error'=>0,'tmp_name'=>'missing'], $directory, 8), 'unavailable');
    check(ImageUpload::iniBytes('32M') === 33554432, 'Request size conversion failed');

    // Four distinct corners make mirror/rotation mistakes visible in every orientation.
    $source = imagecreatetruecolor(80, 40);
    $colors = [0xff0000,0x00ff00,0x0000ff,0xffff00];
    imagefilledrectangle($source,0,0,39,19,$colors[0]);
    imagefilledrectangle($source,40,0,79,19,$colors[1]);
    imagefilledrectangle($source,0,20,39,39,$colors[2]);
    imagefilledrectangle($source,40,20,79,39,$colors[3]);
    ob_start(); imagejpeg($source,null,100); $jpeg = ob_get_clean(); imagedestroy($source);
    $expected = [1=>[0,1,2,3],2=>[1,0,3,2],3=>[3,2,1,0],4=>[2,3,0,1],5=>[0,2,1,3],6=>[2,0,3,1],7=>[3,1,2,0],8=>[1,3,0,2]];
    foreach ($expected as $orientation=>$corners) {
        // Little-endian TIFF IFD containing the EXIF orientation tag (0x0112).
        $exif = "Exif\0\0II".pack('vVv',42,8,1).pack('vvVvvV',0x112,3,1,$orientation,0,0);
        $input = $directory.'/input.jpg';
        file_put_contents($input,substr($jpeg,0,2)."\xff\xe1".pack('n',strlen($exif)+2).$exif.substr($jpeg,2));
        $output = $directory.'/'.ImageUpload::store($input,$directory,40);
        $image = imagecreatefromjpeg($output);
        $w = imagesx($image); $h = imagesy($image);
        check($w === ($orientation>=5?20:40) && $h === ($orientation>=5?40:20), "Wrong dimensions for orientation $orientation");
        foreach ([[3,3],[$w-4,3],[3,$h-4],[$w-4,$h-4]] as $i=>[$x,$y]) {
            $actual = imagecolorat($image,$x,$y);
            $target = $colors[$corners[$i]];
            foreach ([0,8,16] as $shift) check(abs((($actual>>$shift)&255)-(($target>>$shift)&255))<35, "Wrong corner $i for orientation $orientation");
        }
        $metadata = @exif_read_data($output);
        check(!isset($metadata['Orientation']), 'Output retained stale orientation');
        imagedestroy($image);
    }
    file_put_contents($input,$jpeg);
    check(is_file($directory.'/'.ImageUpload::store($input,$directory)), 'JPEG without EXIF failed');
    rejects(fn()=>ImageUpload::store($input,$directory.'/missing'), 'could not save');
    file_put_contents($directory.'/invalid','not an image');
    rejects(fn()=>ImageUpload::store($directory.'/invalid',$directory), 'Unsupported image format');
    file_put_contents($directory.'/broken.jpg',substr($jpeg,0,20));
    rejects(fn()=>ImageUpload::store($directory.'/broken.jpg',$directory), 'damaged or unreadable');
    $png = imagecreatetruecolor(10,10);
    imagealphablending($png,false); imagesavealpha($png,true);
    imagefill($png,0,0,imagecolorallocatealpha($png,0,0,0,127));
    imagepng($png,$directory.'/transparent.png'); imagedestroy($png);
    $output = ImageUpload::store($directory.'/transparent.png',$directory);
    $png = imagecreatefrompng($directory.'/'.$output);
    check((imagecolorat($png,0,0)>>24) === 127,'PNG transparency was lost');
    imagedestroy($png);
    $pngBytes=file_get_contents($directory.'/transparent.png');
    $header=pack('NN',10000,5000).substr($pngBytes,24,5);
    file_put_contents($directory.'/huge.png',substr($pngBytes,0,16).$header.pack('N',crc32('IHDR'.$header)).substr($pngBytes,33));
    rejects(fn()=>ImageUpload::store($directory.'/huge.png',$directory), '40 megapixels');
    echo "Image upload regression checks passed.\n";
} finally {
    foreach (glob($directory.'/*') as $file) unlink($file);
    rmdir($directory);
}
