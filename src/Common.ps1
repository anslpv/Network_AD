# Common.ps1 — общие функции: пути, настройки, JSON, форматирование
# Совместимость: Windows PowerShell 5.1

$script:AppName    = 'Network Inventory'
$script:AppVersion = '1.0.0'

# ---------------------------------------------------------------------------
#  JSON (быстрый сериализатор .NET, при отсутствии — штатные командлеты)
# ---------------------------------------------------------------------------
$script:JsonSerializer = $null
try {
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    $script:JsonSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $script:JsonSerializer.MaxJsonLength  = [int]::MaxValue
    $script:JsonSerializer.RecursionLimit = 256
} catch { $script:JsonSerializer = $null }

function ConvertTo-PlainObject {
    # Приводит объект к «чистым» типам: Hashtable, object[], строки, числа, bool.
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    $o = $InputObject
    if ($o -is [System.Management.Automation.PSObject]) {
        $base = $o.PSObject.BaseObject
        if ($base -is [System.Management.Automation.PSCustomObject]) {
            $h = [ordered]@{}
            foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-PlainObject $p.Value }
            return $h
        }
        $o = $base
    }
    if ($o -is [string] -or $o -is [bool] -or $o -is [char]) { return $o }
    if ($o -is [datetime]) { return $o.ToString('yyyy-MM-ddTHH:mm:ss') }
    if ($o -is [enum]) { return $o.ToString() }
    if ($o -is [System.ValueType]) { return $o }
    if ($o -is [System.Collections.IDictionary]) {
        $h = [ordered]@{}
        foreach ($k in @($o.PSBase.Keys)) { $h[[string]$k] = ConvertTo-PlainObject $o[$k] }
        return $h
    }
    if ($o -is [System.Collections.IEnumerable]) {
        $list = New-Object System.Collections.ArrayList
        foreach ($i in $o) { [void]$list.Add((ConvertTo-PlainObject $i)) }
        return ,($list.ToArray())
    }
    return [string]$o
}

function ConvertFrom-JsonDeep {
    # Результат ConvertFrom-Json (PSCustomObject) -> Hashtable/массивы
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertFrom-JsonDeep $p.Value }
        return $h
    }
    if ($InputObject -is [array]) {
        $list = New-Object System.Collections.ArrayList
        foreach ($i in $InputObject) { [void]$list.Add((ConvertFrom-JsonDeep $i)) }
        return ,($list.ToArray())
    }
    return $InputObject
}

function ConvertTo-JsonText {
    param($InputObject)
    $plain = ConvertTo-PlainObject $InputObject
    if ($script:JsonSerializer) { return $script:JsonSerializer.Serialize($plain) }
    return ($plain | ConvertTo-Json -Depth 32 -Compress)
}

function ConvertFrom-JsonText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    if ($script:JsonSerializer) {
        $obj = $script:JsonSerializer.DeserializeObject($Text)
        return (Convert-SerializerResult $obj)
    }
    return (ConvertFrom-JsonDeep ($Text | ConvertFrom-Json))
}

function Convert-SerializerResult {
    # Dictionary<string,object> -> Hashtable (чтобы $x.Prop работал одинаково везде)
    param($o)
    if ($null -eq $o) { return $null }
    if ($o -is [System.Collections.Generic.Dictionary[string,object]]) {
        $h = @{}
        # foreach по словарю в PowerShell не перебирает пары, поэтому — явный перечислитель
        $en = $o.GetEnumerator()
        while ($en.MoveNext()) { $kv = $en.Current; $h[[string]$kv.Key] = Convert-SerializerResult $kv.Value }
        return $h
    }
    if ($o -is [object[]]) {
        $arr = New-Object object[] $o.Length
        for ($i = 0; $i -lt $o.Length; $i++) { $arr[$i] = Convert-SerializerResult $o[$i] }
        return ,$arr
    }
    return $o
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return (ConvertFrom-JsonText $text)
}

