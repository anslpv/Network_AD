# Reports.ps1 — шаблоны табличных отчётов и построение DataTable

function Get-ChassisText {
    param($Types)
    foreach ($t in (As-Array $Types)) {
        switch ([int]$t) {
            3 { return 'Настольный' } 4 { return 'Низкопрофильный' } 5 { return 'Pizza Box' } 6 { return 'Mini Tower' } 7 { return 'Tower' }
            8 { return 'Портативный' } 9 { return 'Ноутбук' } 10 { return 'Ноутбук' } 11 { return 'Карманный' } 13 { return 'Моноблок' }
            14 { return 'Субноутбук' } 15 { return 'Компактный' } 17 { return 'Сервер' } 23 { return 'Стоечный' } 30 { return 'Планшет' }
            31 { return 'Трансформер' } 32 { return 'Съёмный' } 34 { return 'Встраиваемый' } 35 { return 'Мини-ПК' } 36 { return 'Stick PC' }
        }
    }
    return ''
}

function Get-MemoryTypeText {
    param($Type)
    switch ([int]$Type) {
        20 { 'DDR' } 21 { 'DDR2' } 22 { 'DDR2 FB-DIMM' } 24 { 'DDR3' } 26 { 'DDR4' } 27 { 'LPDDR' } 28 { 'LPDDR2' }
        29 { 'LPDDR3' } 30 { 'LPDDR4' } 34 { 'DDR5' } 35 { 'LPDDR5' } 17 { 'SDRAM' } 18 { 'SGRAM' } 0 { '' } default { '' }
    }
}

function Get-FormFactorText {
    param($FF)
    switch ([int]$FF) { 8 { 'DIMM' } 12 { 'SODIMM' } 13 { 'SRIMM' } 7 { 'SIMM' } 9 { 'TSOP' } default { '' } }
}

function Get-Win11Readiness {
    param($d)
    $issues = @()
    $cpu = @(As-Array (Get-Val $d 'Processors')) | Select-Object -First 1
    if ((Get-Val $d 'OS' 'Architecture') -notmatch '64') { $issues += '32-битная ОС' }
    if ($cpu -and [int](Get-Val $cpu 'Cores') -lt 2) { $issues += 'менее 2 ядер' }
    if ($cpu -and [int](Get-Val $cpu 'MaxClock') -gt 0 -and [int](Get-Val $cpu 'MaxClock') -lt 1000) { $issues += 'частота ЦП < 1 ГГц' }
    $ram = [double](Get-Val $d 'System' 'TotalMemory')
    if ($ram -gt 0 -and $ram -lt 3.8GB) { $issues += 'ОЗУ < 4 ГБ' }
    $tpm = Get-Val $d 'Tpm'
    if (-not (Get-Val $tpm 'Present')) { $issues += 'нет TPM' } elseif ([string](Get-Val $tpm 'Version') -notmatch '^2') { $issues += 'TPM не 2.0' }
    $sysDrive = [string](Get-Val $d 'OS' 'SystemDrive')
    foreach ($ld in (As-Array (Get-Val $d 'LogicalDisks'))) {
        if ((Get-Val $ld 'Letter') -eq $sysDrive -and [double](Get-Val $ld 'Size') -lt 60GB) { $issues += 'системный диск < 64 ГБ' }
    }
    return $issues
}

