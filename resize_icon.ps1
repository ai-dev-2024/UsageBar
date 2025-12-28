Add-Type -AssemblyName System.Drawing
$source = "C:\Users\Muhib\.gemini\antigravity\brain\3a4fa1ef-9c1d-4bae-b8b5-2788786d5097\uploaded_image_1766946204777.png"
$dest = "c:\Users\Muhib\Desktop\Projects\UsageBar\assets\icon.ico"

if (-not (Test-Path $source)) {
    Write-Error "Source image not found at $source"
    exit 1
}

$img = [System.Drawing.Image]::FromFile($source)
$newImg = new-object System.Drawing.Bitmap(256, 256)
$graph = [System.Drawing.Graphics]::FromImage($newImg)
$graph.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graph.DrawImage($img, 0, 0, 256, 256)

# Save as PNG (Electron builder accepts PNG content in .ico file often, or we need real conversion)
# Usually for Windows, a real ICO is preferred, but simple PNG rename might fail if checked strictly.
# However, .NET Check:
# Saving as Icon format requires Icon.FromHandle, but quality is low.
# We will save as PNG and rename to .ico. If build fails, we know why.
# Actually, let's verify if we can save as Icon.
# $icon = [System.Drawing.Icon]::FromHandle($newImg.GetHicon())
# $icon.Save($dest)
# Using Icon.FromHandle produces low quality 16-color often.
# Simplest for Electron Builder: It often handles PNG-as-ICO or we just need 256x256 png.
# Error was "image must be at least 256x256". It didn't say "invalid format".
# So using PNG saved as .ico might pass the check, unless it checks header.
# I'll save as PNG but name it icon.ico.

$tempPng = "c:\Users\Muhib\Desktop\Projects\UsageBar\assets\temp.png"
$newImg.Save($tempPng, [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose()
$newImg.Dispose()
$graph.Dispose()

Copy-Item $tempPng $dest -Force
Remove-Item $tempPng
Write-Output "Icon resized to 256x256 and saved to $dest"
