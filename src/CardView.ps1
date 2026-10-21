# CardView.ps1 — карточка устройства: категории и их содержимое (блоки свойств)

$script:CardCategories = @(
    @{ Id = 'general';   Group = '';             Name = 'Общая информация';        Icon = 'general' }
    @{ Id = 'alerts';    Group = '';             Name = 'Сигналы';                 Icon = 'alerts' }
    @{ Id = 'system';    Group = 'Оборудование'; Name = 'Система';                 Icon = 'system' }
    @{ Id = 'cpu';       Group = 'Оборудование'; Name = 'Процессор';               Icon = 'cpu' }
    @{ Id = 'memory';    Group = 'Оборудование'; Name = 'Системная память';        Icon = 'memory' }
    @{ Id = 'video';     Group = 'Оборудование'; Name = 'Видеосистема';            Icon = 'video' }
    @{ Id = 'audio';     Group = 'Оборудование'; Name = 'Аудиосистема';            Icon = 'audio' }
    @{ Id = 'storage';   Group = 'Оборудование'; Name = 'Хранение информации';     Icon = 'storage' }
    @{ Id = 'network';   Group = 'Оборудование'; Name = 'Сеть';                    Icon = 'network' }
    @{ Id = 'periph';    Group = 'Оборудование'; Name = 'Периферия';               Icon = 'printer' }
    @{ Id = 'devices';   Group = 'Оборудование'; Name = 'Устройства';              Icon = 'devices' }
    @{ Id = 'battery';   Group = 'Оборудование'; Name = 'Батарея';                 Icon = 'battery' }
    @{ Id = 'os';        Group = 'Программы';    Name = 'Операционная система';    Icon = 'os' }
    @{ Id = 'software';  Group = 'Программы';    Name = 'Программы';               Icon = 'software' }
    @{ Id = 'keys';      Group = 'Программы';    Name = 'Лицензионные ключи';      Icon = 'key' }
    @{ Id = 'hotfixes';  Group = 'Программы';    Name = 'Системные обновления';    Icon = 'hotfix' }
    @{ Id = 'wu';        Group = 'Программы';    Name = 'Обновления Windows';      Icon = 'winupdate' }
    @{ Id = 'wuhist';    Group = 'Программы';    Name = 'Журнал обновлений Windows'; Icon = 'winupdate' }
    @{ Id = 'security';  Group = 'Программы';    Name = 'Безопасность';            Icon = 'shield' }
    @{ Id = 'shares';    Group = 'Другое';       Name = 'Общие ресурсы';           Icon = 'share' }
    @{ Id = 'env';       Group = 'Другое';       Name = 'Переменные среды';        Icon = 'env' }
    @{ Id = 'fonts';     Group = 'Другое';       Name = 'Шрифты';                  Icon = 'font' }
    @{ Id = 'startup';   Group = 'Другое';       Name = 'Автозагрузка';            Icon = 'startup' }
    @{ Id = 'services';  Group = 'Другое';       Name = 'Службы';                  Icon = 'service' }
    @{ Id = 'processes'; Group = 'Другое';       Name = 'Запущенные процессы';     Icon = 'process' }
    @{ Id = 'users';     Group = 'Другое';       Name = 'Учетные записи';          Icon = 'user' }
    @{ Id = 'groups';    Group = 'Другое';       Name = 'Локальные группы';        Icon = 'group' }
    @{ Id = 'snapshot';  Group = '-';            Name = 'Детали по снимку';        Icon = 'snapshot' }
    @{ Id = 'special';   Group = '-';            Name = 'Специальная информация';  Icon = 'special' }
)

function Get-CardCategory {
    param([string]$Id)
    foreach ($c in $script:CardCategories) { if ($c.Id -eq $Id) { return $c } }
    return $null
}

# --------------------------------------------------------------- конструкторы
function New-Prop {
    param([string]$K, $V, [string]$V2 = '', [string]$Mark = '')
    return @{ K = $K; V = $(if ($null -eq $V) { '' } else { [string]$V }); V2 = $V2; Mark = $Mark }
}

function New-Block {
    param([string]$Title, [string]$Icon = '', [array]$Props = @(), [string]$Style = 'group', [string]$Extra = '', [bool]$Expanded = $true, [array]$Subs = @())
    $clean = @()
    $showEmpty = [bool](Get-Val $script:Settings 'Reports' 'ShowEmptyValues')
    foreach ($p in $Props) {
        if ($null -eq $p) { continue }
        if (-not $showEmpty -and [string]::IsNullOrWhiteSpace($p.V) -and -not $p.Mark) { continue }
        $clean += $p
    }
    return @{ Title = $Title; Icon = $Icon; Props = $clean; Style = $Style; Extra = $Extra; Expanded = $Expanded; Subs = $Subs }
}

