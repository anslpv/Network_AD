# Scanner.ps1 — задачи сканирования, обнаружение узлов, параллельный сбор данных

# ---------------------------------------------------------------------------
#  IP-утилиты
# ---------------------------------------------------------------------------
function ConvertTo-IpUInt32 {
    param([string]$Ip)
    $b = ([System.Net.IPAddress]::Parse($Ip)).GetAddressBytes()
    return ([uint32]$b[0] * 16777216 + [uint32]$b[1] * 65536 + [uint32]$b[2] * 256 + [uint32]$b[3])
}

function ConvertFrom-IpUInt32 {
    param([uint32]$Value)
    return ('{0}.{1}.{2}.{3}' -f (($Value -shr 24) -band 255), (($Value -shr 16) -band 255), (($Value -shr 8) -band 255), ($Value -band 255))
}

function Test-IPv4 {
    param([string]$Text)
    if ($Text -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    foreach ($p in $Text.Split('.')) { if ([int]$p -gt 255) { return $false } }
    return $true
}

function Get-IpRangeCount {
    param($Task)
    switch ($Task.Kind) {
        'Cidr'  { $bits = [int]$Task.Prefix; if ($bits -ge 31) { return [math]::Pow(2, 32 - $bits) } return ([math]::Pow(2, 32 - $bits) - 2) }
        'Range' { return ([double](ConvertTo-IpUInt32 $Task.End) - [double](ConvertTo-IpUInt32 $Task.Start) + 1) }
        default { return 1 }
    }
}

function Expand-ScanTask {
    # Возвращает список адресов/имён для задачи
    param($Task)
    $list = New-Object System.Collections.ArrayList
    switch ($Task.Kind) {
        'Cidr' {
            $bits = [int]$Task.Prefix
            $net = ConvertTo-IpUInt32 $Task.Network
            $size = [uint32][math]::Pow(2, 32 - $bits)
            $mask = [uint32]([math]::Pow(2, 32) - $size)
            $start = [uint32]($net -band $mask)
            if ($bits -ge 31) { $first = $start; $last = [uint32]($start + $size - 1) }
            else { $first = [uint32]($start + 1); $last = [uint32]($start + $size - 2) }
            for ($v = [double]$first; $v -le [double]$last; $v++) { [void]$list.Add((ConvertFrom-IpUInt32 ([uint32]$v))) }
        }
        'Range' {
            $a = [double](ConvertTo-IpUInt32 $Task.Start); $b = [double](ConvertTo-IpUInt32 $Task.End)
            for ($v = $a; $v -le $b; $v++) { [void]$list.Add((ConvertFrom-IpUInt32 ([uint32]$v))) }
        }
        'Devices' { foreach ($t in $Task.Targets) { [void]$list.Add($t) } }
        'AD'      { foreach ($t in $Task.Targets) { [void]$list.Add($t) } }
        default { [void]$list.Add($Task.Target) }
    }
    return $list.ToArray()
}

function New-ScanTask {
    param([string]$Kind, [string]$Text, [hashtable]$Extra = @{})
    $t = @{
        Id      = (New-Id)
        Kind    = $Kind
        Text    = $Text
        Enabled = $true
        LoginId = [string](Get-Val $script:Settings 'DefaultLogin')
        Folder  = ''
        Status  = ''
    }
    if (-not $t.LoginId) { $t.LoginId = 'current' }
    foreach ($k in $Extra.Keys) { $t[$k] = $Extra[$k] }
    return $t
}

function ConvertFrom-ScanInput {
    # Разбирает строку из поля «Добавить». Возвращает массив задач. Ошибки — исключением.
    param([string]$Text)
    $tasks = @()
    foreach ($raw in ($Text -split '[,;\s]+')) {
        $s = $raw.Trim()
        if (-not $s) { continue }
        if ($s -match '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') {
            $ip = $Matches[1]; $bits = [int]$Matches[2]
            if (-not (Test-IPv4 $ip) -or $bits -lt 8 -or $bits -gt 32) { throw "Неверная подсеть: $s" }
            $net = ConvertTo-IpUInt32 $ip
            $size = [math]::Pow(2, 32 - $bits)
            $mask = [uint32]([math]::Pow(2, 32) - $size)
            $netIp = ConvertFrom-IpUInt32 ([uint32]($net -band $mask))
            if ($bits -eq 32) { $tasks += New-ScanTask 'Ip' $ip @{ Target = $ip }; continue }
            $tasks += New-ScanTask 'Cidr' ('{0}/{1}' -f $netIp, $bits) @{ Network = $netIp; Prefix = $bits }
            continue
        }
        if ($s -match '^(\d{1,3}(?:\.\d{1,3}){3})-(\d{1,3}(?:\.\d{1,3}){3}|\d{1,3})$') {
            $a = $Matches[1]; $b = $Matches[2]
            if ($b -notmatch '\.') { $parts = $a.Split('.'); $b = ('{0}.{1}.{2}.{3}' -f $parts[0], $parts[1], $parts[2], $b) }
            if (-not (Test-IPv4 $a) -or -not (Test-IPv4 $b)) { throw "Неверный диапазон: $s" }
            if ((ConvertTo-IpUInt32 $b) -lt (ConvertTo-IpUInt32 $a)) { $tmp = $a; $a = $b; $b = $tmp }
            $tasks += New-ScanTask 'Range' ('{0} - {1}' -f $a, $b) @{ Start = $a; End = $b }
            continue
        }
        if (Test-IPv4 $s) { $tasks += New-ScanTask 'Ip' $s @{ Target = $s }; continue }
        if ($s -match '^[A-Za-z0-9][A-Za-z0-9\-\._]*$') { $tasks += New-ScanTask 'Host' $s @{ Target = $s }; continue }
        throw "Не удалось распознать: $s"
    }
    return $tasks
}

function Get-LocalSubnets {
    $res = @()
    try {
        foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($ni.OperationalStatus -ne 'Up') { continue }
            if ($ni.NetworkInterfaceType -eq 'Loopback') { continue }
            foreach ($ua in $ni.GetIPProperties().UnicastAddresses) {
                if ($ua.Address.AddressFamily -ne 'InterNetwork') { continue }
                $bits = 24
                try { $bits = [int]$ua.PrefixLength } catch { }
                if ($bits -le 0 -or $bits -gt 32) { $bits = 24 }
                if ($bits -lt 16) { $bits = 16 }
                $ip = ConvertTo-IpUInt32 $ua.Address.ToString()
                $size = [math]::Pow(2, 32 - $bits)
                $mask = [uint32]([math]::Pow(2, 32) - $size)
                $cidr = ('{0}/{1}' -f (ConvertFrom-IpUInt32 ([uint32]($ip -band $mask))), $bits)
                if ($res -notcontains $cidr) { $res += $cidr }
            }
        }
    } catch { }
    return @($res | Sort-Object)
}