function Write-JsonFile {
    param([string]$Path, $Data)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $text = ConvertTo-JsonText $Data
    $tmp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-Val {
    # Безопасное чтение поля из словаря/объекта; Get-Val $obj 'A' 'B' -> $obj.A.B
    param($Object)
    $cur = $Object
    foreach ($k in $args) {
        if ($null -eq $cur) { return $null }
        if ($cur -is [System.Collections.IDictionary]) {
            if ($cur.Contains($k)) { $cur = $cur[$k] } else { return $null }
        } else {
            $p = $cur.PSObject.Properties[$k]
            if ($p) { $cur = $p.Value } else { return $null }
        }
    }
    return $cur
}

function As-Array {
    # Возвращает элементы коллекции (без двойного оборачивания).
    # Использование: foreach ($x in (As-Array $v)) {...} или @(As-Array $v)
    param($Value)
    if ($null -eq $Value) { return }
    if ($Value -is [string] -or $Value -is [System.Collections.IDictionary]) { return $Value }
    if ($Value -is [System.Collections.IEnumerable]) { foreach ($i in $Value) { ,$i }; return }
    return $Value
}

# ---------------------------------------------------------------------------
#  Пути и настройки
# ---------------------------------------------------------------------------
$script:AppDataDir   = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'NetInventory'
$script:SettingsPath = Join-Path $script:AppDataDir 'settings.json'

function Get-DefaultSettings {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = $env:HOME }
    return @{
        StoragePath = (Join-Path $docs 'NetInventory Storage')
        General = @{
            FirstDayOfWeek     = 1          # 0 = воскресенье, 1 = понедельник
            RelativeDates      = $true
            CustomDateFormat   = $false
            DateFormat         = 'd MMM yyyy'
        }
        Scanner = @{
            SkipExisting        = $false
            SkipExistingHours   = 0
            UseDiscovery        = $true
            PingAttempts        = 1
            PingTimeout         = 1000
            DiscoveryProfile    = 'Normal'  # Fast / Normal / Slow
            UseArpPing          = $true
            PortProfile         = 'Light'   # Safe / Light
            PortTimeout         = 1000
            DisableDcom         = $false    # не использовать DCOM/RPC, только WinRM
            ScanWindowsUpdates  = $true
            UpdatesTimeoutMin   = 10
            Threads             = 16
            ShowWelcome         = $true
        }
        Reports = @{
            ShowEmptyValues     = $false
            HtmlFontSize        = 12
        }
        Alerts = @{
            DiskFreePercent     = 10
            MinRamGB            = 4
            CheckAntivirus      = $true
            CheckProblemDevices = $true
            CheckFirewall       = $true
        }
        Logins = @()        # @{ Id; Name; User; Password(DPAPI) }
        DefaultLogin = 'current'
        OnlineStatus = $true
        Window = @{ Width = 1400; Height = 860; Maximized = $true }
    }
}

function Merge-Hashtable {
    param([hashtable]$Base, $Overlay)
    if ($null -eq $Overlay) { return $Base }
    foreach ($k in @($Overlay.PSBase.Keys)) {
        $v = $Overlay[$k]
        if ($Base.ContainsKey($k) -and $Base[$k] -is [hashtable] -and $v -is [System.Collections.IDictionary]) {
            $Base[$k] = Merge-Hashtable $Base[$k] $v
        } else {
            $Base[$k] = $v
        }
    }
    return $Base
}

function Load-Settings {
    $s = Get-DefaultSettings
    try {
        $saved = Read-JsonFile $script:SettingsPath
        if ($saved) { $s = Merge-Hashtable $s $saved }
    } catch { }
    $script:Settings = $s
    return $s
}

function Save-Settings {
    try { Write-JsonFile $script:SettingsPath $script:Settings } catch { }
}

# Пароли: DPAPI текущего пользователя
function Protect-Password {
    param([string]$Plain)
    if ([string]::IsNullOrEmpty($Plain)) { return '' }
    $sec = ConvertTo-SecureString -String $Plain -AsPlainText -Force
    return (ConvertFrom-SecureString -SecureString $sec)
}

