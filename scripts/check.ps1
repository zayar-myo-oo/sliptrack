param([string]$FlutterRoot = (Join-Path $PSScriptRoot '..\.tooling\flutter'))
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sdkRoot = (Resolve-Path $FlutterRoot).Path
$dartPath = Join-Path $sdkRoot 'bin\cache\dart-sdk\bin\dart.exe'
$snapshotPath = Join-Path $sdkRoot 'bin\cache\flutter_tools.snapshot'
# Flutter 3.47 native-assets hooks on Windows can lose quotes around a Dart
# executable path containing spaces. Launch that executable through its 8.3 path.
if (-not ('SlipTrack.ShortPaths' -as [type])) {
    Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace SlipTrack {
  public static class ShortPaths {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern uint GetShortPathName(string path, StringBuilder output, uint length);
  }
}
'@
}
$shortName = [System.Text.StringBuilder]::new(32768)
if ([SlipTrack.ShortPaths]::GetShortPathName($dartPath, $shortName, 32768) -gt 0) { $dartPath = $shortName.ToString() }
Push-Location $projectRoot
try {
    & $dartPath $snapshotPath analyze
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $dartPath $snapshotPath test
    exit $LASTEXITCODE
} finally { Pop-Location }
