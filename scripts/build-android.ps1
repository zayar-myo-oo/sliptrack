param(
    [string]$FlutterRoot = (Join-Path $PSScriptRoot '..\.tooling\flutter'),
    [string]$AndroidSdk = (Join-Path $PSScriptRoot '..\.tooling\android-sdk'),
    [string]$JdkRoot = $env:JAVA_HOME,
    [ValidateSet('debug','release')][string]$BuildMode = 'debug'
)
$ErrorActionPreference = 'Stop'
if (-not $JdkRoot) {
    $candidate = Get-ChildItem -LiteralPath (Join-Path $env:ProgramFiles 'Eclipse Adoptium') -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidate) { $JdkRoot = $candidate.FullName }
}
if (-not $JdkRoot -or -not (Test-Path -LiteralPath (Join-Path $JdkRoot 'bin\java.exe'))) { throw 'Provide -JdkRoot pointing to JDK 17.' }
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
function Get-ShortBuildPath([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $buffer = [System.Text.StringBuilder]::new(32768)
    if ([SlipTrack.ShortPaths]::GetShortPathName($resolved, $buffer, 32768) -gt 0) { return $buffer.ToString() }
    return $resolved
}
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sdkRoot = Get-ShortBuildPath $FlutterRoot
$tempRoot = Join-Path $projectRoot '.tooling\t'
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$tempRoot = Get-ShortBuildPath $tempRoot
$environmentNames = @('ANDROID_HOME','ANDROID_SDK_ROOT','JAVA_HOME','JAVA_TOOL_OPTIONS','GRADLE_USER_HOME','TEMP','TMP')
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
Push-Location $projectRoot
try {
    $env:ANDROID_HOME = Get-ShortBuildPath $AndroidSdk
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
    $env:JAVA_HOME = $JdkRoot
    $env:JAVA_TOOL_OPTIONS = "$($savedEnvironment['JAVA_TOOL_OPTIONS']) -Djava.net.preferIPv4Stack=true -Djava.io.tmpdir=$tempRoot"
    $env:GRADLE_USER_HOME = Join-Path $projectRoot '.tooling\gradle'
    $env:TEMP = $tempRoot
    $env:TMP = $tempRoot
    & (Join-Path $sdkRoot 'bin\cache\dart-sdk\bin\dart.exe') (Join-Path $sdkRoot 'bin\cache\flutter_tools.snapshot') build apk "--$BuildMode"
    exit $LASTEXITCODE
} finally {
    Pop-Location
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
}