function Get-LoginCredential {
    param($Login)
    if ($null -eq $Login) { return $null }
    $user = Get-Val $Login 'User'
    $enc  = Get-Val $Login 'Password'
    if ([string]::IsNullOrEmpty($user)) { return $null }
    try {
        $sec = if ($enc) { ConvertTo-SecureString -String $enc } else { New-Object System.Security.SecureString }
        return (New-Object System.Management.Automation.PSCredential($user, $sec))
    } catch { return $null }
}

# ---------------------------------------------------------------------------
#  Форматирование
# ---------------------------------------------------------------------------
$script:MonthsShort = @('янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек')

function ConvertTo-DateTime {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    if ($Value -is [datetime]) { return $Value }
    $s = [string]$Value
    $d = [datetime]::MinValue
    if ($s -match '^\d{8}$') {
        if ([datetime]::TryParseExact($s, 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { return $d }
        return $null
    }
    if ($s -match '^/Date\((\-?\d+)\)/$') { return ([datetime]'1970-01-01').AddMilliseconds([double]$Matches[1]).ToLocalTime() }
    if ([datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    if ([datetime]::TryParse($s, [ref]$d)) { return $d }
    return $null
}

function Format-DateOnly {
    param($Value)
    $d = ConvertTo-DateTime $Value
    if ($null -eq $d) { return '' }
    $g = Get-Val $script:Settings 'General'
    if ($g -and (Get-Val $g 'CustomDateFormat') -and (Get-Val $g 'DateFormat')) {
        try { return $d.ToString((Get-Val $g 'DateFormat'), [Globalization.CultureInfo]'ru-RU') } catch { }
    }
    return ('{0} {1} {2}' -f $d.Day, $script:MonthsShort[$d.Month - 1], $d.Year)
}

function Format-DateTimeRu {
    param($Value, [switch]$NoRelative)
    $d = ConvertTo-DateTime $Value
    if ($null -eq $d) { return '' }
    $time = $d.ToString('HH:mm')
    $rel = $true
    $g = Get-Val $script:Settings 'General'
    if ($g -and ($null -ne (Get-Val $g 'RelativeDates'))) { $rel = [bool](Get-Val $g 'RelativeDates') }
    if ($rel -and -not $NoRelative) {
        $today = (Get-Date).Date
        if ($d.Date -eq $today) { return "Сегодня - $time" }
        if ($d.Date -eq $today.AddDays(-1)) { return "Вчера - $time" }
    }
    return ('{0} - {1}' -f (Format-DateOnly $d), $time)
}

function Format-Bytes {
    param($Bytes, [int]$Digits = 1)
    if ($null -eq $Bytes -or $Bytes -eq '') { return '' }
    $b = [double]$Bytes
    $units = @('Б','КБ','МБ','ГБ','ТБ','ПБ')
    $i = 0
    while ($b -ge 1024 -and $i -lt $units.Count - 1) { $b = $b / 1024; $i++ }
    if ($i -eq 0) { return ('{0} {1}' -f [math]::Round($b), $units[$i]) }
    $r = [math]::Round($b, $Digits)
    if ($r -eq [math]::Floor($r)) { $txt = ([int64]$r).ToString() } else { $txt = $r.ToString([Globalization.CultureInfo]::InvariantCulture) }
    return ('{0} {1}' -f $txt, $units[$i])
}

function Format-MHz {
    param($Value)
    if ($null -eq $Value -or $Value -eq '' -or [double]$Value -eq 0) { return '' }
    return ('{0} МГц' -f [int]$Value)
}

function Format-YesNo {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ([bool]$Value) { return 'Да' } else { return 'Нет' }
}

function New-Id {
    return ([guid]::NewGuid().ToString('N').Substring(0, 12))
}

function Get-SafeFileName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = 'device' }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalid -contains $ch) { [void]$sb.Append('_') } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString().Trim().TrimEnd('.')
}

function Get-RelativePathSimple {
    param([string]$Root, [string]$Path)
    $r = $Root.TrimEnd('\','/')
    if ($Path.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($r.Length).TrimStart('\','/')
    }
    return $Path
}
