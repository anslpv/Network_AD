# Alerts.ps1 — сигналы (проблемы) по снимку устройства

function Get-DeviceAlerts {
    param($Data)
    $res = @()
    if (-not $Data) { return $res }
    $a = Get-Val $script:Settings 'Alerts'
    $minFree = [double](Get-Val $a 'DiskFreePercent'); if ($minFree -le 0) { $minFree = 10 }
    foreach ($ld in (As-Array (Get-Val $Data 'LogicalDisks'))) {
        if ([int](Get-Val $ld 'DriveType') -ne 3) { continue }
        $sz = [double](Get-Val $ld 'Size'); $fr = [double](Get-Val $ld 'Free')
        if ($sz -gt 0 -and ($fr / $sz * 100) -lt $minFree) {
            $res += @{ Level = 'warning'; Category = 'Хранение информации'; Text = ('Мало места на диске {0}: свободно {1} из {2} ({3}%)' -f (Get-Val $ld 'Letter'), (Format-Bytes $fr), (Format-Bytes $sz), [math]::Round($fr / $sz * 100)) }
        }
    }
    foreach ($dk in (As-Array (Get-Val $Data 'Disks'))) {
        if ((Get-Val $dk 'SmartFailure') -eq $true) { $res += @{ Level = 'error'; Category = 'Хранение информации'; Text = ('SMART предупреждает о возможном отказе: {0}' -f (Get-Val $dk 'Model')) } }
    }
    $minRam = [double](Get-Val $a 'MinRamGB')
    $ram = [double](Get-Val $Data 'System' 'TotalMemory')
    if ($minRam -gt 0 -and $ram -gt 0 -and $ram -lt ($minRam * 1GB * 0.95)) {
        $res += @{ Level = 'warning'; Category = 'Системная память'; Text = ('Объём оперативной памяти {0} меньше рекомендуемого ({1} ГБ)' -f (Format-Bytes $ram 0), $minRam) }
    }
    $isServer = [int](Get-Val $Data 'OS' 'ProductType') -ge 2
    if ((Get-Val $a 'CheckAntivirus') -and -not $isServer -and (Get-Val $Data 'Security')) {
        $av = @(As-Array (Get-Val $Data 'Security' 'Antivirus'))
        if ($av.Count -eq 0) { $res += @{ Level = 'error'; Category = 'Безопасность'; Text = 'Антивирус не обнаружен' } }
        foreach ($x in $av) {
            if (-not (Get-Val $x 'Enabled')) { $res += @{ Level = 'error'; Category = 'Безопасность'; Text = ('Антивирус отключен: {0}' -f (Get-Val $x 'Name')) } }
            elseif (-not (Get-Val $x 'UpToDate')) { $res += @{ Level = 'warning'; Category = 'Безопасность'; Text = ('Антивирусные базы устарели: {0}' -f (Get-Val $x 'Name')) } }
        }
    }
    if (Get-Val $a 'CheckFirewall') {
        foreach ($f in (As-Array (Get-Val $Data 'Security' 'Firewall'))) {
            if (-not (Get-Val $f 'Enabled')) { $res += @{ Level = 'warning'; Category = 'Безопасность'; Text = ('Брандмауэр выключен для профиля «{0}»' -f (Get-Val $f 'Profile')) } }
        }
    }
    if (Get-Val $a 'CheckProblemDevices') {
        $bad = @(As-Array (Get-Val $Data 'Devices') | Where-Object { [int](Get-Val $_ 'ErrorCode') -ne 0 })
        foreach ($b in $bad) { $res += @{ Level = 'warning'; Category = 'Устройства'; Text = ('Проблема с устройством: {0} (код {1})' -f (Get-Val $b 'Name'), (Get-Val $b 'ErrorCode')) } }
    }
    foreach ($bt in (As-Array (Get-Val $Data 'Battery'))) {
        $dc = [double](Get-Val $bt 'DesignCapacity'); $fc = [double](Get-Val $bt 'FullCapacity')
        if ($dc -gt 0 -and $fc -gt 0 -and ($fc / $dc) -lt 0.6) { $res += @{ Level = 'warning'; Category = 'Батарея'; Text = ('Износ батареи {0}%' -f [math]::Round((1 - $fc / $dc) * 100)) } }
    }
    return $res
}
