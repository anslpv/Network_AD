# Software.ps1 — учёт ПО: нормализация названий, категории, сводка установок, лицензии

$script:SoftwareCategoryRules = @(
    @('Архиваторы',             '7-Zip|WinRAR|WinZip|PeaZip|Bandizip|IZArc|ZipGenius'),
    @('Браузеры',               'Chrome|Firefox|Opera|Yandex|Edge|Vivaldi|Brave|Chromium|Safari|Internet Explorer'),
    @('Офисные программы',      'Office|LibreOffice|OpenOffice|WPS|Word|Excel|PowerPoint|Outlook|Visio|Project|OneNote|Foxit|Acrobat Reader|Adobe Reader|PDF|ABBYY|Lync|Teams'),
    @('Графика',                'Photoshop|Illustrator|InDesign|Acrobat|Distiller|CorelDRAW|Corel|GIMP|Paint\.NET|Inkscape|FastStone|IrfanView|XnView|Blender|AutoCAD|Autodesk|SketchUp|Krita|Dreamweaver|Lightroom|Premiere|After Effects|TrueView'),
    @('Мультимедиа',            'VLC|Media Player|K-Lite|Codec|AIMP|Winamp|foobar|Audacity|Spotify|iTunes|QuickTime|Flash Player|Shockwave|Nero|Burn|CDBurner|ImgBurn|PotPlayer|HandBrake|OBS'),
    @('Безопасность',           'Kaspersky|ESET|NOD32|Dr\.Web|Avast|AVG|Norton|McAfee|Defender|Bitdefender|Sophos|Symantec|Malwarebytes|Avira|Panda|Trend Micro|Endpoint|Firewall|КриптоПро|CryptoPro|VipNet|Secret Net|Континент'),
    @('Резервирование',         'Acronis|Veeam|Backup|Cobian|Macrium|Paragon|AOMEI|Handy Backup'),
    @('Разработка',             'Visual Studio|Python|Git|Node\.js|JDK|SDK|IntelliJ|PyCharm|Eclipse|Delphi|NetBeans|Notepad\+\+|Sublime|Postman|Docker|SQL Server Management|Firebird|MySQL|PostgreSQL|SQL Server|Oracle'),
    @('Драйверы и компоненты',  'Driver|Драйвер|Redistributable|Runtime|\.NET|Framework|Visual C\+\+|DirectX|Java|Silverlight|WebView2|Chipset|Realtek|Intel\(R\)|NVIDIA|AMD|Atheros|Broadcom|Synaptics|ELAN|Bluetooth|Update Helper|Updater|Update Service|Notifier|Maintenance Service'),
    @('Связь',                  'Skype|Zoom|Telegram|WhatsApp|Viber|Slack|Discord|Thunderbird|The Bat|Webex|TeamViewer|AnyDesk|Radmin|UltraVNC|TightVNC|RustDesk|Ammyy|Putty|PuTTY|WinSCP|FileZilla'),
    @('Бизнес',                 '1С|1C:|1C |Консультант|Гарант|MapInfo|SAP|Контур|СБИС|Диадок'),
    @('Утилиты',                'CCleaner|Everest|AIDA|CPU-Z|GPU-Z|HWiNFO|Total Commander|FAR|Far Manager|Unlocker|Process Explorer|Sysinternals|Recuva|Defraggler|Speccy|Uninstall|Utility|Tool|PowerToys|Everything|Daemon Tools|UltraISO|Rufus|Classic Shell|Open-Shell')
)

