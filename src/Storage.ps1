# Storage.ps1 — хранилище: папки на диске, по одному JSON-файлу на устройство,
# снимки (история сканирований) — в скрытой папке .data\<Id>\<метка>.json

$script:Store = $null

function Open-Storage {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { [void](New-Item -ItemType Directory -Path $Path -Force) }
    $metaPath = Join-Path $Path 'storage.json'
    $meta = Read-JsonFile $metaPath
    if (-not $meta) {
        $meta = @{ Name = (Split-Path $Path -Leaf); Created = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss'); Format = 1 }
        Write-JsonFile $metaPath $meta
    }
    $dataDir = Join-Path $Path '.data'
    if (-not (Test-Path -LiteralPath $dataDir)) {
        $di = New-Item -ItemType Directory -Path $dataDir -Force
        try { $di.Attributes = $di.Attributes -bor [System.IO.FileAttributes]::Hidden } catch { }
    }
    $script:Store = @{
        Root     = (Resolve-Path -LiteralPath $Path).ProviderPath
        Name     = [string](Get-Val $meta 'Name')
        Meta     = $meta
        Devices  = New-Object System.Collections.ArrayList
        Folders  = New-Object System.Collections.ArrayList
        Cache    = @{}
        Licenses = @()
    }
    Reload-Storage
    return $script:Store
}

function Close-Storage { $script:Store = $null }

function Reload-Storage {
    $st = $script:Store
    if (-not $st) { return }
    $st.Devices.Clear(); $st.Folders.Clear(); $st.Cache = @{}
    $root = $st.Root
    foreach ($d in (Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue)) {
        $rel = Get-RelativePathSimple $root $d.FullName
        if ($rel -match '(^|[\\/])\.') { continue }
        [void]$st.Folders.Add($rel)
    }
    foreach ($f in (Get-ChildItem -LiteralPath $root -Filter '*.device.json' -File -Recurse -ErrorAction SilentlyContinue)) {
        $rel = Get-RelativePathSimple $root $f.DirectoryName
        if ($rel -match '(^|[\\/])\.') { continue }
        try {
            $h = Read-JsonFile $f.FullName
            if (-not $h -or -not (Get-Val $h 'Id')) { continue }
            $h['_Path'] = $f.FullName
            $h['_Folder'] = $rel
            [void]$st.Devices.Add($h)
        } catch { }
    }
    $lic = Read-JsonFile (Join-Path $root 'licenses.json')
    if ($lic) { $st.Licenses = @(As-Array $lic) } else { $st.Licenses = @() }
}

function Save-Licenses {
    if (-not $script:Store) { return }
    Write-JsonFile (Join-Path $script:Store.Root 'licenses.json') @($script:Store.Licenses)
}

function Save-DeviceHeader {
    param($Device)
    $copy = @{}
    foreach ($k in @($Device.PSBase.Keys)) { if (-not ([string]$k).StartsWith('_')) { $copy[$k] = $Device[$k] } }
    Write-JsonFile $Device['_Path'] $copy
}

function Get-FolderFullPath {
    param([string]$RelFolder)
    if ([string]::IsNullOrEmpty($RelFolder)) { return $script:Store.Root }
    return (Join-Path $script:Store.Root $RelFolder)
}

function Get-DevicesUnder {
    param([string]$RelFolder, [switch]$Recurse = $true)
    $res = New-Object System.Collections.ArrayList
    foreach ($d in $script:Store.Devices) {
        $f = [string]$d['_Folder']
        if ([string]::IsNullOrEmpty($RelFolder)) { [void]$res.Add($d); continue }
        if ($f -eq $RelFolder -or ($Recurse -and $f.StartsWith($RelFolder + '\', [StringComparison]::OrdinalIgnoreCase)) -or ($Recurse -and $f.StartsWith($RelFolder + '/', [StringComparison]::OrdinalIgnoreCase))) {
            [void]$res.Add($d)
        }
    }
    return $res.ToArray()
}

function Get-DeviceById {
    param([string]$Id)
    foreach ($d in $script:Store.Devices) { if ($d['Id'] -eq $Id) { return $d } }
    return $null
}

function Get-DeviceTypeFromData {
    param($Data)
    $sys = Get-Val $Data 'System'
    $os  = Get-Val $Data 'OS'
    $model = ('{0} {1}' -f (Get-Val $sys 'Manufacturer'), (Get-Val $sys 'Model'))
    if ($model -match 'Virtual|VMware|VirtualBox|KVM|QEMU|Xen|Hyper-V|Parallels') { return 'Virtual' }
    $pt = Get-Val $os 'ProductType'
    if ($pt -and [int]$pt -ge 2) { return 'Server' }
    $ch = @(As-Array (Get-Val $sys 'ChassisTypes'))
    foreach ($c in $ch) { if ([int]$c -in @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)) { return 'Laptop' } }
    if (@(As-Array (Get-Val $Data 'Battery')).Count -gt 0) { return 'Laptop' }
    return 'Desktop'
}

function Get-PrimaryNetwork {
    # Возвращает @{ Ip; Mac } основного адаптера
    param($Data, [string]$PreferIp)
    $best = $null
    foreach ($n in (As-Array (Get-Val $Data 'Network'))) {
        $ips = @(As-Array (Get-Val $n 'IPs') | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
        if ($PreferIp -and $ips -contains $PreferIp) { return @{ Ip = $PreferIp; Mac = (Get-Val $n 'MAC') } }
        if (-not $best -and $ips.Count -gt 0 -and @(As-Array (Get-Val $n 'Gateways')).Count -gt 0) { $best = @{ Ip = $ips[0]; Mac = (Get-Val $n 'MAC') } }
    }
    if ($best) { return $best }
    foreach ($n in (As-Array (Get-Val $Data 'Network'))) {
        $ips = @(As-Array (Get-Val $n 'IPs') | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254' })
        if ($ips.Count -gt 0) { return @{ Ip = $ips[0]; Mac = (Get-Val $n 'MAC') } }
    }
    return @{ Ip = $PreferIp; Mac = $null }
}

function Find-MatchingDevice {
    param([string]$Hostname, [string]$Mac, [string]$Uuid)
    foreach ($d in $script:Store.Devices) {
        if ($Hostname -and $d['Hostname'] -and ([string]$d['Hostname']).Equals($Hostname, [StringComparison]::OrdinalIgnoreCase)) { return $d }
    }
    foreach ($d in $script:Store.Devices) {
        if ($Mac -and $d['Mac'] -and $d['Mac'] -eq $Mac) { return $d }
    }
    return $null
}

function Get-UniqueDevicePath {
    param([string]$FolderFull, [string]$Name)
    $base = Get-SafeFileName $Name
    $p = Join-Path $FolderFull ($base + '.device.json')
    $i = 2
    while (Test-Path -LiteralPath $p) { $p = Join-Path $FolderFull ('{0} ({1}).device.json' -f $base, $i); $i++ }
    return $p
}

function Add-DeviceSnapshot {
    # Добавляет снимок; создаёт устройство при необходимости. Возвращает заголовок устройства.
    param($Data, [string]$TargetFolder = '', [string]$ScannedAddress = '', [string]$Method = '')
    $st = $script:Store
    $sys = Get-Val $Data 'System'
    $hostname = [string](Get-Val $sys 'Name')
    if (-not $hostname) { $hostname = $ScannedAddress }
    $net = Get-PrimaryNetwork $Data $ScannedAddress
    $uuid = [string](Get-Val $sys 'Uuid')
    $now = Get-Date
    $stamp = $now.ToString('yyyyMMdd-HHmmss')

    $dev = Find-MatchingDevice $hostname ([string]$net.Mac) $uuid
    if (-not $dev) {
        $folderFull = Get-FolderFullPath $TargetFolder
        if (-not (Test-Path -LiteralPath $folderFull)) { [void](New-Item -ItemType Directory -Path $folderFull -Force) }
        $dev = @{
            Id       = (New-Id)
            Name     = $hostname
            Created  = $now.ToString('yyyy-MM-ddTHH:mm:ss')
            Snapshots = @()
            AssignedUser = ''
            Location = ''
            Note     = ''
        }
        $dev['_Path'] = Get-UniqueDevicePath $folderFull $hostname
        $dev['_Folder'] = $TargetFolder
        [void]$st.Devices.Add($dev)
    }
    $osCap = [string](Get-Val $Data 'OS' 'Caption')
    $dev['Hostname'] = $hostname
    $dev['Uuid']     = $uuid
    $dev['Ip']       = $(if ($net.Ip) { $net.Ip } else { $ScannedAddress })
    $dev['Mac']      = $net.Mac
    $dev['Type']     = Get-DeviceTypeFromData $Data
    $dev['OsName']   = $osCap
    $dev['Domain']   = [string](Get-Val $sys 'Domain')
    $dev['User']     = [string](Get-Val $sys 'UserName')
    $dev['Model']    = ('{0} {1}' -f (Get-Val $sys 'Manufacturer'), (Get-Val $sys 'Model')).Trim()
    $dev['LastScan'] = $now.ToString('yyyy-MM-ddTHH:mm:ss')
    $dev['LastMethod'] = $Method
    $dev['Online']   = $true
    $dev['LastPing'] = $now.ToString('yyyy-MM-ddTHH:mm:ss')
    $snaps = @(As-Array $dev['Snapshots']) + @($stamp)
    $dev['Snapshots'] = $snaps

    $snapPath = Join-Path (Join-Path (Join-Path $st.Root '.data') $dev['Id']) ($stamp + '.json')
    Write-JsonFile $snapPath $Data
    Save-DeviceHeader $dev
    $st.Cache[$dev['Id'] + '|' + $stamp] = (ConvertTo-PlainObject $Data)
    return $dev
}

function Get-DeviceSnapshot {
    param($Device, [string]$Stamp = '')
    if (-not $Device) { return $null }
    $snaps = @(As-Array $Device['Snapshots'])
    if ($snaps.Count -eq 0) { return $null }
    if (-not $Stamp) { $Stamp = [string]$snaps[$snaps.Count - 1] }
    $key = $Device['Id'] + '|' + $Stamp
    if ($script:Store.Cache.ContainsKey($key)) { return $script:Store.Cache[$key] }
    $p = Join-Path (Join-Path (Join-Path $script:Store.Root '.data') $Device['Id']) ($Stamp + '.json')
    $d = $null
    try { $d = Read-JsonFile $p } catch { $d = $null }
    if ($d) { $script:Store.Cache[$key] = $d }
    return $d
}

function ConvertFrom-Stamp {
    param([string]$Stamp)
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact($Stamp, 'yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { return $d }
    return $null
}

function Remove-DeviceSnapshot {
    param($Device, [string]$Stamp)
    $snaps = @(As-Array $Device['Snapshots'] | Where-Object { $_ -ne $Stamp })
    $Device['Snapshots'] = $snaps
    $p = Join-Path (Join-Path (Join-Path $script:Store.Root '.data') $Device['Id']) ($Stamp + '.json')
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    $script:Store.Cache.Remove($Device['Id'] + '|' + $Stamp)
    Save-DeviceHeader $Device
}

function Remove-StorageDevice {
    param($Device)
    if (Test-Path -LiteralPath $Device['_Path']) { Remove-Item -LiteralPath $Device['_Path'] -Force }
    $dd = Join-Path (Join-Path $script:Store.Root '.data') $Device['Id']
    if (Test-Path -LiteralPath $dd) { Remove-Item -LiteralPath $dd -Recurse -Force }
    [void]$script:Store.Devices.Remove($Device)
}

function Move-StorageDevice {
    param($Device, [string]$TargetFolder)
    $full = Get-FolderFullPath $TargetFolder
    $leaf = Split-Path $Device['_Path'] -Leaf
    $new = Join-Path $full $leaf
    if ($new -eq $Device['_Path']) { return }
    if (Test-Path -LiteralPath $new) { $new = Get-UniqueDevicePath $full ([string]$Device['Name']) }
    Move-Item -LiteralPath $Device['_Path'] -Destination $new
    $Device['_Path'] = $new
    $Device['_Folder'] = $TargetFolder
}

function Rename-StorageDevice {
    param($Device, [string]$NewName)
    $Device['Name'] = $NewName
    $dir = Split-Path $Device['_Path'] -Parent
    $new = Get-UniqueDevicePath $dir $NewName
    Move-Item -LiteralPath $Device['_Path'] -Destination $new
    $Device['_Path'] = $new
    Save-DeviceHeader $Device
}

function New-StorageFolder {
    param([string]$ParentRel, [string]$Name)
    $safe = Get-SafeFileName $Name
    $rel = $safe
    if ($ParentRel) { $rel = $ParentRel + '\' + $safe }
    $full = Get-FolderFullPath $rel
    if (-not (Test-Path -LiteralPath $full)) { [void](New-Item -ItemType Directory -Path $full -Force) }
    if (-not ($script:Store.Folders -contains $rel)) { [void]$script:Store.Folders.Add($rel) }
    return $rel
}

function Rename-StorageFolder {
    param([string]$Rel, [string]$NewName)
    $full = Get-FolderFullPath $Rel
    $safe = Get-SafeFileName $NewName
    Rename-Item -LiteralPath $full -NewName $safe
    Reload-Storage
}

function Remove-StorageFolder {
    param([string]$Rel)
    foreach ($d in @(Get-DevicesUnder $Rel)) { Remove-StorageDevice $d }
    $full = Get-FolderFullPath $Rel
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
    Reload-Storage
}

function Get-ChildFolders {
    param([string]$ParentRel)
    $res = @()
    foreach ($f in $script:Store.Folders) {
        $parent = ''
        $idx = $f.LastIndexOfAny([char[]]@('\', '/'))
        if ($idx -ge 0) { $parent = $f.Substring(0, $idx) }
        if ($parent -eq $ParentRel) { $res += $f }
    }
    return @($res | Sort-Object)
}

function Get-FolderLeaf {
    param([string]$Rel)
    $idx = $Rel.LastIndexOfAny([char[]]@('\', '/'))
    if ($idx -ge 0) { return $Rel.Substring($idx + 1) }
    return $Rel
}

function Import-SnapshotFile {
    # Импорт снимка, собранного автономным сборщиком (Collect-Offline.ps1)
    param([string]$Path, [string]$TargetFolder = '')
    $obj = Read-JsonFile $Path
    if (-not $obj) { throw 'Файл пуст или повреждён.' }
    $data = $obj
    if ((Get-Val $obj 'Data') -and (Get-Val $obj 'Format') -eq 'NetInventorySnapshot') { $data = Get-Val $obj 'Data' }
    if (-not (Get-Val $data 'System')) { throw 'Файл не похож на снимок инвентаризации.' }
    return (Add-DeviceSnapshot $data $TargetFolder '' 'Импорт')
}

function Backup-Storage {
    param([string]$ZipPath)
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($script:Store.Root, $ZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
}

function Restore-Storage {
    param([string]$ZipPath, [string]$TargetDir)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not (Test-Path -LiteralPath $TargetDir)) { [void](New-Item -ItemType Directory -Path $TargetDir -Force) }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $TargetDir)
}
