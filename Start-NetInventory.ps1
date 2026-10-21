# Start-NetInventory.ps1 — точка входа Network Inventory (Windows PowerShell 5.1, WPF)
param([switch]$NoRelaunch)

$ErrorActionPreference = 'Stop'

# WPF требует однопоточного апартамента (STA)
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA' -and -not $NoRelaunch) {
    $exe = Join-Path $PSHOME 'powershell.exe'
    Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $PSCommandPath), '-NoRelaunch') -WindowStyle Hidden
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$script:RootDir = $PSScriptRoot
$script:SrcDir  = Join-Path $PSScriptRoot 'src'

try {
    foreach ($f in @('Common', 'Collector', 'Storage', 'Scanner', 'Software', 'Changes', 'Reports', 'Alerts', 'CardView', 'Export', 'Types', 'Icons')) {
        . (Join-Path $script:SrcDir ($f + '.ps1'))
    }
    foreach ($f in @('Dialogs', 'Main', 'Main.Scanner', 'Main.View', 'Main.Software', 'Main.Changes', 'Main.App')) {
        . (Join-Path (Join-Path $PSScriptRoot 'ui') ($f + '.ps1'))
    }
    $ErrorActionPreference = 'Continue'
    [void](Load-Settings)
    Start-App
}
catch {
    $msg = $_.Exception.Message
    if ($_.InvocationInfo) { $msg += "`n`n" + $_.InvocationInfo.PositionMessage }
    try {
        $dir = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'NetInventory'
        if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        Add-Content -Path (Join-Path $dir 'app.log') -Value ('{0}  FATAL: {1}' -f (Get-Date), $msg) -Encoding UTF8
    } catch { }
    [System.Windows.MessageBox]::Show($msg, 'Network Inventory — ошибка запуска', 'OK', 'Error') | Out-Null
}
