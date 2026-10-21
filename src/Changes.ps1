# Changes.ps1 — журнал изменений: сравнение соседних снимков устройства

# Каждая категория: Id, группа, подпись, иконка и функция извлечения
# (возвращает словарь «идентификатор элемента» -> «описание/значение»)
$script:ChangeCategories = @(
    @{ Id = 'cpu';      Group = 'Оборудование'; Name = 'Процессор';            Icon = 'cpu' }
    @{ Id = 'memmod';   Group = 'Оборудование'; Name = 'Модуль памяти';        Icon = 'memory' }
    @{ Id = 'ram';      Group = 'Оборудование'; Name = 'Оперативная память';   Icon = 'memory' }
    @{ Id = 'video';    Group = 'Оборудование'; Name = 'Видеоадаптер';         Icon = 'video' }
    @{ Id = 'monitor';  Group = 'Оборудование'; Name = 'Монитор';              Icon = 'monitor' }
    @{ Id = 'audio';    Group = 'Оборудование'; Name = 'Звуковое устройство';  Icon = 'audio' }
    @{ Id = 'disk';     Group = 'Оборудование'; Name = 'Накопитель';           Icon = 'disk' }
    @{ Id = 'volume';   Group = 'Оборудование'; Name = 'Раздел';               Icon = 'volume' }
    @{ Id = 'cdrom';    Group = 'Оборудование'; Name = 'CD-привод';            Icon = 'cdrom' }
    @{ Id = 'nic';      Group = 'Оборудование'; Name = 'Сетевой адаптер';      Icon = 'network' }
    @{ Id = 'printer';  Group = 'Оборудование'; Name = 'Принтер';              Icon = 'printer' }
    @{ Id = 'keyboard'; Group = 'Оборудование'; Name = 'Клавиатура';           Icon = 'keyboard' }
    @{ Id = 'mouse';    Group = 'Оборудование'; Name = 'Указывающее устройство'; Icon = 'mouse' }
    @{ Id = 'usb';      Group = 'Оборудование'; Name = 'USB-устройство';       Icon = 'usb' }
    @{ Id = 'pnp';      Group = 'Оборудование'; Name = 'Windows устройство';   Icon = 'devices' }
    @{ Id = 'battery';  Group = 'Оборудование'; Name = 'Батарея';              Icon = 'battery' }
    @{ Id = 'os';       Group = 'Программы';    Name = 'Операционная система'; Icon = 'os' }
    @{ Id = 'sw';       Group = 'Программы';    Name = 'ПО';                   Icon = 'software' }
    @{ Id = 'hotfix';   Group = 'Программы';    Name = 'Обновление';           Icon = 'hotfix' }
    @{ Id = 'wu';       Group = 'Программы';    Name = 'Обновление Windows';   Icon = 'winupdate' }
    @{ Id = 'av';       Group = 'Программы';    Name = 'Антивирус';            Icon = 'shield' }
    @{ Id = 'fw';       Group = 'Программы';    Name = 'Брандмауэр';           Icon = 'firewall' }
    @{ Id = 'share';    Group = 'Другое';       Name = 'Ресурс';               Icon = 'share' }
    @{ Id = 'font';     Group = 'Другое';       Name = 'Шрифт';                Icon = 'font' }
    @{ Id = 'startup';  Group = 'Другое';       Name = 'Автозапуск';           Icon = 'startup' }
    @{ Id = 'service';  Group = 'Другое';       Name = 'Служба';               Icon = 'service' }
    @{ Id = 'user';     Group = 'Другое';       Name = 'Учетная запись';       Icon = 'user' }
    @{ Id = 'group';    Group = 'Другое';       Name = 'Группа';               Icon = 'group' }
    @{ Id = 'key';      Group = 'Другое';       Name = 'Лицензия';             Icon = 'key' }
)