$script:FreeSoftwarePattern = '7-Zip|Firefox|Chrome|Opera|Yandex|Vivaldi|Brave|VLC|Notepad\+\+|PuTTY|WinSCP|FileZilla|LibreOffice|OpenOffice|GIMP|Paint\.NET|Inkscape|Thunderbird|K-Lite|FAR|Far Manager|Foxit Reader|Adobe Reader|Acrobat Reader|Skype|Zoom|Telegram|Visual Studio Code|Python|Git|Node\.js|AIMP|IrfanView|XnView|FastStone|CCleaner Free|Java|Flash Player|Silverlight|Audacity|qBittorrent|PDF24|Sumatra|Everything|PowerToys|Burn4Free|CDBurnerXP|ImgBurn|Classic Shell|Open-Shell|Radmin Viewer|TightVNC|UltraVNC'
$script:CommercialSoftwarePattern = 'Microsoft Office|Office Professional|Office Standard|Office Pro|Project Professional|Visio|Photoshop|Illustrator|InDesign|Acrobat(?! Reader)|Distiller|Dreamweaver|Premiere|After Effects|Autodesk|AutoCAD|Inventor|Maya|Corel|Kaspersky|ESET|Dr\.Web|Acronis|WinRAR|1С|1C:|ABBYY|MapInfo|Visual Studio (Professional|Enterprise)|SQL Server (Standard|Enterprise)|VMware Workstation|Parallels|EVEREST|AIDA64|Total Commander|Radmin Server|TeamViewer|КриптоПро|CryptoPro|Lync'
$script:ComponentPattern = 'Redistributable|Runtime|\.NET|Framework|Visual C\+\+|DirectX|Driver|Драйвер|WebView2|Update Helper|Updater|Update Service|Language Pack|Help Viewer|Notifier|Maintenance Service|SDK|Prerequisites|Bootstrapper|Chipset|MSXML|Silverlight|Installer|Setup Files'

function Get-NormalizedSoftwareName {
    param([string]$Name)
    if (-not $Name) { return '' }
    $n = $Name.Trim()
    $n = $n -replace '\s*\((x64|x86|64-bit|32-bit|64 bit|32 bit|x64 edition|x86 edition|remove only|только удаление)[^)]*\)', ''
    $n = $n -replace '\s*\(\s*v?\d+(\.\d+)+[^)]*\)', ''
    $n = $n -replace '\s+-\s+[a-z]{2}-[a-z]{2}(\s.*)?$', ''
    $n = $n -replace '\s+(x64|x86|64-bit|32-bit)$', ''
    $n = $n -replace '\s+v?\d+(\.\d+){1,}([\s\-]+(ESR|Beta|beta|RC|alpha|Alpha|\(.*\)|[a-z]{2}(-[A-Z]{2})?|x64|x86).*)?$', ''
    $n = $n -replace '\s+\d+\.\d+\s*$', ''
    $n = $n -replace '\s{2,}', ' '
    $n = $n.Trim(' ', '-', ',')
    if (-not $n) { return $Name.Trim() }
    return $n
}

function Get-SoftwareCategory {
    param([string]$Name, [string]$Publisher)
    $text = $Name
    foreach ($r in $script:SoftwareCategoryRules) {
        if ($text -match $r[1]) { return $r[0] }
    }
    return ''
}

function Get-SoftwareType {
    # Free / Commercial / Component / Unknown
    param([string]$Name, [string]$Publisher)
    if ($Name -match $script:ComponentPattern) { return 'Component' }
    if ($Name -match $script:CommercialSoftwarePattern) { return 'Commercial' }
    if ($Name -match $script:FreeSoftwarePattern) { return 'Free' }
    return 'Unknown'
}

function Get-SoftwareTypeText {
    param([string]$Type)
    switch ($Type) {
        'Free'       { 'Бесплатное' }
        'Commercial' { 'Коммерческое' }
        'Component'  { 'Системный компонент' }
        default      { 'Не определён' }
    }
}

function Get-SoftwareSummary {
    # Сводка ПО по набору устройств (последние снимки)
    param([array]$Devices)
    $groups = @{}
    foreach ($dev in $Devices) {
        $data = Get-DeviceSnapshot $dev
        if (-not $data) { continue }
        foreach ($sw in (As-Array (Get-Val $data 'Software'))) {
            $name = [string](Get-Val $sw 'Name')
            if (-not $name) { continue }
            $norm = Get-NormalizedSoftwareName $name
            $pub = [string](Get-Val $sw 'Publisher')
            $key = $norm.ToLowerInvariant()
            if (-not $groups.ContainsKey($key)) {
                $groups[$key] = @{
                    Key = $key; Name = $norm; Publisher = $pub
                    Category = (Get-SoftwareCategory $norm $pub)
                    Type = (Get-SoftwareType $norm $pub)
                    Versions = @{}; Installs = New-Object System.Collections.ArrayList
                }
            }
            $g = $groups[$key]
            if (-not $g.Publisher -and $pub) { $g.Publisher = $pub }
            $ver = [string](Get-Val $sw 'Version')
            if ($ver) { $g.Versions[$ver] = $true }
            [void]$g.Installs.Add(@{
                DeviceId    = $dev['Id']
                DeviceName  = [string]$dev['Name']
                DeviceType  = [string]$dev['Type']
                Ip          = [string]$dev['Ip']
                DisplayName = $name
                Version     = $ver
                Arch        = [string](Get-Val $sw 'Arch')
                InstallDate = (Get-Val $sw 'InstallDate')
                Added       = [string]$dev['Created']
                Location    = [string](Get-Val $sw 'InstallLocation')
            })
        }
    }
    $list = @($groups.Values | Sort-Object { $_.Name })
    foreach ($g in $list) {
        $vs = @($g.Versions.Keys)
        if ($vs.Count -eq 1) { $g.VersionText = $vs[0] } else { $g.VersionText = '' }
        $g.VersionCount = $vs.Count
        $g.Copies = $g.Installs.Count
        $g.License = Get-SoftwareLicenseStatus $g
    }
    return $list
}