# Каждый шаблон: Id, Path (папки), Name, Icon, Columns, Rows (скрипт-блок: param($dev, $d) -> массив массивов)
$script:ReportTemplates = @(
    # --- Операционные системы
    @{ Id = 'os-all'; Path = @('Операционные системы'); Name = 'Все операционные системы'; Icon = 'os'
       Columns = @('Имя', 'Сборка ОС', 'Версия', 'Выпуск', 'Архитектура', 'Пакет обновления', 'Обновление', 'Дата установки', 'Последняя загрузка')
       Rows = { param($dev, $d) $o = Get-Val $d 'OS'; if (-not $o) { return @() }
           ,@(,@((Get-Val $o 'Caption'), (Get-Val $o 'Version'), (Get-Val $o 'DisplayVersion'), (Get-Val $o 'EditionId'), (Get-Val $o 'Architecture'), (Get-Val $o 'ServicePack'), (Get-Val $o 'UBR'), (Format-DateOnly (Get-Val $o 'InstallDate')), (Format-DateTimeRu (Get-Val $o 'LastBoot') -NoRelative))) } }
    @{ Id = 'os-win'; Path = @('Операционные системы'); Name = 'Сводка по Windows'; Icon = 'os'
       Columns = @('Имя', 'Версия', 'Зарегистрированный пользователь', 'Организация', 'Серийный номер', 'Ключ продукта', 'Каталог Windows', 'Язык')
       Rows = { param($dev, $d) $o = Get-Val $d 'OS'; if (-not $o) { return @() }
           $k = (As-Array (Get-Val $d 'ProductKeys') | Select-Object -First 1)
           ,@(,@((Get-Val $o 'Caption'), ('{0} {1}' -f (Get-Val $o 'DisplayVersion'), (Get-Val $o 'Version')).Trim(), (Get-Val $o 'RegisteredUser'), (Get-Val $o 'Organization'), (Get-Val $o 'SerialNumber'), (Get-Val $k 'Key'), (Get-Val $o 'WindowsDirectory'), (Get-Val $o 'Locale'))) } }
    @{ Id = 'os-win11'; Path = @('Операционные системы'); Name = 'Готовность к Windows 11'; Icon = 'win11'
       Columns = @('Операционная система', 'Процессор', 'Ядер', 'ОЗУ', 'TPM', 'Готовность', 'Причины')
       Rows = { param($dev, $d) if (-not (Get-Val $d 'OS')) { return @() }
           $cpu = @(As-Array (Get-Val $d 'Processors')) | Select-Object -First 1
           $tpm = Get-Val $d 'Tpm'
           $tpmText = if (Get-Val $tpm 'Present') { 'TPM ' + ([string](Get-Val $tpm 'Version')).Split(',')[0] } else { 'Нет' }
           $iss = @(Get-Win11Readiness $d)
           ,@(,@((Get-Val $d 'OS' 'Caption'), (Get-Val $cpu 'Name'), (Get-Val $cpu 'Cores'), (Format-Bytes (Get-Val $d 'System' 'TotalMemory') 0), $tpmText, $(if ($iss.Count -eq 0) { 'Да' } else { 'Нет' }), ($iss -join '; '))) } }

    # --- Программы
    @{ Id = 'sw-installed'; Path = @('Программы'); Name = 'Установленное ПО'; Icon = 'software'
       Columns = @('Название', 'Версия', 'Издатель', 'Дата установки', 'Размер', 'Разрядность')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Software') | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Version'), (Get-Val $_ 'Publisher'), (Format-DateOnly (Get-Val $_ 'InstallDate')), (Format-Bytes (Get-Val $_ 'Size')), (Get-Val $_ 'Arch')) }) } }
    @{ Id = 'sw-keys-ms'; Path = @('Программы', 'Лицензируемое ПО', 'ПО Microsoft'); Name = 'Ключи Microsoft'; Icon = 'key'
       Columns = @('Продукт', 'Ключ', 'Источник')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'ProductKeys') | ForEach-Object { ,@((Get-Val $_ 'Product'), (Get-Val $_ 'Key'), (Get-Val $_ 'Source')) }) } }
    @{ Id = 'sw-office'; Path = @('Программы', 'Лицензируемое ПО', 'ПО Microsoft'); Name = 'Статус Microsoft Office'; Icon = 'office'
       Columns = @('Продукт', 'Версия', 'Разрядность', 'Дата установки')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Software') | Where-Object { (Get-Val $_ 'Name') -match '^Microsoft (Office|365)|Microsoft Office' -and (Get-Val $_ 'Name') -notmatch 'Proof|Language|MUI|Shared|Click-to-Run|Components|Viewer|Компоненты' } | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Version'), (Get-Val $_ 'Arch'), (Format-DateOnly (Get-Val $_ 'InstallDate'))) }) } }
    @{ Id = 'sw-forbidden'; Path = @('Программы'); Name = 'Запрещенное ПО'; Icon = 'forbidden'
       Columns = @('Название', 'Версия', 'Издатель', 'Правило')
       Rows = { param($dev, $d)
           $pats = @(([string](Get-Val $script:Settings 'Reports' 'ForbiddenSoftware')) -split '[;\r\n]+' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
           if ($pats.Count -eq 0) { return @() }
           $res = @()
           foreach ($sw in (As-Array (Get-Val $d 'Software'))) {
               foreach ($p in $pats) { $pp = $p; if ($pp -notmatch '[\*\?]') { $pp = '*' + $pp + '*' }; if ((Get-Val $sw 'Name') -like $pp) { $res += ,@((Get-Val $sw 'Name'), (Get-Val $sw 'Version'), (Get-Val $sw 'Publisher'), $p); break } }
           }
           ,$res } }
    @{ Id = 'sw-db'; Path = @('Программы'); Name = 'Серверы баз данных'; Icon = 'database'
       Columns = @('Продукт', 'Версия', 'Издатель')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Software') | Where-Object { (Get-Val $_ 'Name') -match 'SQL Server \d|SQL Server \(|MySQL Server|PostgreSQL|Firebird|Oracle Database|MariaDB|MongoDB|Redis|ClickHouse' -and (Get-Val $_ 'Name') -notmatch 'Management Studio|Native Client|ODBC|Browser|Writer|VSS|Setup|Tools|Shared|Policies|Client' } | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Version'), (Get-Val $_ 'Publisher')) }) } }

    # --- Безопасность
    @{ Id = 'sec-summary'; Path = @('Безопасность'); Name = 'Сводка по безопасности'; Icon = 'shield'
       Columns = @('Антивирус', 'Антивирус включен', 'Базы актуальны', 'Брандмауэр', 'Контроль учетных записей', 'Автообновление', 'Удаленный рабочий стол')
       Rows = { param($dev, $d) $s = Get-Val $d 'Security'; if (-not $s) { return @() }
           $av = @(As-Array (Get-Val $s 'Antivirus'))
           $avName = ($av | ForEach-Object { Get-Val $_ 'Name' }) -join ', '
           $avOn = if ($av.Count -eq 0) { '' } else { Format-YesNo (@($av | Where-Object { Get-Val $_ 'Enabled' }).Count -gt 0) }
           $avUp = if ($av.Count -eq 0) { '' } else { Format-YesNo (@($av | Where-Object { Get-Val $_ 'UpToDate' }).Count -gt 0) }
           $fw = (As-Array (Get-Val $s 'Firewall') | ForEach-Object { '{0}: {1}' -f (Get-Val $_ 'Profile'), $(if (Get-Val $_ 'Enabled') { 'вкл' } else { 'выкл' }) }) -join '; '
           ,@(,@($(if ($avName) { $avName } else { 'Не обнаружен' }), $avOn, $avUp, $fw, (Format-YesNo (Get-Val $s 'Uac')), (Format-YesNo (Get-Val $s 'AutoUpdate')), (Format-YesNo (Get-Val $s 'RdpEnabled')))) } }
    @{ Id = 'sec-av'; Path = @('Безопасность'); Name = 'Проблемы с антивирусом'; Icon = 'shield'
       Columns = @('Проблема', 'Антивирус')
       Rows = { param($dev, $d) $s = Get-Val $d 'Security'; if (-not $s) { return @() }
           if ([int](Get-Val $d 'OS' 'ProductType') -ge 2) { return @() }
           $av = @(As-Array (Get-Val $s 'Antivirus'))
           if ($av.Count -eq 0) { return ,@(,@('Антивирус не обнаружен', '')) }
           $res = @()
           foreach ($a in $av) {
               if (-not (Get-Val $a 'Enabled')) { $res += ,@('Антивирус отключен', (Get-Val $a 'Name')) }
               elseif (-not (Get-Val $a 'UpToDate')) { $res += ,@('Базы устарели', (Get-Val $a 'Name')) }
           }
           ,$res } }
    @{ Id = 'sec-fw'; Path = @('Безопасность'); Name = 'Проблемы с брандмауэром'; Icon = 'firewall'
       Columns = @('Профиль', 'Состояние')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Security' 'Firewall') | Where-Object { -not (Get-Val $_ 'Enabled') } | ForEach-Object { ,@((Get-Val $_ 'Profile'), 'Выключен') }) } }

    # --- Хранение информации
    @{ Id = 'st-disks'; Path = @('Хранение информации'); Name = 'Накопители'; Icon = 'disk'
       Columns = @('Модель', 'Тип', 'Интерфейс', 'Размер', 'Серийный номер', 'Прошивка', 'SMART')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Disks') | ForEach-Object {
           $sm = Get-Val $_ 'SmartFailure'; $smt = if ($null -eq $sm) { '' } elseif ($sm) { 'Предупреждение' } else { 'OK' }
           $bus = Get-Val $_ 'Bus'; if (-not $bus) { $bus = Get-Val $_ 'Interface' }
           ,@((Get-Val $_ 'Model'), (Get-Val $_ 'Kind'), $bus, (Format-Bytes (Get-Val $_ 'Size') 0), (Get-Val $_ 'SerialNumber'), (Get-Val $_ 'Firmware'), $smt) }) } }
    @{ Id = 'st-removable'; Path = @('Хранение информации'); Name = 'Съемные диски'; Icon = 'removable'
       Columns = @('Диск', 'Метка', 'Файловая система', 'Размер', 'Свободно')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'LogicalDisks') | Where-Object { [int](Get-Val $_ 'DriveType') -eq 2 } | ForEach-Object { ,@((Get-Val $_ 'Letter'), (Get-Val $_ 'Label'), (Get-Val $_ 'FileSystem'), (Format-Bytes (Get-Val $_ 'Size')), (Format-Bytes (Get-Val $_ 'Free'))) }) } }
    @{ Id = 'st-logical'; Path = @('Хранение информации'); Name = 'Логические диски'; Icon = 'volume'
       Columns = @('Диск', 'Метка', 'Файловая система', 'Размер', 'Свободно', 'Свободно, %')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'LogicalDisks') | Where-Object { [int](Get-Val $_ 'DriveType') -eq 3 } | ForEach-Object {
           $sz = [double](Get-Val $_ 'Size'); $fr = [double](Get-Val $_ 'Free'); $pc = if ($sz -gt 0) { [math]::Round($fr / $sz * 100) } else { '' }
           ,@((Get-Val $_ 'Letter'), (Get-Val $_ 'Label'), (Get-Val $_ 'FileSystem'), (Format-Bytes $sz), (Format-Bytes $fr), $pc) }) } }
    @{ Id = 'st-bitlocker'; Path = @('Хранение информации'); Name = 'Статус BitLocker'; Icon = 'lock'
       Columns = @('Диск', 'Защита', 'Шифрование')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'BitLocker') | ForEach-Object {
           $p = switch ([int](Get-Val $_ 'Protection')) { 0 { 'Выключена' } 1 { 'Включена' } default { 'Неизвестно' } }
           $c = switch ([int](Get-Val $_ 'Conversion')) { 0 { 'Не зашифрован' } 1 { 'Зашифрован' } 2 { 'Шифруется' } 3 { 'Расшифровывается' } 4 { 'Приостановлено' } 5 { 'Приостановлено' } default { '' } }
           ,@((Get-Val $_ 'Drive'), $p, $c) }) } }

    # --- Оборудование
    @{ Id = 'hw-system'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'Система'; Icon = 'system'
       Columns = @('Производитель', 'Модель', 'Серийный номер', 'Тип корпуса', 'BIOS', 'Дата BIOS', 'Материнская плата')
       Rows = { param($dev, $d) $s = Get-Val $d 'System'; if (-not $s) { return @() }
           ,@(,@((Get-Val $s 'Manufacturer'), (Get-Val $s 'Model'), (Get-Val $s 'SerialNumber'), (Get-ChassisText (Get-Val $s 'ChassisTypes')), ('{0} {1}' -f (Get-Val $s 'Bios' 'Manufacturer'), (Get-Val $s 'Bios' 'Version')).Trim(), (Format-DateOnly (Get-Val $s 'Bios' 'ReleaseDate')), ('{0} {1}' -f (Get-Val $s 'Board' 'Manufacturer'), (Get-Val $s 'Board' 'Product')).Trim())) } }
    @{ Id = 'hw-cpu'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'Процессоры'; Icon = 'cpu'
       Columns = @('Процессор', 'Частота', 'Ядер', 'Потоков', 'Разъем', 'Кэш L2', 'Кэш L3')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Processors') | ForEach-Object { ,@((Get-Val $_ 'Name'), (Format-MHz (Get-Val $_ 'MaxClock')), (Get-Val $_ 'Cores'), (Get-Val $_ 'Threads'), (Get-Val $_ 'Socket'), (Format-Bytes ([double](Get-Val $_ 'L2CacheKB') * 1024)), (Format-Bytes ([double](Get-Val $_ 'L3CacheKB') * 1024))) }) } }
    @{ Id = 'hw-mem'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'Системная память'; Icon = 'memory'
       Columns = @('Разъем', 'Объем', 'Тип', 'Форм-фактор', 'Частота', 'Производитель', 'Партномер', 'Серийный номер')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Memory' 'Modules') | ForEach-Object { ,@((Get-Val $_ 'DeviceLocator'), (Format-Bytes (Get-Val $_ 'Capacity') 0), (Get-MemoryTypeText (Get-Val $_ 'MemoryType')), (Get-FormFactorText (Get-Val $_ 'FormFactor')), (Format-MHz (Get-Val $_ 'Speed')), (Get-Val $_ 'Manufacturer'), (Get-Val $_ 'PartNumber'), (Get-Val $_ 'SerialNumber')) }) } }
    @{ Id = 'hw-video'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'Видеоадаптеры'; Icon = 'video'
       Columns = @('Видеоадаптер', 'Память', 'Разрешение', 'Версия драйвера', 'Дата драйвера')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Video') | ForEach-Object { $res = ''; if (Get-Val $_ 'HRes') { $res = '{0}x{1}' -f (Get-Val $_ 'HRes'), (Get-Val $_ 'VRes') }; ,@((Get-Val $_ 'Name'), (Format-Bytes (Get-Val $_ 'AdapterRAM') 0), $res, (Get-Val $_ 'DriverVersion'), (Format-DateOnly (Get-Val $_ 'DriverDate'))) }) } }
    @{ Id = 'hw-monitors'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'Мониторы'; Icon = 'monitor'
       Columns = @('Монитор', 'Производитель', 'Диагональ', 'Серийный номер', 'Год выпуска')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Monitors') | ForEach-Object { $dg = Get-Val $_ 'Diagonal'; ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Manufacturer'), $(if ($dg) { '{0}"' -f $dg } else { '' }), (Get-Val $_ 'SerialNumber'), (Get-Val $_ 'Year')) }) } }
    @{ Id = 'hw-audio'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'Звуковые устройства'; Icon = 'audio'
       Columns = @('Устройство', 'Производитель')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Audio') | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Manufacturer')) }) } }
    @{ Id = 'hw-nic'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'Сетевые адаптеры'; Icon = 'network'
       Columns = @('Адаптер', 'Подключение', 'MAC-адрес', 'IP-адреса', 'Шлюз', 'DHCP', 'Скорость')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Network') | Where-Object { Get-Val $_ 'Physical' } | ForEach-Object { $sp = Get-Val $_ 'Speed'; $spt = if ($sp) { '{0} Мбит/с' -f [math]::Round([double]$sp / 1e6) } else { '' }
           ,@((Get-Val $_ 'Name'), (Get-Val $_ 'ConnectionId'), (Get-Val $_ 'MAC'), ((As-Array (Get-Val $_ 'IPs')) -join ', '), ((As-Array (Get-Val $_ 'Gateways')) -join ', '), (Format-YesNo (Get-Val $_ 'Dhcp')), $spt) }) } }
    @{ Id = 'hw-usb'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'USB-устройства'; Icon = 'usb'
       Columns = @('Устройство', 'Класс', 'Производитель')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Usb') | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Class'), (Get-Val $_ 'Manufacturer')) }) } }
    @{ Id = 'hw-printers'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'Принтеры'; Icon = 'printer'
       Columns = @('Принтер', 'Драйвер', 'Порт', 'По умолчанию', 'Сетевой', 'Общий доступ')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Printers') | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Driver'), (Get-Val $_ 'Port'), (Format-YesNo (Get-Val $_ 'Default')), (Format-YesNo (Get-Val $_ 'Network')), (Format-YesNo (Get-Val $_ 'Shared'))) }) } }
    @{ Id = 'hw-optical'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'Оптические диски'; Icon = 'cdrom'
       Columns = @('Привод', 'Буква')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Optical') | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Drive')) }) } }
    @{ Id = 'hw-battery'; Path = @('Оборудование', 'Детальный анализ оборудования'); Name = 'Батарея'; Icon = 'battery'
       Columns = @('Батарея', 'Производитель', 'Проектная емкость', 'Полная емкость', 'Износ, %', 'Заряд, %')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Battery') | ForEach-Object { $dc = [double](Get-Val $_ 'DesignCapacity'); $fc = [double](Get-Val $_ 'FullCapacity'); $wear = if ($dc -gt 0 -and $fc -gt 0) { [math]::Round((1 - $fc / $dc) * 100) } else { '' }
           ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Manufacturer'), $(if ($dc) { '{0} мВт·ч' -f $dc } else { '' }), $(if ($fc) { '{0} мВт·ч' -f $fc } else { '' }), $wear, (Get-Val $_ 'Charge')) }) } }
    @{ Id = 'hw-general'; Path = @('Оборудование'); Name = 'Общая информация о системе'; Icon = 'general'
       Columns = @('Модель', 'Процессор', 'Память', 'Накопители', 'Видеоадаптер', 'Операционная система', 'Пользователь')
       Rows = { param($dev, $d) if (-not (Get-Val $d 'System')) { return @() }
           $cpu = (As-Array (Get-Val $d 'Processors') | ForEach-Object { Get-Val $_ 'Name' }) -join '; '
           $disks = (As-Array (Get-Val $d 'Disks') | ForEach-Object { Format-Bytes (Get-Val $_ 'Size') 0 }) -join ' + '
           $vid = (As-Array (Get-Val $d 'Video') | ForEach-Object { Get-Val $_ 'Name' }) -join '; '
           ,@(,@(('{0} {1}' -f (Get-Val $d 'System' 'Manufacturer'), (Get-Val $d 'System' 'Model')).Trim(), $cpu, (Format-Bytes (Get-Val $d 'System' 'TotalMemory') 0), $disks, $vid, (Get-Val $d 'OS' 'Caption'), (Get-Val $d 'System' 'UserName'))) } }
    @{ Id = 'hw-problem'; Path = @('Оборудование'); Name = 'Проблемные устройства'; Icon = 'warning'
       Columns = @('Устройство', 'Класс', 'Производитель', 'Код ошибки')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Devices') | Where-Object { [int](Get-Val $_ 'ErrorCode') -ne 0 } | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Class'), (Get-Val $_ 'Manufacturer'), (Get-Val $_ 'ErrorCode')) }) } }
    @{ Id = 'hw-tpm'; Path = @('Оборудование'); Name = 'TPM'; Icon = 'chip'
       Columns = @('Наличие', 'Версия', 'Производитель', 'Включен', 'Активирован')
       Rows = { param($dev, $d) $t = Get-Val $d 'Tpm'; if (-not $t) { return @() }
           ,@(,@((Format-YesNo (Get-Val $t 'Present')), ([string](Get-Val $t 'Version')).Split(',')[0], (Get-Val $t 'Manufacturer'), (Format-YesNo (Get-Val $t 'Enabled')), (Format-YesNo (Get-Val $t 'Activated')))) } }

    # --- Обновления
    @{ Id = 'upd-hotfix'; Path = @('Обновления'); Name = 'Системные обновления Windows'; Icon = 'hotfix'
       Columns = @('Обновление', 'Описание', 'Дата установки', 'Установил')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Hotfixes') | ForEach-Object { ,@((Get-Val $_ 'Id'), (Get-Val $_ 'Description'), (Format-DateOnly (Get-Val $_ 'InstalledOn')), (Get-Val $_ 'InstalledBy')) }) } }
    @{ Id = 'upd-errors'; Path = @('Обновления'); Name = 'Ошибки обновления Windows'; Icon = 'winupdate'
       Columns = @('Обновление', 'Дата', 'Результат', 'Код')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'UpdateHistory') | Where-Object { (Get-Val $_ 'Result') -eq 'Ошибка' } | ForEach-Object { ,@((Get-Val $_ 'Title'), (Format-DateTimeRu (Get-Val $_ 'Date') -NoRelative), (Get-Val $_ 'Result'), (Get-Val $_ 'HResult')) }) } }
    @{ Id = 'upd-wu'; Path = @('Обновления'); Name = 'Обновления Windows'; Icon = 'winupdate'
       Columns = @('Обновление', 'Дата', 'Операция', 'Результат')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'UpdateHistory') | ForEach-Object { ,@((Get-Val $_ 'Title'), (Format-DateTimeRu (Get-Val $_ 'Date') -NoRelative), (Get-Val $_ 'Operation'), (Get-Val $_ 'Result')) }) } }

    # --- Пользователи
    @{ Id = 'usr-accounts'; Path = @('Пользователи'); Name = 'Учетные записи'; Icon = 'user'
       Columns = @('Имя', 'Полное имя', 'Описание', 'Отключена', 'Заблокирована', 'Пароль обязателен', 'SID')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Users') | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'FullName'), (Get-Val $_ 'Description'), (Format-YesNo (Get-Val $_ 'Disabled')), (Format-YesNo (Get-Val $_ 'Lockout')), (Format-YesNo (Get-Val $_ 'PasswordRequired')), (Get-Val $_ 'Sid')) }) } }
    @{ Id = 'usr-groups'; Path = @('Пользователи'); Name = 'Локальные группы'; Icon = 'group'
       Columns = @('Группа', 'Описание', 'Участники')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Groups') | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Description'), ((As-Array (Get-Val $_ 'Members')) -join ', ')) }) } }

    # --- Прочее
    @{ Id = 'oth-services'; Path = @('Прочее'); Name = 'Службы'; Icon = 'service'
       Columns = @('Служба', 'Имя', 'Состояние', 'Тип запуска', 'Учетная запись')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Services') | ForEach-Object { ,@((Get-Val $_ 'DisplayName'), (Get-Val $_ 'Name'), (Get-Val $_ 'State'), (Get-Val $_ 'StartMode'), (Get-Val $_ 'Account')) }) } }
    @{ Id = 'oth-startup'; Path = @('Прочее'); Name = 'Автозагрузка'; Icon = 'startup'
       Columns = @('Название', 'Команда', 'Расположение', 'Пользователь')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Startup') | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Command'), (Get-Val $_ 'Location'), (Get-Val $_ 'User')) }) } }
    @{ Id = 'oth-shares'; Path = @('Прочее'); Name = 'Общие ресурсы'; Icon = 'share'
       Columns = @('Ресурс', 'Путь', 'Тип', 'Описание')
       Rows = { param($dev, $d) ,@(As-Array (Get-Val $d 'Shares') | ForEach-Object { ,@((Get-Val $_ 'Name'), (Get-Val $_ 'Path'), (Get-Val $_ 'Type'), (Get-Val $_ 'Description')) }) } }
)

