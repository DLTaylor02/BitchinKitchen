<?php
declare(strict_types=1);

namespace App;

use GdImage;
use RuntimeException;

final class ImageUpload
{
    private const FORMATS = ['image/jpeg'=>'jpg', 'image/png'=>'png', 'image/webp'=>'webp', 'image/gif'=>'gif'];

    public static function errorMessage(int $error, int $maxMb): ?string
    {
        return match ($error) {
            UPLOAD_ERR_OK, UPLOAD_ERR_NO_FILE => null,
            UPLOAD_ERR_INI_SIZE => "The image exceeds the server's per-file upload limit. Choose a smaller image (up to $maxMb MB).",
            UPLOAD_ERR_FORM_SIZE => "The image exceeds the form's upload limit. Choose a smaller image (up to $maxMb MB).",
            UPLOAD_ERR_PARTIAL => 'The upload was interrupted. Please select the image and try again.',
            UPLOAD_ERR_NO_TMP_DIR, UPLOAD_ERR_CANT_WRITE => 'The server could not store the upload. Please try again or contact the administrator.',
            UPLOAD_ERR_EXTENSION => 'The server stopped this upload. Please contact the administrator.',
            default => 'The upload failed. Please select the image and try again.',
        };
    }

    public static function receive(array $file, string $directory, int $maxMb, int $maxDimension = 1000): ?string
    {
        $error = (int)($file['error'] ?? -1);
        if ($message = self::errorMessage($error, $maxMb)) {
            throw new RuntimeException($message);
        }
        if ($error === UPLOAD_ERR_NO_FILE) return null;
        if ((int)($file['size'] ?? 0) > $maxMb * 1024 * 1024) {
            throw new RuntimeException("The image is larger than $maxMb MB. Choose a smaller image.");
        }
        $tmp = $file['tmp_name'] ?? '';
        if (!is_string($tmp) || !is_uploaded_file($tmp)) {
            throw new RuntimeException('The uploaded image is unavailable. Please select it and try again.');
        }
        return self::store($tmp, $directory, $maxDimension);
    }

    public static function iniBytes(string $value): int
    {
        $value = trim($value);
        $factor = match (strtolower(substr($value, -1))) { 'g'=>1073741824, 'm'=>1048576, 'k'=>1024, default=>1 };
        return (int)((float)$value * $factor);
    }

    public static function store(string $tmp, string $directory, int $maxDimension = 1000): string
    {
        $mime = (new \finfo(FILEINFO_MIME_TYPE))->file($tmp);
        if (!isset(self::FORMATS[$mime])) {
            throw new RuntimeException('Unsupported image format. Choose a JPEG, PNG, WebP, or GIF image.');
        }
        if (!function_exists('imagecreatefromstring') || ($mime === 'image/jpeg' && !function_exists('exif_read_data'))) {
            throw new RuntimeException('Image processing is unavailable on the server. Please contact the administrator.');
        }
        $size = @getimagesize($tmp);
        if (!$size || $size[0] < 1 || $size[1] < 1) {
            throw new RuntimeException('The image is damaged or unreadable. Try exporting it again.');
        }
        if ($size[0] * $size[1] > 40000000) {
            throw new RuntimeException('The image exceeds 40 megapixels. Reduce its dimensions and try again.');
        }
        $scale = min(1, $maxDimension / max($size[0], $size[1]));
        $width = max(1, (int)round($size[0] * $scale));
        $height = max(1, (int)round($size[1] * $scale));
        // Reject before decoding if the estimated working set exceeds available PHP memory.
        $budget = self::iniBytes((string)ini_get('memory_limit'));
        $estimate = $size[0] * $size[1] * 8 + $width * $height * 12 + (int)filesize($tmp) * 2 + 16 * 1024 * 1024;
        if ($budget > 0 && $estimate > $budget - memory_get_usage(true)) {
            throw new RuntimeException('The image is too large to process on this server. Reduce its dimensions and try again.');
        }
        $source = @imagecreatefromstring((string)file_get_contents($tmp));
        if (!$source) throw new RuntimeException('The image is damaged or unreadable. Try exporting it again.');
        $output = null;
        $path = null;
        try {
            $output = imagecreatetruecolor($width, $height);
            if (!$output) throw new RuntimeException('The image could not be processed. Try a smaller image.');
            if ($mime !== 'image/jpeg') {
                imagealphablending($output, false);
                imagesavealpha($output, true);
                imagefill($output, 0, 0, imagecolorallocatealpha($output, 0, 0, 0, 127));
            }
            if (!imagecopyresampled($output, $source, 0, 0, 0, 0, $width, $height, $size[0], $size[1])) {
                throw new RuntimeException('The image could not be resized. Try exporting it again.');
            }
            if ($mime === 'image/jpeg') {
                $exif = @exif_read_data($tmp, 'IFD0', true);
                // Missing or malformed orientation is treated as an ordinary, upright image.
                $orientation = $exif['IFD0']['Orientation'] ?? 1;
                $output = self::orient($output, is_numeric($orientation) ? (int)$orientation : 1);
            }
            $name = bin2hex(random_bytes(16)).'.'.self::FORMATS[$mime];
            $path = $directory.'/'.$name;
            $saved = match ($mime) {
                'image/jpeg' => function_exists('imagejpeg') && @imagejpeg($output, $path, 82),
                'image/png' => function_exists('imagepng') && @imagepng($output, $path, 6),
                'image/webp' => function_exists('imagewebp') && @imagewebp($output, $path, 82),
                'image/gif' => function_exists('imagegif') && @imagegif($output, $path),
            };
            if (!$saved || !is_file($path) || filesize($path) === 0) {
                throw new RuntimeException('The server could not save the image. Please try again or contact the administrator.');
            }
            return $name;
        } catch (\Throwable $error) {
            if ($path !== null) @unlink($path);
            throw $error;
        } finally {
            imagedestroy($source);
            if ($output instanceof GdImage) imagedestroy($output);
        }
    }

    private static function orient(GdImage $image, int $orientation): GdImage
    {
        $angle = match ($orientation) { 3=>180, 5,6,7=>-90, 8=>90, default=>0 };
        if ($angle !== 0) {
            $rotated = imagerotate($image, $angle, 0);
            if (!$rotated) throw new RuntimeException('The image could not be rotated. Try exporting it again.');
            imagedestroy($image);
            $image = $rotated;
        }
        $flip = match ($orientation) { 2,5=>IMG_FLIP_HORIZONTAL, 4,7=>IMG_FLIP_VERTICAL, default=>null };
        if ($flip !== null) imageflip($image, $flip);
        return $image;
    }
}
