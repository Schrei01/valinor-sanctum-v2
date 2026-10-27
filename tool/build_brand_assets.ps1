#requires -Version 7.0
# Genera recursos nativos a partir del logo original, sin redibujar la marca.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot 'assets/branding/valinor-original.png'
$logo = Join-Path $projectRoot 'assets/branding/valinor-logo.png'
$icon = Join-Path $projectRoot 'windows/runner/resources/app_icon.ico'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Falta el logo original de Valinor.' }
Add-Type -AssemblyName System.Drawing
$runtime = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
$references = @(
    [object].Assembly.Location,
    [System.Drawing.Bitmap].Assembly.Location,
    [System.Drawing.Color].Assembly.Location,
    (Join-Path $runtime 'System.Runtime.dll'),
    (Join-Path $runtime 'System.Runtime.InteropServices.dll'),
    (Join-Path $runtime 'System.Collections.dll')
)
$drawingRoot = Split-Path -Parent ([System.Drawing.Bitmap].Assembly.Location)
$references += @(Get-ChildItem -LiteralPath $drawingRoot -Filter 'System.Private.Windows*.dll' | ForEach-Object FullName)
if (-not ('Valinor.BrandAssets' -as [type])) {
Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
namespace Valinor {
public static class BrandAssets {
    static Bitmap Draw(Bitmap source, Rectangle crop, int width, int height, int padding) {
        var target = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(target)) {
            graphics.Clear(Color.White);
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            float scale = Math.Min((width - 2f * padding) / crop.Width, (height - 2f * padding) / crop.Height);
            float w = crop.Width * scale, h = crop.Height * scale;
            graphics.DrawImage(source, new RectangleF((width-w)/2, (height-h)/2, w, h), crop, GraphicsUnit.Pixel);
        }
        return target;
    }
    public static void Build(string sourcePath, string logoPath, string iconPath) {
        using (var source = new Bitmap(sourcePath)) {
            var bounds = new Rectangle(0, 0, source.Width, source.Height);
            var locked = source.LockBits(bounds, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            int left = source.Width, top = source.Height, right = -1, bottom = -1;
            try {
                if (locked.Stride <= 0) throw new InvalidOperationException("Unsupported bitmap stride");
                var bytes = new byte[locked.Stride * source.Height];
                Marshal.Copy(locked.Scan0, bytes, 0, bytes.Length);
                for (int y = 0; y < source.Height; y++) for (int x = 0; x < source.Width; x++) {
                    int p = y * locked.Stride + x * 4;
                    if (bytes[p+3] > 0 && (bytes[p] < 245 || bytes[p+1] < 245 || bytes[p+2] < 245)) {
                        left = Math.Min(left,x); right = Math.Max(right,x);
                        top = Math.Min(top,y); bottom = Math.Max(bottom,y);
                    }
                }
            } finally { source.UnlockBits(locked); }
            if (right < left) throw new InvalidOperationException("The logo has no visible content");
            // Remove only the outer blank margin; retain every part of the mark.
            int margin = Math.Max(right-left+1,bottom-top+1)/100;
            left = Math.Max(0,left-margin); top = Math.Max(0,top-margin);
            right = Math.Min(source.Width-1,right+margin); bottom = Math.Min(source.Height-1,bottom+margin);
            var crop = Rectangle.FromLTRB(left, top, right+1, bottom+1);
            using (var image = Draw(source,crop,512,Math.Max(1,(int)Math.Round(512d*crop.Height/crop.Width)),0)) {
                image.Save(logoPath,ImageFormat.Png);
            }
            var sizes = new int[] {16,20,24,32,40,48,64,128,256};
            var frames = new byte[sizes.Length][];
            for (int i = 0; i < sizes.Length; i++) using (var image = Draw(source,crop,sizes[i],sizes[i],Math.Max(1,sizes[i]/32)))
                using (var stream = new MemoryStream()) {
                    image.Save(stream,ImageFormat.Png); frames[i] = stream.ToArray();
                }
            using (var stream = File.Create(iconPath)) using (var writer = new BinaryWriter(stream)) {
                writer.Write((ushort)0); writer.Write((ushort)1); writer.Write((ushort)sizes.Length);
                int offset = 6 + 16 * sizes.Length;
                for (int i = 0; i < sizes.Length; i++) {
                    writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                    writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                    writer.Write((byte)0); writer.Write((byte)0); writer.Write((ushort)1); writer.Write((ushort)32);
                    writer.Write(frames[i].Length); writer.Write(offset); offset += frames[i].Length;
                }
                foreach (var frame in frames) writer.Write(frame);
            }
        }
    }
}
}
'@
}
[Valinor.BrandAssets]::Build($source,$logo,$icon)
[pscustomobject]@{logo=$logo;icon=$icon;frames=9;sourceSha256=(Get-FileHash -LiteralPath $source).Hash} | ConvertTo-Json
