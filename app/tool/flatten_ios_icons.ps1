# Apple rejects app icons that contain an alpha channel, so re-save them as opaque RGB.
Add-Type -AssemblyName System.Drawing
$folder = Join-Path $PSScriptRoot '..\ios\Runner\Assets.xcassets\AppIcon.appiconset'
Get-ChildItem $folder -Filter '*.png' | ForEach-Object {
    $source = [System.Drawing.Image]::FromFile($_.FullName)
    $flat = New-Object System.Drawing.Bitmap($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($flat)
    $graphics.DrawImage($source, 0, 0, $source.Width, $source.Height)
    $graphics.Dispose()
    $source.Dispose()
    $flat.Save($_.FullName, [System.Drawing.Imaging.ImageFormat]::Png)
    $flat.Dispose()
}