function Get-ChangeItems {
    # Возвращает упорядоченный словарь id -> @{ Name; Value }
    param($Data, [string]$CategoryId)
    $d = [ordered]@{}
    function Add-I([string]$id, [string]$name, [string]$value) {
        if (-not $id) { return }
        $k = $id; $n = 2
        while ($d.Contains($k)) { $k = $id + '#' + $n; $n++ }
        $d[$k] = @{ Name = $name; Value = $value }
    }
    switch ($CategoryId) {
        'cpu'      { foreach ($x in (As-Array (Get-Val $Data 'Processors'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ('{0} ядер / {1} потоков' -f (Get-Val $x 'Cores'), (Get-Val $x 'Threads')) } }
        'memmod'   { foreach ($x in (As-Array (Get-Val $Data 'Memory' 'Modules'))) { $loc = [string](Get-Val $x 'DeviceLocator'); Add-I $loc ('{0}: {1}' -f $loc, (Format-Bytes (Get-Val $x 'Capacity'))) ('{0} {1} {2}' -f (Format-Bytes (Get-Val $x 'Capacity')), (Get-Val $x 'Manufacturer'), (Get-Val $x 'PartNumber')).Trim() } }
        'ram'      { $t = Get-Val $Data 'System' 'TotalMemory'; if ($t) { Add-I 'ram' 'Объём оперативной памяти' (Format-Bytes $t 0) } }
        'video'    { foreach ($x in (As-Array (Get-Val $Data 'Video'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ('{0}, драйвер {1}' -f (Format-Bytes (Get-Val $x 'AdapterRAM') 0), (Get-Val $x 'DriverVersion')) } }
        'monitor'  { foreach ($x in (As-Array (Get-Val $Data 'Monitors'))) { $n = ('{0} {1}' -f (Get-Val $x 'Manufacturer'), (Get-Val $x 'Name')).Trim(); Add-I ($n + '|' + (Get-Val $x 'SerialNumber')) $n ('S/N ' + (Get-Val $x 'SerialNumber')) } }
        'audio'    { foreach ($x in (As-Array (Get-Val $Data 'Audio'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ([string](Get-Val $x 'Manufacturer')) } }
        'disk'     { foreach ($x in (As-Array (Get-Val $Data 'Disks'))) { $n = [string](Get-Val $x 'Model'); Add-I ($n + '|' + (Get-Val $x 'SerialNumber')) $n ('{0}, S/N {1}' -f (Format-Bytes (Get-Val $x 'Size') 0), (Get-Val $x 'SerialNumber')) } }
        'volume'   { foreach ($x in (As-Array (Get-Val $Data 'LogicalDisks'))) { $l = [string](Get-Val $x 'Letter'); Add-I $l ('Диск ' + $l) ('{0} {1} {2}' -f (Get-Val $x 'Label'), (Get-Val $x 'FileSystem'), (Format-Bytes (Get-Val $x 'Size') 0)).Trim() } }
        'cdrom'    { foreach ($x in (As-Array (Get-Val $Data 'Optical'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ([string](Get-Val $x 'Drive')) } }
        'nic'      { foreach ($x in (As-Array (Get-Val $Data 'Network'))) { if (-not (Get-Val $x 'Physical')) { continue }; Add-I ([string](Get-Val $x 'MAC') + '|' + (Get-Val $x 'Name')) (Get-Val $x 'Name') ('MAC {0}; IP {1}' -f (Get-Val $x 'MAC'), ((As-Array (Get-Val $x 'IPs')) -join ', ')) } }
        'printer'  { foreach ($x in (As-Array (Get-Val $Data 'Printers'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ('{0}, {1}' -f (Get-Val $x 'Driver'), (Get-Val $x 'Port')) } }
        'keyboard' { foreach ($x in (As-Array (Get-Val $Data 'Keyboards'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') '' } }
        'mouse'    { foreach ($x in (As-Array (Get-Val $Data 'Mice'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ([string](Get-Val $x 'Manufacturer')) } }
        'usb'      { foreach ($x in (As-Array (Get-Val $Data 'Usb'))) { Add-I ([string](Get-Val $x 'DeviceId')) (Get-Val $x 'Name') ([string](Get-Val $x 'Manufacturer')) } }
        'pnp'      { foreach ($x in (As-Array (Get-Val $Data 'Devices'))) { Add-I ([string](Get-Val $x 'Name') + '|' + (Get-Val $x 'Class')) (Get-Val $x 'Name') ('{0}; код ошибки {1}' -f (Get-Val $x 'Class'), (Get-Val $x 'ErrorCode')) } }
        'battery'  { foreach ($x in (As-Array (Get-Val $Data 'Battery'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ('Ёмкость {0} / {1}' -f (Get-Val $x 'FullCapacity'), (Get-Val $x 'DesignCapacity')) } }
        'os'       { $o = Get-Val $Data 'OS'; if ($o) { Add-I 'os' 'Операционная система' ('{0} {1} (сборка {2}.{3})' -f (Get-Val $o 'Caption'), (Get-Val $o 'DisplayVersion'), (Get-Val $o 'BuildNumber'), (Get-Val $o 'UBR')) } }
        'sw'       { foreach ($x in (As-Array (Get-Val $Data 'Software'))) { $n = [string](Get-Val $x 'Name'); Add-I ((Get-NormalizedSoftwareName $n) + '|' + (Get-Val $x 'Arch')) $n ([string](Get-Val $x 'Version')) } }
        'hotfix'   { foreach ($x in (As-Array (Get-Val $Data 'Hotfixes'))) { Add-I ([string](Get-Val $x 'Id')) (Get-Val $x 'Id') ([string](Get-Val $x 'Description')) } }
        'wu'       { foreach ($x in (As-Array (Get-Val $Data 'UpdateHistory'))) { if ((Get-Val $x 'Result') -notlike 'Успешно*') { continue }; Add-I ([string](Get-Val $x 'Title')) (Get-Val $x 'Title') ([string](Get-Val $x 'Operation')) } }
        'av'       { foreach ($x in (As-Array (Get-Val $Data 'Security' 'Antivirus'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ('включен: {0}; базы актуальны: {1}' -f (Format-YesNo (Get-Val $x 'Enabled')), (Format-YesNo (Get-Val $x 'UpToDate'))) } }
        'fw'       { foreach ($x in (As-Array (Get-Val $Data 'Security' 'Firewall'))) { Add-I ([string](Get-Val $x 'Profile')) ('Профиль: ' + (Get-Val $x 'Profile')) ('включен: ' + (Format-YesNo (Get-Val $x 'Enabled'))) } }
        'share'    { foreach ($x in (As-Array (Get-Val $Data 'Shares'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ([string](Get-Val $x 'Path')) } }
        'font'     { foreach ($x in (As-Array (Get-Val $Data 'Fonts'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ([string](Get-Val $x 'File')) } }
        'startup'  { foreach ($x in (As-Array (Get-Val $Data 'Startup'))) { $n = [string](Get-Val $x 'Name'); Add-I ($n + '|' + (Get-Val $x 'Location')) $n ([string](Get-Val $x 'Command')) } }
        'service'  { foreach ($x in (As-Array (Get-Val $Data 'Services'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'DisplayName') ('запуск: {0}' -f (Get-Val $x 'StartMode')) } }
        'user'     { foreach ($x in (As-Array (Get-Val $Data 'Users'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') ($(if (Get-Val $x 'Disabled') { 'отключена' } else { 'активна' })) } }
        'group'    { foreach ($x in (As-Array (Get-Val $Data 'Groups'))) { Add-I ([string](Get-Val $x 'Name')) (Get-Val $x 'Name') (((As-Array (Get-Val $x 'Members')) | Sort-Object) -join ', ') } }
        'key'      { foreach ($x in (As-Array (Get-Val $Data 'ProductKeys'))) { Add-I ([string](Get-Val $x 'Product')) (Get-Val $x 'Product') ([string](Get-Val $x 'Key')) } }
    }
    return $d
}

function Compare-DeviceSnapshots {
    param($Old, $New, [string[]]$CategoryIds)
    $changes = New-Object System.Collections.ArrayList
    foreach ($cid in $CategoryIds) {
        $cat = $script:ChangeCategories | Where-Object { $_.Id -eq $cid } | Select-Object -First 1
        $a = Get-ChangeItems $Old $cid
        $b = Get-ChangeItems $New $cid
        foreach ($k in @($b.PSBase.Keys)) {
            if (-not $a.Contains($k)) {
                [void]$changes.Add(@{ CategoryId = $cid; Category = $cat.Name; Change = 'Добавлено'; Item = [string]$b[$k].Name; Old = ''; New = [string]$b[$k].Value })
            } elseif ([string]$a[$k].Value -ne [string]$b[$k].Value) {
                [void]$changes.Add(@{ CategoryId = $cid; Category = $cat.Name; Change = 'Изменено'; Item = [string]$b[$k].Name; Old = [string]$a[$k].Value; New = [string]$b[$k].Value })
            }
        }
        foreach ($k in @($a.PSBase.Keys)) {
            if (-not $b.Contains($k)) {
                [void]$changes.Add(@{ CategoryId = $cid; Category = $cat.Name; Change = 'Удалено'; Item = [string]$a[$k].Name; Old = [string]$a[$k].Value; New = '' })
            }
        }
    }
    return $changes.ToArray()
}

function Get-DeviceChanges {
    # Изменения для набора устройств за период. Возвращает @{ Rows; Counts; DevicesWithHistory }
    param([array]$Devices, [datetime]$From, [datetime]$To, [string[]]$CategoryIds)
    $rows = New-Object System.Collections.ArrayList
    $counts = @{}
    $withHistory = 0
    foreach ($cid in $CategoryIds) { $counts[$cid] = 0 }
    foreach ($dev in $Devices) {
        $snaps = @(As-Array $dev['Snapshots'] | Sort-Object)
        if ($snaps.Count -lt 2) { continue }
        $withHistory++
        for ($i = 1; $i -lt $snaps.Count; $i++) {
            $dt = ConvertFrom-Stamp $snaps[$i]
            if ($null -eq $dt -or $dt -lt $From -or $dt -gt $To) { continue }
            $old = Get-DeviceSnapshot $dev $snaps[$i - 1]
            $new = Get-DeviceSnapshot $dev $snaps[$i]
            if (-not $old -or -not $new) { continue }
            foreach ($c in (Compare-DeviceSnapshots $old $new $CategoryIds)) {
                $c.Device = [string]$dev['Name']; $c.DeviceId = $dev['Id']; $c.Ip = [string]$dev['Ip']
                $c.Date = $dt; $c.PrevDate = ConvertFrom-Stamp $snaps[$i - 1]
                [void]$rows.Add($c)
                $counts[$c.CategoryId] = [int]$counts[$c.CategoryId] + 1
            }
        }
    }
    return @{ Rows = $rows.ToArray(); Counts = $counts; DevicesWithHistory = $withHistory }
}