function Get-CurrentAdDomain {
    try { return ([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name } catch { return $null }
}

function Get-AdComputers {
    param([string]$Domain, [System.Management.Automation.PSCredential]$Credential = $null)
    $path = 'LDAP://' + $Domain
    if ($Credential) {
        $entry = New-Object System.DirectoryServices.DirectoryEntry($path, $Credential.UserName, $Credential.GetNetworkCredential().Password)
    } else {
        $entry = New-Object System.DirectoryServices.DirectoryEntry($path)
    }
    $ds = New-Object System.DirectoryServices.DirectorySearcher($entry)
    $ds.Filter = '(&(objectCategory=computer)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))'
    $ds.PageSize = 500
    foreach ($p in @('name', 'dnshostname', 'operatingsystem', 'distinguishedname')) { [void]$ds.PropertiesToLoad.Add($p) }
    $out = @()
    foreach ($r in $ds.FindAll()) {
        $name = [string]($r.Properties['name'] | Select-Object -First 1)
        $dns  = [string]($r.Properties['dnshostname'] | Select-Object -First 1)
        $os   = [string]($r.Properties['operatingsystem'] | Select-Object -First 1)
        $dn   = [string]($r.Properties['distinguishedname'] | Select-Object -First 1)
        $ou = ''
        if ($dn -match '^CN=[^,]+,(.+)$') { $ou = $Matches[1] }
        $out += @{ Name = $name; Host = $(if ($dns) { $dns } else { $name }); OS = $os; OU = $ou }
    }
    return $out
}

# ---------------------------------------------------------------------------
#  ARP (iphlpapi) — компилируется один раз
# ---------------------------------------------------------------------------
function Initialize-ArpHelper {
    if ('NetInv.Arp' -as [type]) { return }
    try {
        Add-Type -Namespace NetInv -Name Arp -MemberDefinition @'
[DllImport("iphlpapi.dll", ExactSpelling = true)]
public static extern int SendARP(uint destIp, uint srcIp, byte[] macAddr, ref uint physAddrLen);
public static string Resolve(string ip) {
    var addr = System.Net.IPAddress.Parse(ip);
    uint dest = System.BitConverter.ToUInt32(addr.GetAddressBytes(), 0);
    byte[] mac = new byte[6]; uint len = 6;
    int r = SendARP(dest, 0, mac, ref len);
    if (r != 0) return null;
    return string.Join("-", System.Array.ConvertAll(mac, b => b.ToString("X2")));
}
'@ -ErrorAction Stop
    } catch { }
}

# ---------------------------------------------------------------------------
#  Рабочий скрипт одного узла (выполняется в пуле потоков)
# ---------------------------------------------------------------------------
$script:ScanWorker = {
    param($CollectorPath, $Target, $Credential, $Opts, $Queue, $Sync, $TaskId)

    function Log([string]$Level, [string]$Text) {
        $Queue.Enqueue(@{ Type = 'log'; Level = $Level; Text = $Text; Time = (Get-Date); Target = $Target; TaskId = $TaskId })
    }
    $result = @{ Type = 'result'; TaskId = $TaskId; Target = $Target; Ok = $false; Skipped = $false }
    try {
        if ($Sync.Cancel) { $result.Skipped = $true; $result.Error = 'Отменено'; $Queue.Enqueue($result); return }
        $Queue.Enqueue(@{ Type = 'progress'; TaskId = $TaskId; Target = $Target; Stage = 'discover' })

        $alive = $true
        $isLocal = $false
        . $CollectorPath
        $isLocal = Test-IsLocalComputer $Target

        if ($Opts.UseDiscovery -and -not $isLocal) {
            $alive = $false
            $attempts = [math]::Max(1, [int]$Opts.PingAttempts)
            if ($Opts.DiscoveryProfile -eq 'Slow') { $attempts++ }
            $ping = New-Object System.Net.NetworkInformation.Ping
            for ($i = 0; $i -lt $attempts -and -not $alive; $i++) {
                try { $r = $ping.Send($Target, [int]$Opts.PingTimeout); if ($r.Status -eq 'Success') { $alive = $true } } catch { }
            }
            $ping.Dispose()
            if (-not $alive -and $Opts.UseArpPing -and ($Target -match '^\d+\.\d+\.\d+\.\d+$') -and ('NetInv.Arp' -as [type])) {
                try { if ([NetInv.Arp]::Resolve($Target)) { $alive = $true } } catch { }
            }
            if (-not $alive -and $Opts.DiscoveryProfile -ne 'Fast') {
                $ports = @(135, 445, 5985)
                if ($Opts.PortProfile -eq 'Light' -or $Opts.DiscoveryProfile -eq 'Slow') { $ports = @(135, 139, 445, 5985, 5986, 22, 80, 443, 3389, 9100) }
                foreach ($port in $ports) {
                    if ($alive) { break }
                    $tc = New-Object System.Net.Sockets.TcpClient
                    try {
                        $ar = $tc.BeginConnect($Target, $port, $null, $null)
                        if ($ar.AsyncWaitHandle.WaitOne([int]$Opts.PortTimeout) -and $tc.Connected) { $alive = $true }
                    } catch { } finally { $tc.Close() }
                }
            }
        }
        if (-not $alive) {
            $result.Skipped = $true; $result.Error = 'Узел недоступен'
            $Queue.Enqueue($result); return
        }
        if ($Sync.Cancel) { $result.Skipped = $true; $result.Error = 'Отменено'; $Queue.Enqueue($result); return }

        Log 'info' ('{0}: узел найден, сбор данных...' -f $Target)
        $Queue.Enqueue(@{ Type = 'progress'; TaskId = $TaskId; Target = $Target; Stage = 'collect' })
        $cred = $Credential
        if ($isLocal) { $cred = $null }
        $r = Invoke-InventoryCollection -Target $Target -Credential $cred -DisableDcom ([bool]$Opts.DisableDcom) -ScanUpdates ([bool]$Opts.ScanWindowsUpdates) -UpdatesTimeoutSec ([int]$Opts.UpdatesTimeoutMin * 60)
        $result.Ok = [bool]$r.Ok
        $result.Data = $r.Data
        $result.Method = $r.Method
        $result.Error = $r.Error
    } catch {
        $result.Error = $_.Exception.Message
    }
    $Queue.Enqueue($result)
}

# ---------------------------------------------------------------------------
#  Движок
# ---------------------------------------------------------------------------
function Start-ScanEngine {
    # $Items: массив @{ Target; TaskId; Credential }
    param([array]$Items, [hashtable]$Opts, [string]$CollectorPath)
    Initialize-ArpHelper
    $threads = [math]::Max(1, [math]::Min(64, [int]$Opts.Threads))
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $pool = [runspacefactory]::CreateRunspacePool(1, $threads, $iss, $Host)
    $pool.ApartmentState = 'MTA'
    $pool.Open()
    $engine = @{
        Pool     = $pool
        Queue    = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        Sync     = [hashtable]::Synchronized(@{ Cancel = $false })
        Jobs     = New-Object System.Collections.ArrayList
        Total    = $Items.Count
        Finished = 0
        Started  = Get-Date
        Running  = $true
    }
    foreach ($it in $Items) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($script:ScanWorker.ToString())
        [void]$ps.AddArgument($CollectorPath).AddArgument($it.Target).AddArgument($it.Credential).AddArgument($Opts).AddArgument($engine.Queue).AddArgument($engine.Sync).AddArgument($it.TaskId)
        $h = $ps.BeginInvoke()
        [void]$engine.Jobs.Add(@{ PS = $ps; Handle = $h })
    }
    return $engine
}

function Receive-ScanMessages {
    # Забирает сообщения из очереди и подчищает завершённые потоки
    param($Engine)
    $msgs = New-Object System.Collections.ArrayList
    if (-not $Engine) { return $msgs.ToArray() }
    $m = $null
    while ($Engine.Queue.TryDequeue([ref]$m)) { [void]$msgs.Add($m) }
    foreach ($j in @($Engine.Jobs)) {
        if ($j.Handle.IsCompleted) {
            try { [void]$j.PS.EndInvoke($j.Handle) } catch { [void]$msgs.Add(@{ Type = 'log'; Level = 'error'; Text = $_.Exception.Message; Time = (Get-Date) }) }
            $j.PS.Dispose()
            $Engine.Jobs.Remove($j)
        }
    }
    if ($Engine.Jobs.Count -eq 0 -and $Engine.Running) {
        while ($Engine.Queue.TryDequeue([ref]$m)) { [void]$msgs.Add($m) }
        $Engine.Running = $false
        try { $Engine.Pool.Close(); $Engine.Pool.Dispose() } catch { }
    }
    return $msgs.ToArray()
}

function Stop-ScanEngine {
    param($Engine)
    if (-not $Engine) { return }
    $Engine.Sync.Cancel = $true
    foreach ($j in @($Engine.Jobs)) { try { [void]$j.PS.BeginStop($null, $null) } catch { } }
}

# ---------------------------------------------------------------------------
#  Сохранённые задачи
# ---------------------------------------------------------------------------
function Get-TasksFolder {
    $p = Join-Path $script:AppDataDir 'Tasks'
    if (-not (Test-Path -LiteralPath $p)) { [void](New-Item -ItemType Directory -Path $p -Force) }
    return $p
}

function Get-SavedTaskSets {
    $dir = Get-TasksFolder
    return @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { @{ Name = $_.BaseName; Path = $_.FullName } })
}

function Save-TaskSet {
    param([string]$Name, [array]$Tasks)
    $p = Join-Path (Get-TasksFolder) ((Get-SafeFileName $Name) + '.json')
    $clean = @($Tasks | ForEach-Object { $c = @{}; foreach ($k in $_.Keys) { if ($k -ne 'Status') { $c[$k] = $_[$k] } }; $c })
    Write-JsonFile $p $clean
}

function Load-TaskSet {
    param([string]$Path)
    $arr = Read-JsonFile $Path
    $res = @()
    foreach ($t in (As-Array $arr)) {
        $h = @{}
        foreach ($k in $t.Keys) { $h[$k] = $t[$k] }
        $h['Id'] = (New-Id); $h['Status'] = ''
        $res += $h
    }
    return $res
}