function YesNoProp {
    param([string]$K, $Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    if ([bool]$Value) { return (New-Prop $K 'Да' '' 'yes') }
    return (New-Prop $K 'Нет' '' 'no')
}

function Join-NonEmpty {
    param([string]$Sep = ' ')
    return ((@($args) | Where-Object { $_ -ne $null -and [string]$_ -ne '' }) -join $Sep)
}

# --------------------------------------------------------------- категории
function Get-CardBlocks {
    param([string]$CategoryId, $Device, $Data)
    $d = $Data
    $B = New-Object System.Collections.ArrayList
    switch ($CategoryId) {
        'general' {
            $sys = Get-Val $d 'System'; $os = Get-Val $d 'OS'
            $online = $Device['Online']
            $statusMark = ''; $statusText = 'Неизвестно'
            if ($online -eq $true) { $statusMark = 'online'; $statusText = 'Онлайн' } elseif ($online -eq $false) { $statusMark = 'offline'; $statusText = 'Офлайн' }
            $wg = Get-Val $sys 'Domain'
            $wgKind = if (Get-Val $sys 'PartOfDomain') { 'Домен' } else { 'Рабочая группа' }
            [void]$B.Add((New-Block 'Инвентаризация' 'inventory' @(
                (New-Prop 'Дата создания' (Format-DateTimeRu $Device['Created']))
                (New-Prop 'Последнее сканирование' (Format-DateTimeRu $Device['LastScan']))
                (New-Prop 'Способ сканирования' $Device['LastMethod'])
                (New-Prop 'Закрепленный пользователь' $Device['AssignedUser'])
                (New-Prop 'Текущий пользователь' (Get-Val $sys 'UserName'))
                (New-Prop 'Имя' (Get-Val $sys 'Name'))
                (New-Prop 'Рабочая группа/домен' $wg ('(' + $wgKind + ')'))
                (New-Prop 'IP-адрес' $Device['Ip'])
                (New-Prop 'MAC адрес' $Device['Mac'])
                (New-Prop 'Расположение' $Device['Location'])
                (New-Prop 'Статус' $statusText '' $statusMark)
                (New-Prop 'Последний успешный пинг' (Format-DateTimeRu $Device['LastPing']))
            )))
            if ($os) {
                $osName = Get-Val $os 'Caption'
                [void]$B.Add((New-Block 'Операционная система' 'os' @(
                    (New-Prop 'Имя' $osName ('(' + (Get-Val $os 'Architecture') + ')'))
                    (New-Prop 'Версия' (Get-Val $os 'DisplayVersion'))
                    (New-Prop 'Пакет обновления' (Get-Val $os 'ServicePack'))
                    (New-Prop 'Сборка' (Join-NonEmpty '.' (Get-Val $os 'Version') (Get-Val $os 'UBR')))
                )))
            }
            $hw = @()
            if ($sys) {
                $hw += New-Prop 'Компьютерная система' (Get-Val $sys 'Manufacturer') (Get-Val $sys 'Model')
                $hw += New-Prop 'Серийный номер' (Get-Val $sys 'SerialNumber')
            }
            $cpus = @(As-Array (Get-Val $d 'Processors'))
            if ($cpus.Count -gt 0) { $hw += New-Prop 'Процессор' ('{0} x {1}' -f $cpus.Count, (Get-Val $cpus[0] 'Name')) ('(' + (Format-MHz (Get-Val $cpus[0] 'MaxClock')) + ')') }
            if ($sys) { $hw += New-Prop 'Материнская плата' (Join-NonEmpty ' ' (Get-Val $sys 'Board' 'Manufacturer')) (Get-Val $sys 'Board' 'Product') }
            $mods = @(As-Array (Get-Val $d 'Memory' 'Modules'))
            $modText = ''
            if ($mods.Count -gt 0) { $modText = '(' + ((@($mods | ForEach-Object { Format-Bytes (Get-Val $_ 'Capacity') 0 })) -join ' + ') + ')' }
            if ($sys) { $hw += New-Prop 'Системная память' (Format-Bytes (Get-Val $sys 'TotalMemory') 0) $modText }
            foreach ($v in (As-Array (Get-Val $d 'Video'))) { $hw += New-Prop 'Видеоадаптер' (Get-Val $v 'Name') ('(' + (Format-Bytes (Get-Val $v 'AdapterRAM') 0) + ')') }
            foreach ($m in (As-Array (Get-Val $d 'Monitors'))) {
                $dg = Get-Val $m 'Diagonal'
                $extra = Join-NonEmpty ', ' $(if ($dg) { '{0}"' -f $dg }) $(if (Get-Val $m 'SerialNumber') { 'серийный номер: ' + (Get-Val $m 'SerialNumber') })
                $hw += New-Prop 'Монитор' (Join-NonEmpty ' ' (Get-Val $m 'Manufacturer') (Get-Val $m 'Name')) $(if ($extra) { '(' + $extra + ')' } else { '' })
            }
            foreach ($k in (As-Array (Get-Val $d 'Disks'))) { $hw += New-Prop 'Накопитель' (Get-Val $k 'Model') ('(' + (Join-NonEmpty ', ' (Format-Bytes (Get-Val $k 'Size') 0) (Get-Val $k 'Kind')) + ')') }
            foreach ($o in (As-Array (Get-Val $d 'Optical'))) { $hw += New-Prop 'CD-привод' (Get-Val $o 'Name') }
            foreach ($a in (As-Array (Get-Val $d 'Audio'))) { $hw += New-Prop 'Звуковое устройство' (Get-Val $a 'Name') }
            foreach ($p in (As-Array (Get-Val $d 'Printers'))) {
                $flags = Join-NonEmpty ', ' $(if (Get-Val $p 'Default') { 'По умолчанию' }) (Get-Val $p 'Port')
                $hw += New-Prop 'Принтер' (Get-Val $p 'Name') $(if ($flags) { '(' + $flags + ')' } else { '' })
            }
            if ($hw.Count -gt 0) { [void]$B.Add((New-Block 'Сводка по оборудованию' 'system' $hw)) }
        }
        'alerts' {
            $al = @(Get-DeviceAlerts $d)
            if ($al.Count -eq 0) { [void]$B.Add((New-Block 'Сигналы' 'alerts' @((New-Prop 'Состояние' 'Проблем не обнаружено' '' 'yes')))) }
            else {
                $groups = $al | Group-Object { $_.Category }
                foreach ($g in $groups) {
                    $props = @($g.Group | ForEach-Object { New-Prop $(if ($_.Level -eq 'error') { 'Ошибка' } else { 'Предупреждение' }) $_.Text '' 'no' })
                    [void]$B.Add((New-Block $g.Name 'alerts' $props))
                }
            }
        }
        'system' {
            $sys = Get-Val $d 'System'
            if (-not $sys) { break }
            [void]$B.Add((New-Block 'Компьютер' 'system' @(
                (New-Prop 'Производитель' (Get-Val $sys 'Manufacturer'))
                (New-Prop 'Модель' (Get-Val $sys 'Model'))
                (New-Prop 'Семейство' (Get-Val $sys 'SystemFamily'))
                (New-Prop 'SKU' (Get-Val $sys 'SystemSku'))
                (New-Prop 'Серийный номер' (Get-Val $sys 'SerialNumber'))
                (New-Prop 'UUID' (Get-Val $sys 'Uuid'))
                (New-Prop 'Тип корпуса' (Get-ChassisText (Get-Val $sys 'ChassisTypes')))
                (New-Prop 'Инвентарный номер' (Get-Val $sys 'AssetTag'))
                (New-Prop 'Тип системы' (Get-Val $sys 'SystemType'))
                (YesNoProp 'Гипервизор' (Get-Val $sys 'HypervisorPresent'))
            )))
            [void]$B.Add((New-Block 'BIOS' 'chip' @(
                (New-Prop 'Производитель' (Get-Val $sys 'Bios' 'Manufacturer'))
                (New-Prop 'Версия' (Get-Val $sys 'Bios' 'Version'))
                (New-Prop 'Название' (Get-Val $sys 'Bios' 'Name'))
                (New-Prop 'Дата выпуска' (Format-DateOnly (Get-Val $sys 'Bios' 'ReleaseDate')))
                (New-Prop 'Версия SMBIOS' (Get-Val $sys 'Bios' 'SmbiosVersion'))
            )))
            [void]$B.Add((New-Block 'Материнская плата' 'board' @(
                (New-Prop 'Производитель' (Get-Val $sys 'Board' 'Manufacturer'))
                (New-Prop 'Модель' (Get-Val $sys 'Board' 'Product'))
                (New-Prop 'Версия' (Get-Val $sys 'Board' 'Version'))
                (New-Prop 'Серийный номер' (Get-Val $sys 'Board' 'SerialNumber'))
            )))
            $t = Get-Val $d 'Tpm'
            if ($t) {
                [void]$B.Add((New-Block 'TPM' 'lock' @(
                    (YesNoProp 'Присутствует' (Get-Val $t 'Present'))
                    (New-Prop 'Версия спецификации' (Get-Val $t 'Version'))
                    (New-Prop 'Производитель' (Get-Val $t 'Manufacturer'))
                    (YesNoProp 'Включен' (Get-Val $t 'Enabled'))
                    (YesNoProp 'Активирован' (Get-Val $t 'Activated'))
                )))
            }
        }
        'cpu' {
            foreach ($c in (As-Array (Get-Val $d 'Processors'))) {
                $l2 = [double](Get-Val $c 'L2CacheKB'); $l3 = [double](Get-Val $c 'L3CacheKB')
                $v = Get-Val $c 'Voltage'
                $arch = switch ([int](Get-Val $c 'Architecture')) { 0 { 'x86' } 5 { 'ARM' } 9 { 'x64' } 12 { 'ARM64' } default { '' } }
                $sub = New-Block 'Справочная информация' '' @(
                    (New-Prop 'Идентификатор' (Get-Val $c 'ProcessorId'))
                    (New-Prop 'Архитектура' $arch)
                    (New-Prop 'Разрядность' $(if (Get-Val $c 'AddressWidth') { '{0} бит' -f (Get-Val $c 'AddressWidth') }))
                    (YesNoProp 'Виртуализация включена' (Get-Val $c 'Virtualization'))
                ) 'group' '' $false
                [void]$B.Add((New-Block (Get-Val $c 'Name') 'cpu' @(
                    (New-Prop 'Описание' (Get-Val $c 'Description'))
                    (New-Prop 'Текущая частота' (Format-MHz (Get-Val $c 'CurrentClock')))
                    (New-Prop 'Максимальная частота' (Format-MHz (Get-Val $c 'MaxClock')))
                    (New-Prop 'Частота шины' (Format-MHz (Get-Val $c 'ExtClock')))
                    (New-Prop 'Производитель' (Get-Val $c 'Manufacturer'))
                    (New-Prop 'Обозначение разъема' (Get-Val $c 'Socket'))
                    (New-Prop 'Напряжение ядра' $(if ($v) { '{0} вольт' -f ([double]$v / 10).ToString('0.0#', [Globalization.CultureInfo]'ru-RU') }))
                    (New-Prop 'Число ядер' (Get-Val $c 'Cores'))
                    (New-Prop 'Число потоков' (Get-Val $c 'Threads'))
                    (YesNoProp 'Многопоточный' ([int](Get-Val $c 'Threads') -gt [int](Get-Val $c 'Cores')))
                    (New-Prop 'Кэш 2 уровня' $(if ($l2) { Format-Bytes ($l2 * 1024) }))
                    (New-Prop 'Кэш 3 уровня' $(if ($l3) { Format-Bytes ($l3 * 1024) }))
                ) 'group' '' $true @($sub)))
            }
        }
        'memory' {
            $mem = Get-Val $d 'Memory'
            $mods = @(As-Array (Get-Val $mem 'Modules'))
            $os = Get-Val $d 'OS'
            [void]$B.Add((New-Block 'Сводка' 'memory' @(
                (New-Prop 'Общий объем' (Format-Bytes (Get-Val $d 'System' 'TotalMemory') 1))
                (New-Prop 'Свободно' $(if (Get-Val $os 'FreePhysicalKB') { Format-Bytes ([double](Get-Val $os 'FreePhysicalKB') * 1024) }))
                (New-Prop 'Количество разъемов' (Get-Val $mem 'Slots'))
                (New-Prop 'Занято разъемов' $mods.Count)
                (New-Prop 'Максимальный объем' $(if ([double](Get-Val $mem 'MaxCapacity') -gt 0) { Format-Bytes (Get-Val $mem 'MaxCapacity') 0 }))
                (New-Prop 'Виртуальная память' $(if (Get-Val $os 'TotalVirtualKB') { Format-Bytes ([double](Get-Val $os 'TotalVirtualKB') * 1024) }))
            )))
            foreach ($m in $mods) {
                $title = Join-NonEmpty ' ' ((Get-Val $m 'DeviceLocator') + ':') (Format-Bytes (Get-Val $m 'Capacity') 0) (Get-MemoryTypeText (Get-Val $m 'MemoryType'))
                [void]$B.Add((New-Block $title 'memory' @(
                    (New-Prop 'Банк' (Get-Val $m 'BankLabel'))
                    (New-Prop 'Разъем' (Get-Val $m 'DeviceLocator'))
                    (New-Prop 'Объем' (Format-Bytes (Get-Val $m 'Capacity') 0))
                    (New-Prop 'Тип' (Get-MemoryTypeText (Get-Val $m 'MemoryType')))
                    (New-Prop 'Форм-фактор' (Get-FormFactorText (Get-Val $m 'FormFactor')))
                    (New-Prop 'Частота' (Format-MHz (Get-Val $m 'Speed')))
                    (New-Prop 'Рабочая частота' (Format-MHz (Get-Val $m 'ConfiguredSpeed')))
                    (New-Prop 'Производитель' (Get-Val $m 'Manufacturer'))
                    (New-Prop 'Партномер' (Get-Val $m 'PartNumber'))
                    (New-Prop 'Серийный номер' (Get-Val $m 'SerialNumber'))
                )))
            }
        }
        'video' {
            foreach ($v in (As-Array (Get-Val $d 'Video'))) {
                $res = ''
                if (Get-Val $v 'HRes') { $res = '{0} x {1}, {2} бит, {3} Гц' -f (Get-Val $v 'HRes'), (Get-Val $v 'VRes'), (Get-Val $v 'Bits'), (Get-Val $v 'Refresh') }
                [void]$B.Add((New-Block (Get-Val $v 'Name') 'video' @(
                    (New-Prop 'Видеопроцессор' (Get-Val $v 'Processor'))
                    (New-Prop 'Объем памяти' (Format-Bytes (Get-Val $v 'AdapterRAM') 0))
                    (New-Prop 'Текущий режим' $res)
                    (New-Prop 'Версия драйвера' (Get-Val $v 'DriverVersion'))
                    (New-Prop 'Дата драйвера' (Format-DateOnly (Get-Val $v 'DriverDate')))
                )))
            }
            foreach ($m in (As-Array (Get-Val $d 'Monitors'))) {
                $dg = Get-Val $m 'Diagonal'
                [void]$B.Add((New-Block (Join-NonEmpty ' ' (Get-Val $m 'Manufacturer') (Get-Val $m 'Name')) 'monitor' @(
                    (New-Prop 'Производитель' (Get-Val $m 'Manufacturer'))
                    (New-Prop 'Модель' (Get-Val $m 'Name'))
                    (New-Prop 'Код продукта' (Get-Val $m 'ProductCode'))
                    (New-Prop 'Диагональ' $(if ($dg) { '{0}"' -f $dg }))
                    (New-Prop 'Серийный номер' (Get-Val $m 'SerialNumber'))
                    (New-Prop 'Год выпуска' (Get-Val $m 'Year'))
                )))
            }
        }
        'audio' {
            foreach ($a in (As-Array (Get-Val $d 'Audio'))) {
                [void]$B.Add((New-Block (Get-Val $a 'Name') 'audio' @((New-Prop 'Производитель' (Get-Val $a 'Manufacturer')), (New-Prop 'Состояние' (Get-Val $a 'Status')))))
            }
        }
        'storage' {
            foreach ($k in (As-Array (Get-Val $d 'Disks'))) {
                $sm = Get-Val $k 'SmartFailure'
                $smProp = $null
                if ($sm -eq $true) { $smProp = New-Prop 'Состояние SMART' 'Предупреждение' '' 'no' } elseif ($sm -eq $false) { $smProp = New-Prop 'Состояние SMART' 'OK' '' 'yes' }
                [void]$B.Add((New-Block (Get-Val $k 'Model') 'storage' @(
                    (New-Prop 'Объем' (Format-Bytes (Get-Val $k 'Size') 1))
                    (New-Prop 'Тип' (Get-Val $k 'Kind'))
                    (New-Prop 'Интерфейс' (Join-NonEmpty ' / ' (Get-Val $k 'Bus') (Get-Val $k 'Interface')))
                    (New-Prop 'Тип носителя' (Get-Val $k 'MediaType'))
                    (New-Prop 'Серийный номер' (Get-Val $k 'SerialNumber'))
                    (New-Prop 'Версия прошивки' (Get-Val $k 'Firmware'))
                    (New-Prop 'Разделов' (Get-Val $k 'Partitions'))
                    $smProp
                )))
            }
            foreach ($l in (As-Array (Get-Val $d 'LogicalDisks'))) {
                $sz = [double](Get-Val $l 'Size'); $fr = [double](Get-Val $l 'Free')
                $kind = switch ([int](Get-Val $l 'DriveType')) { 2 { 'Съемный диск' } 3 { 'Локальный диск' } 4 { 'Сетевой диск' } 5 { 'Оптический диск' } 6 { 'RAM-диск' } default { 'Диск' } }
                $pct = ''
                if ($sz -gt 0) { $pct = '({0}%)' -f [math]::Round($fr / $sz * 100) }
                [void]$B.Add((New-Block (Join-NonEmpty ' ' (Get-Val $l 'Letter') (Get-Val $l 'Label')) 'volume' @(
                    (New-Prop 'Тип' $kind)
                    (New-Prop 'Файловая система' (Get-Val $l 'FileSystem'))
                    (New-Prop 'Объем' $(if ($sz) { Format-Bytes $sz }))
                    (New-Prop 'Свободно' $(if ($sz) { Format-Bytes $fr }) $pct)
                    (New-Prop 'Серийный номер тома' (Get-Val $l 'Serial'))
                    (New-Prop 'Сетевой путь' (Get-Val $l 'Provider'))
                )))
            }
            foreach ($o in (As-Array (Get-Val $d 'Optical'))) { [void]$B.Add((New-Block (Get-Val $o 'Name') 'cdrom' @((New-Prop 'Буква диска' (Get-Val $o 'Drive')), (New-Prop 'Производитель' (Get-Val $o 'Manufacturer'))))) }
        }
        'network' {
            foreach ($n in (As-Array (Get-Val $d 'Network'))) {
                $sp = Get-Val $n 'Speed'
                $st = switch ([int](Get-Val $n 'Status')) { 0 { 'Отключен' } 1 { 'Подключение' } 2 { 'Подключен' } 7 { 'Кабель не подключен' } default { '' } }
                [void]$B.Add((New-Block (Get-Val $n 'Name') 'network' @(
                    (New-Prop 'Подключение' (Get-Val $n 'ConnectionId'))
                    (New-Prop 'Производитель' (Get-Val $n 'Manufacturer'))
                    (New-Prop 'Состояние' $st)
                    (New-Prop 'MAC-адрес' (Get-Val $n 'MAC'))
                    (New-Prop 'Скорость' $(if ($sp) { '{0} Мбит/с' -f [math]::Round([double]$sp / 1e6) }))
                    (New-Prop 'IP-адрес' ((As-Array (Get-Val $n 'IPs')) -join ', '))
                    (New-Prop 'Маска подсети' ((As-Array (Get-Val $n 'Masks')) -join ', '))
                    (New-Prop 'Основной шлюз' ((As-Array (Get-Val $n 'Gateways')) -join ', '))
                    (New-Prop 'DNS-серверы' ((As-Array (Get-Val $n 'Dns')) -join ', '))
                    (YesNoProp 'DHCP включен' (Get-Val $n 'Dhcp'))
                    (New-Prop 'DHCP-сервер' (Get-Val $n 'DhcpServer'))
                )))
            }
        }
        'periph' {
            foreach ($p in (As-Array (Get-Val $d 'Printers'))) {
                [void]$B.Add((New-Block (Get-Val $p 'Name') 'printer' @(
                    (New-Prop 'Драйвер' (Get-Val $p 'Driver'))
                    (New-Prop 'Порт' (Get-Val $p 'Port'))
                    (YesNoProp 'По умолчанию' (Get-Val $p 'Default'))
                    (YesNoProp 'Сетевой' (Get-Val $p 'Network'))
                    (YesNoProp 'Общий доступ' (Get-Val $p 'Shared'))
                    (New-Prop 'Имя общего ресурса' (Get-Val $p 'ShareName'))
                    (New-Prop 'Расположение' (Get-Val $p 'Location'))
                )))
            }
            $kb = @(As-Array (Get-Val $d 'Keyboards') | ForEach-Object { New-Prop 'Клавиатура' (Get-Val $_ 'Name') })
            $ms = @(As-Array (Get-Val $d 'Mice') | ForEach-Object { New-Prop 'Указывающее устройство' (Get-Val $_ 'Name') $(if (Get-Val $_ 'Buttons') { '(кнопок: ' + (Get-Val $_ 'Buttons') + ')' }) })
            if (($kb.Count + $ms.Count) -gt 0) { [void]$B.Add((New-Block 'Устройства ввода' 'keyboard' (@($kb) + @($ms)))) }
            $usb = @(As-Array (Get-Val $d 'Usb') | ForEach-Object { New-Prop (Get-Val $_ 'Class') (Get-Val $_ 'Name') $(if (Get-Val $_ 'Manufacturer') { '(' + (Get-Val $_ 'Manufacturer') + ')' }) })
            if ($usb.Count -gt 0) { [void]$B.Add((New-Block 'USB-устройства' 'usb' $usb)) }
        }
        'devices' {
            $all = @(As-Array (Get-Val $d 'Devices'))
            $bad = @($all | Where-Object { [int](Get-Val $_ 'ErrorCode') -ne 0 })
            if ($bad.Count -gt 0) {
                [void]$B.Add((New-Block 'Проблемные устройства' 'warning' @($bad | ForEach-Object { New-Prop (Get-Val $_ 'Name') ('Код ошибки ' + (Get-Val $_ 'ErrorCode')) '' 'no' })))
            }
            foreach ($g in ($all | Group-Object { $c = [string](Get-Val $_ 'Class'); if ($c) { $c } else { 'Прочие' } } | Sort-Object Name)) {
                $props = @($g.Group | Sort-Object { Get-Val $_ 'Name' } | ForEach-Object { New-Prop (Get-Val $_ 'Name') (Get-Val $_ 'Manufacturer') })
                [void]$B.Add((New-Block ('{0} ({1})' -f $g.Name, $g.Count) 'devices' $props 'group' '' $false))
            }
        }
        'battery' {
            foreach ($b in (As-Array (Get-Val $d 'Battery'))) {
                $dc = [double](Get-Val $b 'DesignCapacity'); $fc = [double](Get-Val $b 'FullCapacity')
                $chem = switch ([int](Get-Val $b 'Chemistry')) { 3 { 'Свинцово-кислотный' } 4 { 'Никель-кадмиевый' } 5 { 'Никель-металлгидридный' } 6 { 'Литий-ионный' } 8 { 'Литий-полимерный' } default { '' } }
                [void]$B.Add((New-Block (Get-Val $b 'Name') 'battery' @(
                    (New-Prop 'Производитель' (Get-Val $b 'Manufacturer'))
                    (New-Prop 'Серийный номер' (Get-Val $b 'SerialNumber'))
                    (New-Prop 'Химия' $chem)
                    (New-Prop 'Проектная емкость' $(if ($dc) { '{0} мВт·ч' -f $dc }))
                    (New-Prop 'Полная емкость' $(if ($fc) { '{0} мВт·ч' -f $fc }) $(if ($dc -and $fc) { '(износ {0}%)' -f [math]::Round((1 - $fc / $dc) * 100) }))
                    (New-Prop 'Заряд' $(if (Get-Val $b 'Charge') { '{0}%' -f (Get-Val $b 'Charge') }))
                )))
            }
        }
        'os' {
            $os = Get-Val $d 'OS'
            if (-not $os) { break }
            $key = (As-Array (Get-Val $d 'ProductKeys') | Select-Object -First 1)
            [void]$B.Add((New-Block (Get-Val $os 'Caption') 'os' @(
                (New-Prop 'Версия' (Get-Val $os 'DisplayVersion'))
                (New-Prop 'Сборка' (Join-NonEmpty '.' (Get-Val $os 'Version') (Get-Val $os 'UBR')))
                (New-Prop 'Выпуск' (Get-Val $os 'EditionId'))
                (New-Prop 'Пакет обновления' (Get-Val $os 'ServicePack'))
                (New-Prop 'Архитектура' (Get-Val $os 'Architecture'))
                (New-Prop 'Дата установки' (Format-DateTimeRu (Get-Val $os 'InstallDate') -NoRelative))
                (New-Prop 'Последняя загрузка' (Format-DateTimeRu (Get-Val $os 'LastBoot')))
                (New-Prop 'Зарегистрированный пользователь' (Get-Val $os 'RegisteredUser'))
                (New-Prop 'Организация' (Get-Val $os 'Organization'))
                (New-Prop 'Серийный номер' (Get-Val $os 'SerialNumber'))
                (New-Prop 'Ключ продукта' (Get-Val $key 'Key'))
                (New-Prop 'Каталог Windows' (Get-Val $os 'WindowsDirectory'))
                (New-Prop 'Язык системы' (Get-Val $os 'Locale'))
            )))
        }
        'software' {
            foreach ($s in (As-Array (Get-Val $d 'Software'))) {
                $inst = Get-Val $s 'InstallDate'
                [void]$B.Add((New-Block (Get-Val $s 'Name') 'software' @(
                    (New-Prop 'Издатель' (Get-Val $s 'Publisher'))
                    (New-Prop 'Версия' (Get-Val $s 'Version'))
                    (New-Prop 'Разрядность' (Get-Val $s 'Arch'))
                    (New-Prop 'Строка деинсталляции' (Get-Val $s 'Uninstall'))
                    (New-Prop 'Дата установки' (Format-DateOnly $inst))
                    (New-Prop 'Папка установки' (Get-Val $s 'InstallLocation'))
                    (New-Prop 'Источник установки' (Get-Val $s 'InstallSource'))
                    (New-Prop 'Размер' (Format-Bytes (Get-Val $s 'Size')))
                    (New-Prop 'URL' (Get-Val $s 'Url'))
                ) 'item' ([string](Get-Val $s 'Version')) $false))
            }
        }
        'keys' {
            foreach ($k in (As-Array (Get-Val $d 'ProductKeys'))) {
                [void]$B.Add((New-Block (Get-Val $k 'Product') 'key' @((New-Prop 'Ключ' (Get-Val $k 'Key')), (New-Prop 'Источник' (Get-Val $k 'Source')))))
            }
        }
        'hotfixes' {
            foreach ($h in (As-Array (Get-Val $d 'Hotfixes') | Sort-Object { ConvertTo-DateTime (Get-Val $_ 'InstalledOn') } -Descending)) {
                [void]$B.Add((New-Block (Get-Val $h 'Id') 'hotfix' @(
                    (New-Prop 'Описание' (Get-Val $h 'Description'))
                    (New-Prop 'Дата установки' (Format-DateOnly (Get-Val $h 'InstalledOn')))
                    (New-Prop 'Установил' (Get-Val $h 'InstalledBy'))
                ) 'item' (Format-DateOnly (Get-Val $h 'InstalledOn')) $false))
            }
        }
        'wu' {
            $ok = @(As-Array (Get-Val $d 'UpdateHistory') | Where-Object { (Get-Val $_ 'Result') -like 'Успешно*' -and (Get-Val $_ 'Operation') -eq 'Установка' })
            foreach ($h in $ok) {
                [void]$B.Add((New-Block (Get-Val $h 'Title') 'winupdate' @((New-Prop 'Дата' (Format-DateTimeRu (Get-Val $h 'Date') -NoRelative)), (New-Prop 'Результат' (Get-Val $h 'Result') '' 'yes')) 'item' (Format-DateOnly (Get-Val $h 'Date')) $false))
            }
        }
        'wuhist' {
            foreach ($h in (As-Array (Get-Val $d 'UpdateHistory'))) {
                $mark = if ((Get-Val $h 'Result') -like 'Успешно*') { 'yes' } elseif ((Get-Val $h 'Result') -eq 'Ошибка') { 'no' } else { '' }
                [void]$B.Add((New-Block (Get-Val $h 'Title') 'winupdate' @(
                    (New-Prop 'Дата' (Format-DateTimeRu (Get-Val $h 'Date') -NoRelative))
                    (New-Prop 'Операция' (Get-Val $h 'Operation'))
                    (New-Prop 'Результат' (Get-Val $h 'Result') '' $mark)
                    (New-Prop 'Код' (Get-Val $h 'HResult'))
                ) 'item' (Get-Val $h 'Result') $false))
            }
        }
        'security' {
            $s = Get-Val $d 'Security'
            if (-not $s) { break }
            $av = @(As-Array (Get-Val $s 'Antivirus'))
            if ($av.Count -eq 0) { [void]$B.Add((New-Block 'Антивирус' 'shield' @((New-Prop 'Состояние' 'Не обнаружен' '' 'no')))) }
            foreach ($a in $av) {
                [void]$B.Add((New-Block ('Антивирус: ' + (Get-Val $a 'Name')) 'shield' @(
                    (YesNoProp 'Включен' (Get-Val $a 'Enabled'))
                    (YesNoProp 'Базы актуальны' (Get-Val $a 'UpToDate'))
                    (New-Prop 'Исполняемый файл' (Get-Val $a 'Path'))
                )))
            }
            foreach ($a in (As-Array (Get-Val $s 'Antispyware'))) {
                [void]$B.Add((New-Block ('Антишпион: ' + (Get-Val $a 'Name')) 'shield' @((YesNoProp 'Включен' (Get-Val $a 'Enabled')), (YesNoProp 'Базы актуальны' (Get-Val $a 'UpToDate')))))
            }
            $fw = @(As-Array (Get-Val $s 'Firewall') | ForEach-Object { YesNoProp ('Профиль «' + (Get-Val $_ 'Profile') + '»') (Get-Val $_ 'Enabled') })
            $fwp = @(As-Array (Get-Val $s 'FirewallProducts') | ForEach-Object { YesNoProp (Get-Val $_ 'Name') (Get-Val $_ 'Enabled') })
            if (($fw.Count + $fwp.Count) -gt 0) { [void]$B.Add((New-Block 'Брандмауэр' 'firewall' (@($fw) + @($fwp)))) }
            [void]$B.Add((New-Block 'Параметры системы' 'shield' @(
                (YesNoProp 'Контроль учетных записей (UAC)' (Get-Val $s 'Uac'))
                (YesNoProp 'Автоматическое обновление' (Get-Val $s 'AutoUpdate'))
                (YesNoProp 'Удаленный рабочий стол разрешен' (Get-Val $s 'RdpEnabled'))
            )))
            $bl = @(As-Array (Get-Val $d 'BitLocker'))
            if ($bl.Count -gt 0) {
                [void]$B.Add((New-Block 'BitLocker' 'lock' @($bl | ForEach-Object { $on = [int](Get-Val $_ 'Protection') -eq 1; New-Prop ('Диск ' + (Get-Val $_ 'Drive')) $(if ($on) { 'Защищен' } else { 'Не защищен' }) '' $(if ($on) { 'yes' } else { 'no' }) })))
            }
        }
        'shares' {
            foreach ($s in (As-Array (Get-Val $d 'Shares'))) {
                [void]$B.Add((New-Block (Get-Val $s 'Name') 'share' @((New-Prop 'Путь' (Get-Val $s 'Path')), (New-Prop 'Тип' (Get-Val $s 'Type')), (New-Prop 'Описание' (Get-Val $s 'Description'))) 'item' ([string](Get-Val $s 'Path')) $false))
            }
        }
        'env' {
            $sysVars = @(As-Array (Get-Val $d 'Environment') | Where-Object { Get-Val $_ 'System' } | Sort-Object { Get-Val $_ 'Name' } | ForEach-Object { New-Prop (Get-Val $_ 'Name') (Get-Val $_ 'Value') })
            if ($sysVars.Count -gt 0) { [void]$B.Add((New-Block 'Системные переменные' 'env' $sysVars)) }
            foreach ($g in (As-Array (Get-Val $d 'Environment') | Where-Object { -not (Get-Val $_ 'System') } | Group-Object { Get-Val $_ 'User' })) {
                [void]$B.Add((New-Block ('Переменные пользователя ' + $g.Name) 'env' @($g.Group | Sort-Object { Get-Val $_ 'Name' } | ForEach-Object { New-Prop (Get-Val $_ 'Name') (Get-Val $_ 'Value') })))
            }
        }
        'fonts' {
            $f = @(As-Array (Get-Val $d 'Fonts') | ForEach-Object { New-Prop (Get-Val $_ 'Name') (Get-Val $_ 'File') })
            if ($f.Count -gt 0) { [void]$B.Add((New-Block ('Установленные шрифты ({0})' -f $f.Count) 'font' $f)) }
        }
        'startup' {
            foreach ($g in (As-Array (Get-Val $d 'Startup') | Group-Object { Get-Val $_ 'Location' })) {
                [void]$B.Add((New-Block $g.Name 'startup' @($g.Group | ForEach-Object { New-Prop (Get-Val $_ 'Name') (Get-Val $_ 'Command') $(if (Get-Val $_ 'User') { '(' + (Get-Val $_ 'User') + ')' }) })))
            }
        }
        'services' {
            foreach ($s in (As-Array (Get-Val $d 'Services') | Sort-Object { Get-Val $_ 'DisplayName' })) {
                $st = switch ([string](Get-Val $s 'State')) { 'Running' { 'Работает' } 'Stopped' { 'Остановлена' } 'Paused' { 'Приостановлена' } default { [string](Get-Val $s 'State') } }
                $sm = switch ([string](Get-Val $s 'StartMode')) { 'Auto' { 'Автоматически' } 'Manual' { 'Вручную' } 'Disabled' { 'Отключена' } 'Boot' { 'Загрузка' } 'System' { 'Система' } default { [string](Get-Val $s 'StartMode') } }
                [void]$B.Add((New-Block (Get-Val $s 'DisplayName') 'service' @(
                    (New-Prop 'Имя службы' (Get-Val $s 'Name'))
                    (New-Prop 'Состояние' $st '' $(if ($st -eq 'Работает') { 'online' } else { '' }))
                    (New-Prop 'Тип запуска' $sm)
                    (New-Prop 'Учетная запись' (Get-Val $s 'Account'))
                    (New-Prop 'Путь' (Get-Val $s 'Path'))
                    (New-Prop 'Описание' (Get-Val $s 'Description'))
                ) 'item' $st $false))
            }
        }
        'processes' {
            foreach ($p in (As-Array (Get-Val $d 'Processes') | Sort-Object { Get-Val $_ 'Name' })) {
                [void]$B.Add((New-Block (Get-Val $p 'Name') 'process' @(
                    (New-Prop 'PID' (Get-Val $p 'Pid'))
                    (New-Prop 'Путь' (Get-Val $p 'Path'))
                    (New-Prop 'Память' (Format-Bytes (Get-Val $p 'Memory')))
                    (New-Prop 'Потоков' (Get-Val $p 'Threads'))
                ) 'item' (Format-Bytes (Get-Val $p 'Memory')) $false))
            }
        }
        'users' {
            foreach ($u in (As-Array (Get-Val $d 'Users'))) {
                [void]$B.Add((New-Block (Get-Val $u 'Name') 'user' @(
                    (New-Prop 'Полное имя' (Get-Val $u 'FullName'))
                    (New-Prop 'Описание' (Get-Val $u 'Description'))
                    (YesNoProp 'Отключена' (Get-Val $u 'Disabled'))
                    (YesNoProp 'Заблокирована' (Get-Val $u 'Lockout'))
                    (YesNoProp 'Требуется пароль' (Get-Val $u 'PasswordRequired'))
                    (YesNoProp 'Срок действия пароля ограничен' (Get-Val $u 'PasswordExpires'))
                    (New-Prop 'SID' (Get-Val $u 'Sid'))
                )))
            }
        }
        'groups' {
            foreach ($g in (As-Array (Get-Val $d 'Groups'))) {
                $mem = @(As-Array (Get-Val $g 'Members') | ForEach-Object { New-Prop 'Участник' $_ })
                [void]$B.Add((New-Block (Get-Val $g 'Name') 'group' (@((New-Prop 'Описание' (Get-Val $g 'Description'))) + $mem) 'group' '' ($mem.Count -gt 0)))
            }
        }
        'snapshot' {
            $m = Get-Val $d 'Meta'
            $errs = @(As-Array (Get-Val $m 'Errors') | ForEach-Object { New-Prop 'Ошибка' $_ '' 'no' })
            [void]$B.Add((New-Block 'Снимок' 'snapshot' (@(
                (New-Prop 'Дата снимка' (Format-DateTimeRu (Get-Val $m 'Timestamp')))
                (New-Prop 'Способ получения' (Get-Val $m 'Method'))
                (New-Prop 'Всего снимков устройства' (@(As-Array $Device['Snapshots'])).Count)
                (New-Prop 'Идентификатор устройства' $Device['Id'])
                (New-Prop 'Файл устройства' $Device['_Path'])
            ) + $errs)))
        }
        'special' {
            [void]$B.Add((New-Block 'Специальная информация' 'special' @(
                (New-Prop 'Закрепленный пользователь' $Device['AssignedUser'])
                (New-Prop 'Расположение' $Device['Location'])
                (New-Prop 'Записка' $Device['Note'])
            )))
        }
    }
    return $B.ToArray()
}

function ConvertTo-PlainText {
    # Текстовое представление блоков (для «Копировать как текст» и печати)
    param([string]$Title, [array]$Blocks)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine($Title)
    [void]$sb.AppendLine(('=' * [math]::Max(10, $Title.Length)))
    foreach ($b in $Blocks) {
        [void]$sb.AppendLine('')
        $t = $b.Title
        if ($b.Extra) { $t = $t + '  ' + $b.Extra }
        [void]$sb.AppendLine('[' + $t + ']')
        foreach ($p in $b.Props) { [void]$sb.AppendLine(('  {0}: {1} {2}' -f $p.K, $p.V, $p.V2).TrimEnd()) }
        foreach ($s in $b.Subs) {
            [void]$sb.AppendLine('  [' + $s.Title + ']')
            foreach ($p in $s.Props) { [void]$sb.AppendLine(('    {0}: {1} {2}' -f $p.K, $p.V, $p.V2).TrimEnd()) }
        }
    }
    return $sb.ToString()
}
