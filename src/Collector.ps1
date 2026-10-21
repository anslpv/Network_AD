# Collector.ps1 — сбор инвентарных данных Windows-компьютера.
# Скрипт-блок $CollectorScript самодостаточен: его можно выполнить локально,
# передать на удалённый компьютер через Invoke-Command (WinRM) или выполнить
# локально с CIM-сессией DCOM к удалённой машине.

$script:CollectorVersion = '1.0'

$script:CollectorScript = {
    param(
        $CimSession = $null,          # $null = локальный компьютер
        [bool]$ScanUpdates = $true,
        [int]$UpdatesTimeoutSec = 600,
        [string]$Method = 'Local'
    )

    $ErrorActionPreference = 'Stop'
    $errors = New-Object System.Collections.ArrayList
    $isRemoteCim = ($null -ne $CimSession)

    # ---------------------------------------------------------------- helpers
    function S([object]$v) {
        if ($null -eq $v) { return $null }
        $t = ([string]$v).Trim()
        if ($t -eq '') { return $null }
        return $t
    }
    function D([object]$v) {
        if ($null -eq $v) { return $null }
        if ($v -is [datetime]) { return $v.ToString('yyyy-MM-ddTHH:mm:ss') }
        return (S $v)
    }
    function Q([string]$Class, [string]$Namespace = 'root\cimv2', [string]$Filter = $null) {
        $p = @{ ClassName = $Class; Namespace = $Namespace; ErrorAction = 'Stop' }
        if ($Filter) { $p['Filter'] = $Filter }
        if ($isRemoteCim) { $p['CimSession'] = $CimSession; $p['OperationTimeoutSec'] = 60 }
        try { return @(Get-CimInstance @p) }
        catch {
            if ($Namespace -eq 'root\cimv2') { [void]$errors.Add(('{0}: {1}' -f $Class, $_.Exception.Message)) }
            return @()
        }
    }

    $HKLM = [uint32]2147483650
    $HKU  = [uint32]2147483651

    function Get-LocalKey([uint32]$Hive, [string]$Path) {
        $h = [Microsoft.Win32.RegistryHive]::LocalMachine
        if ($Hive -eq $HKU) { $h = [Microsoft.Win32.RegistryHive]::Users }
        $view = [Microsoft.Win32.RegistryView]::Default
        if ([Environment]::Is64BitOperatingSystem) { $view = [Microsoft.Win32.RegistryView]::Registry64 }
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($h, $view)
        return $base.OpenSubKey($Path)
    }
    function Reg-Keys([uint32]$Hive, [string]$Path) {
        if ($isRemoteCim) {
            try {
                $r = Invoke-CimMethod -CimSession $CimSession -Namespace root\cimv2 -ClassName StdRegProv -MethodName EnumKey -Arguments @{ hDefKey = $Hive; sSubKeyName = $Path }
                if ($r.ReturnValue -eq 0 -and $r.sNames) { return @($r.sNames) }
            } catch { }
            return @()
        }
        try { $k = Get-LocalKey $Hive $Path; if ($k) { $n = $k.GetSubKeyNames(); $k.Close(); return @($n) } } catch { }
        return @()
    }
    function Reg-Values([uint32]$Hive, [string]$Path) {
        # Возвращает хэш-таблицу имя -> значение (строки и числа)
        $res = @{}
        if ($isRemoteCim) {
            try {
                $r = Invoke-CimMethod -CimSession $CimSession -Namespace root\cimv2 -ClassName StdRegProv -MethodName EnumValues -Arguments @{ hDefKey = $Hive; sSubKeyName = $Path }
                if ($r.ReturnValue -ne 0 -or -not $r.sNames) { return $res }
                $names = @($r.sNames); $types = @($r.Types)
                for ($i = 0; $i -lt $names.Count; $i++) {
                    $n = $names[$i]; $t = $types[$i]
                    $args2 = @{ hDefKey = $Hive; sSubKeyName = $Path; sValueName = $n }
                    try {
                        switch ($t) {
                            1 { $res[$n] = (Invoke-CimMethod -CimSession $CimSession -Namespace root\cimv2 -ClassName StdRegProv -MethodName GetStringValue -Arguments $args2).sValue }
                            2 { $res[$n] = (Invoke-CimMethod -CimSession $CimSession -Namespace root\cimv2 -ClassName StdRegProv -MethodName GetExpandedStringValue -Arguments $args2).sValue }
                            4 { $res[$n] = (Invoke-CimMethod -CimSession $CimSession -Namespace root\cimv2 -ClassName StdRegProv -MethodName GetDWORDValue -Arguments $args2).uValue }
                            11 { $res[$n] = (Invoke-CimMethod -CimSession $CimSession -Namespace root\cimv2 -ClassName StdRegProv -MethodName GetQWORDValue -Arguments $args2).uValue }
                        }
                    } catch { }
                }
            } catch { }
            return $res
        }
        try {
            $k = Get-LocalKey $Hive $Path
            if ($k) {
                foreach ($n in $k.GetValueNames()) {
                    $kind = $k.GetValueKind($n)
                    if ($kind -eq 'String' -or $kind -eq 'ExpandString' -or $kind -eq 'DWord' -or $kind -eq 'QWord') {
                        $res[$n] = $k.GetValue($n)
                    }
                }
                $k.Close()
            }
        } catch { }
        return $res
    }
    function Reg-Value([uint32]$Hive, [string]$Path, [string]$Name, [string]$Kind = 'String') {
        if ($isRemoteCim) {
            $m = @{ String = 'GetStringValue'; DWord = 'GetDWORDValue'; Binary = 'GetBinaryValue'; Multi = 'GetMultiStringValue' }[$Kind]
            try {
                $r = Invoke-CimMethod -CimSession $CimSession -Namespace root\cimv2 -ClassName StdRegProv -MethodName $m -Arguments @{ hDefKey = $Hive; sSubKeyName = $Path; sValueName = $Name }
                if ($r.ReturnValue -ne 0) { return $null }
                switch ($Kind) { 'String' { return $r.sValue } 'DWord' { return $r.uValue } 'Binary' { return $r.uValue } 'Multi' { return $r.sValue } }
            } catch { return $null }
            return $null
        }
        try {
            $k = Get-LocalKey $Hive $Path
            if ($k) { $v = $k.GetValue($Name); $k.Close(); return $v }
        } catch { }
        return $null
    }
    function Decode-ProductKey([byte[]]$Id) {
        if ($null -eq $Id -or $Id.Length -lt 67) { return $null }
        $key = New-Object byte[] 15
        [Array]::Copy($Id, 52, $key, 0, 15)
        $isWin8 = ([math]::Floor($key[14] / 6)) -band 1
        $key[14] = ($key[14] -band 0xF7)
        $chars = 'BCDFGHJKMPQRTVWXY2346789'
        $out = ''
        $last = 0
        for ($i = 24; $i -ge 0; $i--) {
            $cur = 0
            for ($j = 14; $j -ge 0; $j--) {
                $cur = $cur * 256 + $key[$j]
                $key[$j] = [byte][math]::Floor($cur / 24)
                $cur = $cur % 24
            }
            $out = [string]$chars[$cur] + $out
            $last = $cur
        }
        if ($isWin8 -eq 1) { $out = $out.Substring(1).Insert($last, 'N') }
        $parts = @()
        for ($p = 0; $p -lt 25; $p += 5) { $parts += $out.Substring($p, 5) }
        $k = $parts -join '-'
        if ($k -eq 'BBBBB-BBBBB-BBBBB-BBBBB-BBBBB') { return $null }
        return $k
    }
    function Chars([object]$arr) {
        if ($null -eq $arr) { return $null }
        $s = -join (@($arr) | Where-Object { $_ -ne 0 } | ForEach-Object { [char][int]$_ })
        return (S $s)
    }

    $data = @{}

    # ---------------------------------------------------------------- system
    $cs   = Q 'Win32_ComputerSystem' | Select-Object -First 1
    $bios = Q 'Win32_BIOS' | Select-Object -First 1
    $bb   = Q 'Win32_BaseBoard' | Select-Object -First 1
    $csp  = Q 'Win32_ComputerSystemProduct' | Select-Object -First 1
    $enc  = Q 'Win32_SystemEnclosure' | Select-Object -First 1
    $os   = Q 'Win32_OperatingSystem' | Select-Object -First 1

    $chassis = @()
    if ($enc -and $enc.ChassisTypes) { $chassis = @($enc.ChassisTypes | ForEach-Object { [int]$_ }) }

    $data.System = @{
        Name            = S $cs.Name
        DnsHostName     = S $cs.DNSHostName
        Domain          = S $cs.Domain
        PartOfDomain    = [bool]$cs.PartOfDomain
        Workgroup       = S $cs.Workgroup
        DomainRole      = $cs.DomainRole
        UserName        = S $cs.UserName
        Manufacturer    = S $cs.Manufacturer
        Model           = S $cs.Model
        SystemFamily    = S $cs.SystemFamily
        SystemSku       = S $cs.SystemSKUNumber
        SystemType      = S $cs.SystemType
        TotalMemory     = $cs.TotalPhysicalMemory
        HypervisorPresent = $cs.HypervisorPresent
        SerialNumber    = S $bios.SerialNumber
        Uuid            = S $csp.UUID
        ProductName     = S $csp.Name
        ProductVendor   = S $csp.Vendor
        ProductVersion  = S $csp.Version
        ChassisTypes    = $chassis
        AssetTag        = S $enc.SMBIOSAssetTag
        Bios = @{
            Manufacturer = S $bios.Manufacturer
            Version      = S $bios.SMBIOSBIOSVersion
            Name         = S $bios.Name
            ReleaseDate  = D $bios.ReleaseDate
            SmbiosVersion = ('{0}.{1}' -f $bios.SMBIOSMajorVersion, $bios.SMBIOSMinorVersion)
        }
        Board = @{
            Manufacturer = S $bb.Manufacturer
            Product      = S $bb.Product
            Version      = S $bb.Version
            SerialNumber = S $bb.SerialNumber
        }
    }

    # ---------------------------------------------------------------- OS
    $cv = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $displayVersion = Reg-Value $HKLM $cv 'DisplayVersion'
    if (-not $displayVersion) { $displayVersion = Reg-Value $HKLM $cv 'ReleaseId' }
    $ubr = Reg-Value $HKLM $cv 'UBR' 'DWord'
    $editionId = Reg-Value $HKLM $cv 'EditionID'
    $caption = S $os.Caption
    $build = S $os.BuildNumber
    if ($caption -and $caption -match 'Windows 10' -and $build -and [int]$build -ge 22000) { $caption = $caption -replace 'Windows 10', 'Windows 11' }
    $data.OS = @{
        Caption         = $caption
        Version         = S $os.Version
        BuildNumber     = $build
        UBR             = $ubr
        DisplayVersion  = S $displayVersion
        EditionId       = S $editionId
        ServicePack     = S $os.CSDVersion
        Architecture    = S $os.OSArchitecture
        InstallDate     = D $os.InstallDate
        LastBoot        = D $os.LastBootUpTime
        LocalDateTime   = D $os.LocalDateTime
        RegisteredUser  = S $os.RegisteredUser
        Organization    = S $os.Organization
        SerialNumber    = S $os.SerialNumber
        ProductType     = $os.ProductType
        WindowsDirectory = S $os.WindowsDirectory
        SystemDrive     = S $os.SystemDrive
        Locale          = S $os.Locale
        Language        = $os.OSLanguage
        TimeZoneMinutes = $os.CurrentTimeZone
        FreePhysicalKB  = $os.FreePhysicalMemory
        TotalVirtualKB  = $os.TotalVirtualMemorySize
        FreeVirtualKB   = $os.FreeVirtualMemory
    }

    # ---------------------------------------------------------------- CPU
    $data.Processors = @(Q 'Win32_Processor' | ForEach-Object {
        @{
            Name            = S $_.Name
            Description     = S $_.Description
            Manufacturer    = S $_.Manufacturer
            CurrentClock    = $_.CurrentClockSpeed
            MaxClock        = $_.MaxClockSpeed
            ExtClock        = $_.ExtClock
            Socket          = S $_.SocketDesignation
            Cores           = $_.NumberOfCores
            Threads         = $_.NumberOfLogicalProcessors
            L2CacheKB       = $_.L2CacheSize
            L3CacheKB       = $_.L3CacheSize
            Voltage         = $_.CurrentVoltage
            Architecture    = $_.Architecture
            AddressWidth    = $_.AddressWidth
            ProcessorId     = S $_.ProcessorId
            Virtualization  = $_.VirtualizationFirmwareEnabled
        }
    })

    # ---------------------------------------------------------------- memory
    $arrays = Q 'Win32_PhysicalMemoryArray'
    $slots = 0; $maxCap = 0
    foreach ($a in $arrays) {
        if ($a.Use -eq 3 -or $null -eq $a.Use) {
            $slots += [int]$a.MemoryDevices
            if ($a.MaxCapacityEx) { $maxCap += [double]$a.MaxCapacityEx * 1024 } elseif ($a.MaxCapacity) { $maxCap += [double]$a.MaxCapacity * 1024 }
        }
    }
    $data.Memory = @{
        Slots       = $slots
        MaxCapacity = $maxCap
        Modules = @(Q 'Win32_PhysicalMemory' | ForEach-Object {
            $mt = $_.SMBIOSMemoryType
            if (-not $mt) { $mt = $_.MemoryType }
            @{
                BankLabel     = S $_.BankLabel
                DeviceLocator = S $_.DeviceLocator
                Capacity      = $_.Capacity
                Speed         = $_.Speed
                ConfiguredSpeed = $_.ConfiguredClockSpeed
                Manufacturer  = S $_.Manufacturer
                PartNumber    = S $_.PartNumber
                SerialNumber  = S $_.SerialNumber
                FormFactor    = $_.FormFactor
                MemoryType    = $mt
            }
        })
    }

    # ---------------------------------------------------------------- video / monitors / audio
    $data.Video = @(Q 'Win32_VideoController' | ForEach-Object {
        @{
            Name          = S $_.Name
            Processor     = S $_.VideoProcessor
            AdapterRAM    = $_.AdapterRAM
            DriverVersion = S $_.DriverVersion
            DriverDate    = D $_.DriverDate
            HRes          = $_.CurrentHorizontalResolution
            VRes          = $_.CurrentVerticalResolution
            Bits          = $_.CurrentBitsPerPixel
            Refresh       = $_.CurrentRefreshRate
            PnpId         = S $_.PNPDeviceID
        }
    })
    # точный объём видеопамяти (AdapterRAM ограничен 4 ГБ)
    try {
        $vkeys = Reg-Keys $HKLM 'SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        foreach ($vk in $vkeys) {
            if ($vk -notmatch '^\d{4}$') { continue }
            $p = 'SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\' + $vk
            $desc = Reg-Value $HKLM $p 'DriverDesc'
            $mem = Reg-Value $HKLM $p 'HardwareInformation.qwMemorySize'
            if ($desc -and $mem) {
                foreach ($v in $data.Video) {
                    if ($v.Name -eq $desc) {
                        if ($mem -is [byte[]]) { $mem = [BitConverter]::ToUInt64($mem, 0) }
                        try { $v.AdapterRAM = [double]$mem } catch { }
                    }
                }
            }
        }
    } catch { }

    $sizes = @{}
    foreach ($bp in (Q 'WmiMonitorBasicDisplayParams' 'root\wmi')) {
        $h = [double]$bp.MaxHorizontalImageSize; $v = [double]$bp.MaxVerticalImageSize
        if ($h -gt 0 -and $v -gt 0) { $sizes[[string]$bp.InstanceName] = [math]::Round([math]::Sqrt($h * $h + $v * $v) / 2.54, 1) }
    }
    $data.Monitors = @(Q 'WmiMonitorID' 'root\wmi' | ForEach-Object {
        @{
            Manufacturer = Chars $_.ManufacturerName
            Name         = Chars $_.UserFriendlyName
            ProductCode  = Chars $_.ProductCodeID
            SerialNumber = Chars $_.SerialNumberID
            Year         = $_.YearOfManufacture
            Diagonal     = $sizes[[string]$_.InstanceName]
        }
    })

    $data.Audio = @(Q 'Win32_SoundDevice' | ForEach-Object {
        @{ Name = S $_.Name; Manufacturer = S $_.Manufacturer; Status = S $_.Status }
    })

    # ---------------------------------------------------------------- storage
    $physical = @{}
    foreach ($pd in (Q 'MSFT_PhysicalDisk' 'root\Microsoft\Windows\Storage')) {
        $mt = switch ([int]$pd.MediaType) { 3 { 'HDD' } 4 { 'SSD' } 5 { 'SCM' } default { $null } }
        $bt = switch ([int]$pd.BusType) { 1 {'SCSI'} 3 {'ATA'} 6 {'Fibre Channel'} 7 {'USB'} 8 {'RAID'} 10 {'SAS'} 11 {'SATA'} 12 {'SD'} 13 {'MMC'} 15 {'File Backed Virtual'} 16 {'Storage Spaces'} 17 {'NVMe'} default { $null } }
        $physical[[string]$pd.DeviceId] = @{ MediaType = $mt; BusType = $bt; Health = [int]$pd.HealthStatus }
    }
    $smart = @{}
    foreach ($fp in (Q 'MSStorageDriver_FailurePredictStatus' 'root\wmi')) { $smart[[string]$fp.InstanceName] = [bool]$fp.PredictFailure }
    $data.Disks = @(Q 'Win32_DiskDrive' | ForEach-Object {
        $pi = $physical[[string]$_.Index]
        $pred = $null
        foreach ($k in $smart.Keys) { if ($_.PNPDeviceID -and $k.StartsWith([string]$_.PNPDeviceID, [StringComparison]::OrdinalIgnoreCase)) { $pred = $smart[$k] } }
        @{
            Index        = $_.Index
            Model        = S $_.Model
            Size         = $_.Size
            Interface    = S $_.InterfaceType
            MediaType    = S $_.MediaType
            Kind         = $(if ($pi) { $pi.MediaType } else { $null })
            Bus          = $(if ($pi) { $pi.BusType } else { $null })
            SerialNumber = S $_.SerialNumber
            Firmware     = S $_.FirmwareRevision
            Partitions   = $_.Partitions
            Status       = S $_.Status
            SmartFailure = $pred
        }
    })
    $data.LogicalDisks = @(Q 'Win32_LogicalDisk' | ForEach-Object {
        @{
            Letter     = S $_.DeviceID
            Label      = S $_.VolumeName
            FileSystem = S $_.FileSystem
            Size       = $_.Size
            Free       = $_.FreeSpace
            DriveType  = $_.DriveType
            Serial     = S $_.VolumeSerialNumber
            Provider   = S $_.ProviderName
        }
    })
    $data.Optical = @(Q 'Win32_CDROMDrive' | ForEach-Object { @{ Name = S $_.Name; Drive = S $_.Drive; Manufacturer = S $_.Manufacturer } })
    try {
        $bl = Q 'Win32_EncryptableVolume' 'root\cimv2\Security\MicrosoftVolumeEncryption'
        $data.BitLocker = @($bl | ForEach-Object { @{ Drive = S $_.DriveLetter; Protection = $_.ProtectionStatus; Conversion = $_.ConversionStatus } })
    } catch { $data.BitLocker = @() }

    # ---------------------------------------------------------------- network
    $cfgs = @{}
    foreach ($c in (Q 'Win32_NetworkAdapterConfiguration')) { $cfgs[[string]$c.Index] = $c }
    $data.Network = @(Q 'Win32_NetworkAdapter' | Where-Object { $_.PhysicalAdapter -or ($cfgs[[string]$_.Index] -and $cfgs[[string]$_.Index].IPEnabled) } | ForEach-Object {
        $c = $cfgs[[string]$_.Index]
        $ips = @(); $masks = @(); $gw = @(); $dns = @(); $dhcp = $null; $dhcpSrv = $null; $ipEnabled = $false
        if ($c) {
            $ipEnabled = [bool]$c.IPEnabled
            if ($c.IPAddress) { $ips = @($c.IPAddress) }
            if ($c.IPSubnet) { $masks = @($c.IPSubnet) }
            if ($c.DefaultIPGateway) { $gw = @($c.DefaultIPGateway) }
            if ($c.DNSServerSearchOrder) { $dns = @($c.DNSServerSearchOrder) }
            $dhcp = [bool]$c.DHCPEnabled
            $dhcpSrv = S $c.DHCPServer
        }
        @{
            Name         = S $_.Name
            ConnectionId = S $_.NetConnectionID
            Manufacturer = S $_.Manufacturer
            MAC          = S $_.MACAddress
            Speed        = $_.Speed
            Status       = $_.NetConnectionStatus
            Physical     = [bool]$_.PhysicalAdapter
            IpEnabled    = $ipEnabled
            IPs          = $ips
            Masks        = $masks
            Gateways     = $gw
            Dns          = $dns
            Dhcp         = $dhcp
            DhcpServer   = $dhcpSrv
        }
    })

    # ---------------------------------------------------------------- peripherals
    $data.Printers = @(Q 'Win32_Printer' | ForEach-Object {
        @{ Name = S $_.Name; Driver = S $_.DriverName; Port = S $_.PortName; Default = [bool]$_.Default; Network = [bool]$_.Network; Shared = [bool]$_.Shared; ShareName = S $_.ShareName; Location = S $_.Location }
    })
    $data.Keyboards = @(Q 'Win32_Keyboard' | ForEach-Object { @{ Name = S $_.Description; Layout = S $_.Layout } })
    $data.Mice = @(Q 'Win32_PointingDevice' | ForEach-Object { @{ Name = S $_.Name; Manufacturer = S $_.Manufacturer; Buttons = $_.NumberOfButtons } })
    $data.Usb = @(Q 'Win32_PnPEntity' 'root\cimv2' "PNPDeviceID LIKE 'USB%'" | Where-Object { $_.Name } | ForEach-Object {
        @{ Name = S $_.Name; Manufacturer = S $_.Manufacturer; Class = S $_.PNPClass; DeviceId = S $_.PNPDeviceID }
    })

    $data.Devices = @(Q 'Win32_PnPEntity' | Where-Object { $_.Name } | ForEach-Object {
        @{
            Name         = S $_.Name
            Class        = S $_.PNPClass
            Manufacturer = S $_.Manufacturer
            ErrorCode    = $_.ConfigManagerErrorCode
            Status       = S $_.Status
        }
    })

    $data.Battery = @(Q 'Win32_Battery' | ForEach-Object {
        @{ Name = S $_.Name; DeviceId = S $_.DeviceID; Chemistry = $_.Chemistry; Charge = $_.EstimatedChargeRemaining; Status = $_.BatteryStatus; Voltage = $_.DesignVoltage }
    })
    try {
        $bs = Q 'BatteryStaticData' 'root\wmi' | Select-Object -First 1
        $bf = Q 'BatteryFullChargedCapacity' 'root\wmi' | Select-Object -First 1
        if ($data.Battery.Count -gt 0 -and $bs) {
            $data.Battery[0].DesignCapacity = $bs.DesignedCapacity
            $data.Battery[0].Manufacturer = S $bs.ManufactureName
            $data.Battery[0].SerialNumber = S $bs.SerialNumber
            if ($bf) { $data.Battery[0].FullCapacity = $bf.FullChargedCapacity }
        }
    } catch { }

    try {
        $tpm = Q 'Win32_Tpm' 'root\cimv2\Security\MicrosoftTpm' | Select-Object -First 1
        if ($tpm) {
            $data.Tpm = @{ Present = $true; Enabled = $tpm.IsEnabled_InitialValue; Activated = $tpm.IsActivated_InitialValue; Version = S $tpm.SpecVersion; Manufacturer = S $tpm.ManufacturerIdTxt }
        } else { $data.Tpm = @{ Present = $false } }
    } catch { $data.Tpm = @{ Present = $false } }

    # ---------------------------------------------------------------- software
    $software = New-Object System.Collections.ArrayList
    $seen = @{}
    $roots = @(
        @{ Hive = $HKLM; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Arch = 'x64'; User = $null },
        @{ Hive = $HKLM; Path = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Arch = 'x86'; User = $null }
    )
    foreach ($sid in (Reg-Keys $HKU '')) {
        if ($sid -match '^S-1-5-21-[\d\-]+$') {
            $roots += @{ Hive = $HKU; Path = "$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall"; Arch = 'user'; User = $sid }
        }
    }
    foreach ($r in $roots) {
        foreach ($sub in (Reg-Keys $r.Hive $r.Path)) {
            $vals = Reg-Values $r.Hive ($r.Path + '\' + $sub)
            $name = S $vals['DisplayName']
            if (-not $name) { continue }
            if ($vals['SystemComponent'] -eq 1) { continue }
            if ($vals['ParentKeyName'] -or $vals['ReleaseType'] -match 'Update|Hotfix') { continue }
            $ver = S $vals['DisplayVersion']
            $key = ('{0}|{1}|{2}' -f $name, $ver, $r.Arch)
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $size = $null
            if ($vals['EstimatedSize']) { $size = [double]$vals['EstimatedSize'] * 1024 }
            [void]$software.Add(@{
                Name            = $name
                Version         = $ver
                Publisher       = S $vals['Publisher']
                InstallDate     = S $vals['InstallDate']
                InstallLocation = S $vals['InstallLocation']
                InstallSource   = S $vals['InstallSource']
                Uninstall       = S $vals['UninstallString']
                Size            = $size
                Url             = $(if ($vals['URLInfoAbout']) { S $vals['URLInfoAbout'] } else { S $vals['HelpLink'] })
                Arch            = $r.Arch
                UserSid         = $r.User
                KeyName         = $sub
            })
        }
    }
    $data.Software = @($software | Sort-Object { $_.Name })

    # ---------------------------------------------------------------- updates
    $data.Hotfixes = @(Q 'Win32_QuickFixEngineering' | ForEach-Object {
        $hf = $_
        $d = $null
        try { if ($hf.InstalledOn) { $d = D ([datetime]$hf.InstalledOn) } } catch { $d = S $hf.InstalledOn }
        @{ Id = S $hf.HotFixID; Description = S $hf.Description; InstalledOn = $d; InstalledBy = S $hf.InstalledBy }
    })
    $data.UpdateHistory = @()
    if ($ScanUpdates -and -not $isRemoteCim) {
        try {
            $session = New-Object -ComObject 'Microsoft.Update.Session'
            $searcher = $session.CreateUpdateSearcher()
            $count = $searcher.GetTotalHistoryCount()
            if ($count -gt 0) {
                $hist = $searcher.QueryHistory(0, [math]::Min($count, 300))
                $list = New-Object System.Collections.ArrayList
                foreach ($h in $hist) {
                    if (-not $h.Title) { continue }
                    $res = switch ([int]$h.ResultCode) { 1 {'В процессе'} 2 {'Успешно'} 3 {'Успешно с ошибками'} 4 {'Ошибка'} 5 {'Отменено'} default {'Неизвестно'} }
                    $op  = switch ([int]$h.Operation) { 1 {'Установка'} 2 {'Удаление'} 3 {'Другое'} default {''} }
                    [void]$list.Add(@{ Title = S $h.Title; Date = D $h.Date; Result = $res; Operation = $op; HResult = ('0x{0:X8}' -f $h.HResult) })
                }
                $data.UpdateHistory = @($list)
            }
        } catch { }
    }

    # ---------------------------------------------------------------- security
    $av = @(Q 'AntiVirusProduct' 'root\SecurityCenter2' | ForEach-Object {
        $hex = '{0:x6}' -f [int]$_.productState
        @{ Name = S $_.displayName; Enabled = ($hex.Substring(2, 2) -eq '10' -or $hex.Substring(2, 2) -eq '11'); UpToDate = ($hex.Substring(4, 2) -eq '00'); Path = S $_.pathToSignedProductExe; State = $_.productState }
    })
    $as = @(Q 'AntiSpywareProduct' 'root\SecurityCenter2' | ForEach-Object {
        $hex = '{0:x6}' -f [int]$_.productState
        @{ Name = S $_.displayName; Enabled = ($hex.Substring(2, 2) -eq '10' -or $hex.Substring(2, 2) -eq '11'); UpToDate = ($hex.Substring(4, 2) -eq '00') }
    })
    $fwp = @(Q 'FirewallProduct' 'root\SecurityCenter2' | ForEach-Object {
        $hex = '{0:x6}' -f [int]$_.productState
        @{ Name = S $_.displayName; Enabled = ($hex.Substring(2, 2) -eq '10' -or $hex.Substring(2, 2) -eq '11') }
    })
    $fw = @()
    foreach ($pr in @(@('DomainProfile','Доменный'), @('StandardProfile','Частный'), @('PublicProfile','Общедоступный'))) {
        $v = Reg-Value $HKLM ('SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\' + $pr[0]) 'EnableFirewall' 'DWord'
        if ($null -ne $v) { $fw += @{ Profile = $pr[1]; Enabled = ([int]$v -eq 1) } }
    }
    $uac = Reg-Value $HKLM 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA' 'DWord'
    $au  = Reg-Value $HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 'DWord'
    $rdp = Reg-Value $HKLM 'SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 'DWord'
    $data.Security = @{
        Antivirus     = $av
        Antispyware   = $as
        FirewallProducts = $fwp
        Firewall      = $fw
        Uac           = $(if ($null -eq $uac) { $null } else { [int]$uac -eq 1 })
        AutoUpdate    = $(if ($null -eq $au) { $true } else { [int]$au -ne 1 })
        RdpEnabled    = $(if ($null -eq $rdp) { $null } else { [int]$rdp -eq 0 })
    }

    # ---------------------------------------------------------------- license keys
    $keys = @()
    $dpid = Reg-Value $HKLM $cv 'DigitalProductId' 'Binary'
    if ($dpid) {
        $k = Decode-ProductKey ([byte[]]@($dpid))
        if ($k) { $keys += @{ Product = $data.OS.Caption; Key = $k; Source = 'Реестр' } }
    }
    try {
        $sls = Q 'SoftwareLicensingService' | Select-Object -First 1
        if ($sls -and $sls.OA3xOriginalProductKey) { $keys += @{ Product = ($data.OS.Caption + ' (OEM)'); Key = S $sls.OA3xOriginalProductKey; Source = 'BIOS/UEFI' } }
    } catch { }
    $data.ProductKeys = $keys

    # ---------------------------------------------------------------- other
    $data.Shares = @(Q 'Win32_Share' | ForEach-Object {
        $t = switch ([int64]$_.Type) { 0 {'Диск'} 1 {'Очередь печати'} 2 {'Устройство'} 3 {'IPC'} 2147483648 {'Диск (адм.)'} 2147483649 {'Очередь печати (адм.)'} 2147483651 {'IPC (адм.)'} default { [string]$_.Type } }
        @{ Name = S $_.Name; Path = S $_.Path; Description = S $_.Description; Type = $t }
    })
    $data.Environment = @(Q 'Win32_Environment' | ForEach-Object {
        @{ Name = S $_.Name; Value = S $_.VariableValue; User = S $_.UserName; System = [bool]$_.SystemVariable }
    })
    $data.Startup = @(Q 'Win32_StartupCommand' | ForEach-Object {
        @{ Name = S $_.Name; Command = S $_.Command; Location = S $_.Location; User = S $_.User }
    })
    $data.Services = @(Q 'Win32_Service' | ForEach-Object {
        @{ Name = S $_.Name; DisplayName = S $_.DisplayName; State = S $_.State; StartMode = S $_.StartMode; Account = S $_.StartName; Path = S $_.PathName; Description = S $_.Description }
    })
    $data.Processes = @(Q 'Win32_Process' | ForEach-Object {
        @{ Name = S $_.Name; Pid = $_.ProcessId; Path = S $_.ExecutablePath; Memory = $_.WorkingSetSize; Threads = $_.ThreadCount }
    })
    $data.Users = @(Q 'Win32_UserAccount' 'root\cimv2' 'LocalAccount=True' | ForEach-Object {
        @{ Name = S $_.Name; FullName = S $_.FullName; Description = S $_.Description; Disabled = [bool]$_.Disabled; Lockout = [bool]$_.Lockout; PasswordRequired = [bool]$_.PasswordRequired; PasswordExpires = [bool]$_.PasswordExpires; Sid = S $_.SID }
    })
    $groups = @()
    foreach ($g in (Q 'Win32_Group' 'root\cimv2' 'LocalAccount=True')) {
        $members = @()
        try {
            $ap = @{ InputObject = $g; ResultClassName = 'Win32_Account'; ErrorAction = 'Stop' }
            if ($isRemoteCim) { $ap['CimSession'] = $CimSession }
            $members = @(Get-CimAssociatedInstance @ap | ForEach-Object { '{0}\{1}' -f $_.Domain, $_.Name })
        } catch { }
        $groups += @{ Name = S $g.Name; Description = S $g.Description; Sid = S $g.SID; Members = $members }
    }
    $data.Groups = $groups

    $fonts = @()
    $fv = Reg-Values $HKLM 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    foreach ($fk in ($fv.Keys | Sort-Object)) { $fonts += @{ Name = [string]$fk; File = [string]$fv[$fk] } }
    $data.Fonts = $fonts

    $data.Meta = @{
        Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        Method    = $Method
        Errors    = @($errors)
    }
    return $data
}

function Test-IsLocalComputer {
    param([string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return $true }
    $t = $Target.Trim().ToLowerInvariant()
    if ($t -in @('localhost', '127.0.0.1', '::1', '.')) { return $true }
    $names = @($env:COMPUTERNAME.ToLowerInvariant())
    try { $names += [System.Net.Dns]::GetHostName().ToLowerInvariant() } catch { }
    if ($names -contains $t) { return $true }
    if ($t.Split('.')[0] -in $names -and $t -notmatch '^\d') { return $true }
    try {
        foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            foreach ($ua in $ni.GetIPProperties().UnicastAddresses) {
                if ($ua.Address.ToString() -eq $t) { return $true }
            }
        }
    } catch { }
    return $false
}

function Invoke-InventoryCollection {
    # Возвращает @{ Ok; Data; Method; Error }
    param(
        [string]$Target,
        [System.Management.Automation.PSCredential]$Credential = $null,
        [bool]$DisableDcom = $false,
        [bool]$ScanUpdates = $true,
        [int]$UpdatesTimeoutSec = 600
    )
    if (Test-IsLocalComputer $Target) {
        try {
            $d = & $script:CollectorScript -CimSession $null -ScanUpdates $ScanUpdates -UpdatesTimeoutSec $UpdatesTimeoutSec -Method 'Локальный'
            return @{ Ok = $true; Data = $d; Method = 'Локальный' }
        } catch { return @{ Ok = $false; Error = $_.Exception.Message } }
    }

    $errs = @()
    # 1) PowerShell Remoting (WinRM): сбор выполняется на самом компьютере
    try {
        $p = @{ ComputerName = $Target; ScriptBlock = $script:CollectorScript; ArgumentList = @($null, $ScanUpdates, $UpdatesTimeoutSec, 'WinRM'); ErrorAction = 'Stop' }
        if ($Credential) { $p['Credential'] = $Credential }
        $so = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout ([Math]::Max(120000, $UpdatesTimeoutSec * 1000))
        $p['SessionOption'] = $so
        $d = Invoke-Command @p
        if ($d) { return @{ Ok = $true; Data = $d; Method = 'WinRM' } }
    } catch { $errs += ('WinRM: ' + $_.Exception.Message) }

    # 2) WMI через DCOM
    if (-not $DisableDcom) {
        $s = $null
        try {
            $opt = New-CimSessionOption -Protocol Dcom
            $p = @{ ComputerName = $Target; SessionOption = $opt; ErrorAction = 'Stop'; OperationTimeoutSec = 30 }
            if ($Credential) { $p['Credential'] = $Credential }
            $s = New-CimSession @p
            $d = & $script:CollectorScript -CimSession $s -ScanUpdates $false -UpdatesTimeoutSec 0 -Method 'WMI (DCOM)'
            return @{ Ok = $true; Data = $d; Method = 'WMI (DCOM)' }
        } catch { $errs += ('DCOM: ' + $_.Exception.Message) }
        finally { if ($s) { Remove-CimSession $s -ErrorAction SilentlyContinue } }
    }
    return @{ Ok = $false; Error = ($errs -join ' | ') }
}