# ---------------------------------------------------------------------------
#  Лицензии
# ---------------------------------------------------------------------------
function Test-LicenseMatch {
    param($License, [string]$SoftwareName)
    $pat = [string](Get-Val $License 'Software')
    if (-not $pat) { return $false }
    foreach ($p in ($pat -split ';')) {
        $p = $p.Trim()
        if (-not $p) { continue }
        if ($p -notmatch '[\*\?]') { $p = '*' + $p + '*' }
        if ($SoftwareName -like $p) { return $true }
    }
    return $false
}

function Get-LicensesForSoftware {
    param([string]$SoftwareName)
    return @($script:Store.Licenses | Where-Object { Test-LicenseMatch $_ $SoftwareName })
}

function Get-SoftwareLicenseStatus {
    param($Group)
    $lics = @(Get-LicensesForSoftware $Group.Name)
    if ($lics.Count -eq 0) {
        if ($Group.Type -eq 'Free') { return 'Бесплатное' }
        if ($Group.Type -eq 'Component') { return 'Не требуется' }
        return 'Неизвестно'
    }
    $seats = 0
    foreach ($l in $lics) { $seats += [int](Get-Val $l 'Seats') }
    if ($Group.Copies -gt $seats) { return ('Превышено ({0} из {1})' -f $Group.Copies, $seats) }
    return ('Лицензировано ({0} из {1})' -f $Group.Copies, $seats)
}

function Get-LicenseUsage {
    # Возвращает @{ Installed; Status } для лицензии по текущему хранилищу
    param($License, [array]$Summary)
    $installed = 0
    foreach ($g in $Summary) { if (Test-LicenseMatch $License $g.Name) { $installed += $g.Copies } }
    $seats = [int](Get-Val $License 'Seats')
    $status = 'В норме'
    $exp = ConvertTo-DateTime (Get-Val $License 'Expires')
    if ($exp -and $exp -lt (Get-Date).Date) { $status = 'Истекла' }
    elseif ($installed -gt $seats) { $status = 'Превышено' }
    elseif ($installed -eq 0) { $status = 'Не используется' }
    return @{ Installed = $installed; Status = $status; Seats = $seats }
}

function Get-AllFoundKeys {
    # Все ключи продуктов из последних снимков
    param([array]$Devices)
    $res = @()
    foreach ($dev in $Devices) {
        $data = Get-DeviceSnapshot $dev
        if (-not $data) { continue }
        foreach ($k in (As-Array (Get-Val $data 'ProductKeys'))) {
            $res += @{ Key = [string](Get-Val $k 'Key'); Product = [string](Get-Val $k 'Product'); Source = [string](Get-Val $k 'Source'); DeviceId = $dev['Id']; DeviceName = [string]$dev['Name']; Ip = [string]$dev['Ip']; DeviceType = [string]$dev['Type'] }
        }
    }
    return $res
}

function Get-UnboundKeys {
    param([array]$Devices)
    $bound = @{}
    foreach ($l in $script:Store.Licenses) { foreach ($k in (As-Array (Get-Val $l 'LicenseKeys'))) { if ($k) { $bound[([string]$k).ToUpperInvariant()] = $true } } }
    return @(Get-AllFoundKeys $Devices | Where-Object { $_.Key -and -not $bound.ContainsKey($_.Key.ToUpperInvariant()) })
}