function Get-ReportTemplate {
    param([string]$Id)
    foreach ($t in $script:ReportTemplates) { if ($t.Id -eq $Id) { return $t } }
    return $null
}

function New-SimpleTable {
    # DataTable с безопасными внутренними именами столбцов (c0, c1, ...) и подписями в Caption
    param([string[]]$Captions, [hashtable]$Types = @{})
    $dt = New-Object System.Data.DataTable
    for ($i = 0; $i -lt $Captions.Count; $i++) {
        $t = [string]
        if ($Types.ContainsKey($Captions[$i])) { $t = $Types[$Captions[$i]] }
        $col = $dt.Columns.Add(('c' + $i), $t)
        $col.Caption = $Captions[$i]
    }
    return ,$dt
}

function Add-TableRow {
    param([System.Data.DataTable]$Table, [object[]]$Values)
    $row = $Table.NewRow()
    for ($i = 0; $i -lt $Table.Columns.Count; $i++) {
        $v = $null
        if ($i -lt $Values.Count) { $v = $Values[$i] }
        if ($Table.Columns[$i].DataType -eq [string]) {
            if ($null -eq $v -or [string]$v -eq '') { $row[$i] = [string][char]0x2014 } else { $row[$i] = [string]$v }
        } else {
            if ($null -eq $v -or [string]$v -eq '') { $row[$i] = [DBNull]::Value } else { $row[$i] = $v }
        }
    }
    [void]$Table.Rows.Add($row)
}

function New-ReportTable {
    # Строит DataTable по шаблону для набора устройств
    param($Template, [array]$Devices)
    $caps = @('№', 'Сетевое имя', 'IP-адрес') + @($Template.Columns)
    $dt = New-SimpleTable $caps @{ '№' = [int] }
    $num = 0
    foreach ($dev in ($Devices | Sort-Object { [string]$_['Name'] })) {
        $data = Get-DeviceSnapshot $dev
        if (-not $data) { continue }
        $rows = $null
        try { $rows = & $Template.Rows $dev $data } catch { $rows = $null }
        if ($null -eq $rows) { continue }
        foreach ($r in $rows) {
            if ($null -eq $r) { continue }
            $num++
            Add-TableRow $dt (@($num, [string]$dev['Name'], [string]$dev['Ip']) + @($r))
        }
    }
    return ,$dt
}
