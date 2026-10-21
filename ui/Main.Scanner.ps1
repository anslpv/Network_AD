# Main.Scanner.ps1 — вкладка «Сканер»: задачи, запуск, журнал

$script:RootFolderLabel = '(корень хранилища)'
$script:CurrentUserLabel = 'Текущий пользователь'

function Add-Log {
    param([string]$Level, [string]$Text)
    $e = New-Object NetInv.LogEntry
    $e.Time = (Get-Date).ToString('HH:mm:ss')
    $e.Text = $Text
    switch ($Level) {
        'ok'    { $e.Glyph = [string][char]0xE73E; $e.GlyphColor = '#2E9E3E' }
        'error' { $e.Glyph = [string][char]0xE783; $e.GlyphColor = '#D9302C' }
        'warn'  { $e.Glyph = [string][char]0xE7BA; $e.GlyphColor = '#E08A00' }
        default { $e.Glyph = [string][char]0xE946; $e.GlyphColor = '#2F7FD0' }
    }
    $script:LogItems.Add($e)
    while ($script:LogItems.Count -gt 5000) { $script:LogItems.RemoveAt(0) }
    $ui.txtLogCount.Text = [string]$script:LogItems.Count
    $ui.txtLogMessages.Text = 'Сообщений: ' + $script:LogItems.Count
    $ui.lbLog.ScrollIntoView($e)
}

function Update-LoginOptions {
    $l = [NetInv.ScanTaskRow]::SharedLogins
    $l.Clear()
    $l.Add($script:CurrentUserLabel)
    foreach ($x in (As-Array $script:Settings.Logins)) { $l.Add([string]$x['Name']) }
}

function Update-FolderOptions {
    $f = [NetInv.ScanTaskRow]::SharedFolders
    $keep = @($script:TaskRows | ForEach-Object { $_.FolderName })
    $f.Clear()
    $f.Add($script:RootFolderLabel)
    foreach ($x in ($script:Store.Folders | Sort-Object)) { $f.Add([string]$x) }
    foreach ($k in $keep) { if ($k -and -not $f.Contains($k)) { $f.Add($k) } }
}

function Get-LoginNameById {
    param([string]$Id)
    if (-not $Id -or $Id -eq 'current') { return $script:CurrentUserLabel }
    foreach ($x in (As-Array $script:Settings.Logins)) { if ($x['Id'] -eq $Id) { return [string]$x['Name'] } }
    return $script:CurrentUserLabel
}

function Get-LoginByName {
    param([string]$Name)
    if (-not $Name -or $Name -eq $script:CurrentUserLabel) { return $null }
    foreach ($x in (As-Array $script:Settings.Logins)) { if ([string]$x['Name'] -eq $Name) { return $x } }
    return $null
}

function Get-TaskGlyph {
    param([string]$Kind)
    switch ($Kind) {
        'Cidr'    { return [string][char]0xE968 }
        'Range'   { return [string][char]0xE968 }
        'Local'   { return [string][char]0xE80F }
        'Devices' { return [string][char]0xE8F1 }
        'AD'      { return [string][char]0xE716 }
        default   { return [string][char]0xE977 }
    }
}

function Add-ScanTasks {
    param([array]$Tasks)
    $added = 0
    foreach ($t in $Tasks) {
        $dup = $false
        foreach ($r in $script:TaskRows) { if ($r.Text -eq $t.Text) { $dup = $true } }
        if ($dup) { continue }
        $row = New-Object NetInv.ScanTaskRow
        $row.Id = [string]$t.Id
        $row.Task = $t
        $row.Text = [string]$t.Text
        $row.Glyph = Get-TaskGlyph $t.Kind
        $row.LoginName = Get-LoginNameById ([string]$t.LoginId)
        $folder = [string]$t.Folder
        if (-not $folder) {
            $n = $script:State.Node
            if ($n -and $n.Kind -eq 'Folder' -and $t.Kind -in @('Cidr', 'Range', 'Ip', 'Host', 'AD')) { $folder = [string]$n.Tag }
        }
        $row.FolderName = $(if ($folder) { $folder } else { $script:RootFolderLabel })
        if (-not [NetInv.ScanTaskRow]::SharedFolders.Contains($row.FolderName)) { [NetInv.ScanTaskRow]::SharedFolders.Add($row.FolderName) }
        $cnt = Get-IpRangeCount $t
        if ($t.Kind -eq 'Devices' -or $t.Kind -eq 'AD') { $cnt = @($t.Targets).Count }
        $row.Status = $(if ($cnt -gt 1) { 'Адресов: ' + $cnt } else { '' })
        $script:TaskRows.Add($row)
        $added++
    }
    Update-ScannerView
    return $added
}

function Add-DeviceTasks {
    param([array]$Devices, [bool]$SwitchTab = $false)
    $targets = @($Devices | ForEach-Object { if ($_['Hostname']) { [string]$_['Hostname'] } elseif ($_['Ip']) { [string]$_['Ip'] } } | Where-Object { $_ })
    if ($targets.Count -eq 0) { Show-Info 'Нет устройств для сканирования.'; return }
    if ($targets.Count -eq 1) {
        $d = @($Devices)[0]
        $t = New-ScanTask 'Host' ('{0}' -f $targets[0]) @{ Target = $targets[0]; Folder = [string]$d['_Folder'] }
    } else {
        $scope = Get-ScopeInfo
        $t = New-ScanTask 'Devices' ('Устройства: {0} ({1})' -f $scope.Title, $targets.Count) @{ Targets = $targets; Folder = '' }
    }
    [void](Add-ScanTasks @($t))
    if ($SwitchTab) { $ui.tabScanner.IsChecked = $true }
}

function Add-TasksFromInput {
    $text = $ui.txtAddTask.Text.Trim()
    if (-not $text) { return }
    $tasks = $null
    try { $tasks = @(ConvertFrom-ScanInput $text) }
    catch { Show-Warning ($_.Exception.Message + "`n`nПримеры: 192.168.1.10, 192.168.1.0/24, 192.168.1.1-192.168.1.50, 10.0.0.1-50, PC-01"); return }
    [void](Add-ScanTasks $tasks)
    $recent = @($text) + @(As-Array $script:Settings['RecentTargets'] | Where-Object { $_ -ne $text })
    $script:Settings['RecentTargets'] = @($recent | Select-Object -First 10)
    Save-Settings
    $ui.txtAddTask.Text = ''
}

function Update-ScannerView {
    $has = $script:TaskRows.Count -gt 0
    $ui.gridWelcome.Visibility = $(if ($has) { 'Collapsed' } else { 'Visible' })
    $ui.dgTasks.Visibility = $(if ($has) { 'Visible' } else { 'Collapsed' })
    $ui.btnClearTasks.Visibility = $(if ($has) { 'Visible' } else { 'Collapsed' })
    $ui.btnSaveTasks.IsEnabled = $has
    $ui.pnlWelcomeHelp.Visibility = $(if ($script:Settings.Scanner.ShowWelcome) { 'Visible' } else { 'Collapsed' })
    $eng = $script:State.Engine
    if ($eng -and $eng.Running) {
        $ui.txtStartScan.Text = 'Остановить сканирование'
        $ui.glyphStartScan.Text = [string][char]0xE71A
        $ui.glyphStartScan.Foreground = '#D9302C'
        $ui.txtStartScanSub.Text = ('Выполнено: {0} из {1}' -f $script:State.ScanDone, $script:State.ScanTotal)
        $ui.btnStartScan.IsEnabled = $true
    } else {
        $ui.txtStartScan.Text = 'Начать сканирование'
        $ui.glyphStartScan.Text = [string][char]0xE768
        $ui.glyphStartScan.Foreground = '#3A6EA5'
        $enabled = @($script:TaskRows | Where-Object { $_.Enabled }).Count
        $ui.txtStartScanSub.Text = $(if (-not $has) { 'Нет задач' } elseif ($enabled -eq 0) { 'Задачи не отмечены' } else { 'Готов к запуску' })
        $ui.btnStartScan.IsEnabled = ($enabled -gt 0)
    }
}

function Start-Scan {
    $eng = $script:State.Engine
    if ($eng -and $eng.Running) {
        Stop-ScanEngine $eng
        Add-Log 'warn' 'Остановка сканирования...'
        return
    }
    $rows = @($script:TaskRows | Where-Object { $_.Enabled })
    if ($rows.Count -eq 0) { return }
    $items = New-Object System.Collections.ArrayList
    $script:State.TaskProgress = @{}
    $script:State.TaskFolders = @{}
    $sc = $script:Settings.Scanner
    $skip = @{}
    if ($sc.SkipExisting -and [int]$sc.SkipExistingHours -gt 0) {
        $limit = (Get-Date).AddHours(-[int]$sc.SkipExistingHours)
        foreach ($d in $script:Store.Devices) {
            $ls = ConvertTo-DateTime $d['LastScan']
            if ($ls -and $ls -gt $limit) {
                foreach ($k in @($d['Ip'], $d['Hostname'], $d['Name'])) { if ($k) { $skip[([string]$k).ToLowerInvariant()] = $true } }
            }
        }
    }
    foreach ($r in $rows) {
        $t = $r.Task
        $targets = @(Expand-ScanTask $t)
        if ($targets.Count -gt 4096) {
            if (-not (Confirm-Action ('Задача «{0}» содержит {1} адресов. Сканирование может занять много времени. Продолжить?' -f $r.Text, $targets.Count))) { continue }
        }
        $login = Get-LoginByName $r.LoginName
        $cred = Get-LoginCredential $login
        if ($login -and -not $cred) { Add-Log 'warn' ('Не удалось расшифровать пароль логина «{0}», используется текущий пользователь.' -f $login['Name']) }
        $folder = $(if ($r.FolderName -and $r.FolderName -ne $script:RootFolderLabel) { $r.FolderName } else { '' })
        $script:State.TaskFolders[$r.Id] = $folder
        $cnt = 0; $skipped = 0
        foreach ($tg in $targets) {
            if ($skip.ContainsKey(([string]$tg).ToLowerInvariant())) { $skipped++; continue }
            [void]$items.Add(@{ Target = $tg; TaskId = $r.Id; Credential = $cred })
            $cnt++
        }
        $script:State.TaskProgress[$r.Id] = @{ Total = $cnt; Done = 0; Found = 0; Errors = 0; Row = $r }
        $r.Status = $(if ($cnt -eq 0) { 'Пропущено (недавно сканировалось)' } else { 'В очереди: ' + $cnt })
        $r.StatusColor = '#666666'
        if ($skipped -gt 0) { Add-Log 'info' ('{0}: пропущено недавно сканированных устройств: {1}' -f $r.Text, $skipped) }
    }
    if ($items.Count -eq 0) { Update-ScannerView; return }
    $opts = @{}
    foreach ($k in @($sc.PSBase.Keys)) { $opts[$k] = $sc[$k] }
    $script:State.ScanTotal = $items.Count
    $script:State.ScanDone = 0; $script:State.ScanFound = 0; $script:State.ScanErrors = 0
    Add-Log 'info' ('Сканирование запущено: адресов — {0}, потоков — {1}' -f $items.Count, $opts.Threads)
    $script:State.Engine = Start-ScanEngine $items.ToArray() $opts $script:CollectorPath
    $ui.pbScan.Visibility = 'Visible'
    $ui.pbScan.Maximum = $items.Count
    $ui.pbScan.Value = 0
    $ui.txtStatScan.Text = 'Сканирование...'
    Update-ScannerView
}

function Process-ScanMessages {
    $eng = $script:State.Engine
    if (-not $eng) { return }
    $msgs = @(Receive-ScanMessages $eng)
    $changed = $false
    foreach ($m in $msgs) {
        switch ($m.Type) {
            'log' { Add-Log $m.Level $m.Text }
            'progress' {
                $tp = $script:State.TaskProgress[$m.TaskId]
                if ($tp -and $m.Stage -eq 'collect') { $tp.Row.Status = ('Сбор данных: {0}' -f $m.Target); $tp.Row.StatusColor = '#2F7FD0' }
            }
            'result' {
                $script:State.ScanDone++
                $tp = $script:State.TaskProgress[$m.TaskId]
                if ($tp) { $tp.Done++ }
                if ($m.Ok -and $m.Data) {
                    try {
                        $dev = Add-DeviceSnapshot $m.Data ([string]$script:State.TaskFolders[$m.TaskId]) ([string]$m.Target) ([string]$m.Method)
                        $script:State.ScanFound++
                        if ($tp) { $tp.Found++ }
                        $changed = $true
                        $errs = @(As-Array (Get-Val $m.Data 'Meta' 'Errors'))
                        Add-Log 'ok' ('{0}: {1} — данные получены ({2}){3}' -f $m.Target, $dev['Name'], $m.Method, $(if ($errs.Count) { ', с предупреждениями: ' + $errs.Count } else { '' }))
                    } catch {
                        $script:State.ScanErrors++
                        if ($tp) { $tp.Errors++ }
                        Add-Log 'error' ('{0}: ошибка сохранения — {1}' -f $m.Target, $_.Exception.Message)
                    }
                } elseif ($m.Skipped) {
                    if ($tp -and $tp.Total -le 1) { Add-Log 'warn' ('{0}: {1}' -f $m.Target, $m.Error) }
                } else {
                    $script:State.ScanErrors++
                    if ($tp) { $tp.Errors++ }
                    Add-Log 'error' ('{0}: не удалось получить данные — {1}' -f $m.Target, $m.Error)
                }
                if ($tp) {
                    $tp.Row.Status = ('Обработано {0} из {1}; найдено: {2}; ошибок: {3}' -f $tp.Done, $tp.Total, $tp.Found, $tp.Errors)
                    $tp.Row.StatusColor = $(if ($tp.Errors -gt 0) { '#D9302C' } elseif ($tp.Done -ge $tp.Total) { '#2E9E3E' } else { '#2F7FD0' })
                }
            }
        }
    }
    $ui.pbScan.Value = $script:State.ScanDone
    if ($changed) {
        Set-DataChanged
        Build-Tree
    }
    if (-not $eng.Running) {
        $script:State.Engine = $null
        $ui.pbScan.Visibility = 'Collapsed'
        $ui.txtStatScan.Text = ('Сканирование завершено: найдено {0}, ошибок {1}' -f $script:State.ScanFound, $script:State.ScanErrors)
        Add-Log $(if ($script:State.ScanErrors) { 'warn' } else { 'ok' }) ('Сканирование завершено. Обработано адресов: {0}, получены данные: {1}, ошибок: {2}' -f $script:State.ScanDone, $script:State.ScanFound, $script:State.ScanErrors)
        Build-Tree
        Refresh-CurrentTab
    } elseif ($msgs.Count -gt 0) {
        $ui.txtStatScan.Text = ('Сканирование: {0} из {1}' -f $script:State.ScanDone, $script:State.ScanTotal)
    }
    Update-ScannerView
}

function Start-QuickScan {
    $tasks = @(New-ScanTask 'Local' ('Этот компьютер ({0})' -f $env:COMPUTERNAME) @{ Target = 'localhost' })
    foreach ($s in (Get-LocalSubnets)) {
        if ($s -match '/(\d+)$' -and [int]$Matches[1] -ge 22 -and $s -notmatch '^169\.254\.') { $tasks += @(ConvertFrom-ScanInput $s) }
    }
    [void](Add-ScanTasks $tasks)
    Start-Scan
}

function Update-SubnetsPanel {
    $subs = @(Get-LocalSubnets)
    $ui.icSubnets.ItemsSource = $subs
    $ui.txtNoSubnets.Visibility = $(if ($subs.Count -eq 0) { 'Visible' } else { 'Collapsed' })
}

function Update-AdPanel {
    $doms = @($script:State.AdCreds.Keys | Sort-Object)
    $ui.icAdDomains.ItemsSource = $doms
    $ui.txtAdStatus.Visibility = $(if ($doms.Count -eq 0) { 'Visible' } else { 'Collapsed' })
}

function Add-AdDomainTask {
    param([string]$Domain)
    $cred = $script:State.AdCreds[$Domain]
    $script:MainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
    try { $comps = @(Get-AdComputers $Domain $cred) }
    finally { $script:MainWindow.Cursor = $null }
    if ($comps.Count -eq 0) { Show-Info ('В домене {0} не найдено включённых учётных записей компьютеров.' -f $Domain); return }
    $t = New-ScanTask 'AD' ('Active Directory: {0} ({1})' -f $Domain, $comps.Count) @{ Targets = @($comps | ForEach-Object { $_.Host }) }
    [void](Add-ScanTasks @($t))
    Add-Log 'info' ('Active Directory {0}: найдено компьютеров — {1}' -f $Domain, $comps.Count)
}

function Update-SavedTasksPanel {
    $sets = @(Get-SavedTaskSets)
    $ui.icSavedTasks.ItemsSource = @($sets | ForEach-Object { [pscustomobject]$_ })
    $ui.txtNoSavedTasks.Visibility = $(if ($sets.Count -eq 0) { 'Visible' } else { 'Collapsed' })
}

function Save-CurrentTasks {
    if ($script:TaskRows.Count -eq 0) { return }
    $name = Show-InputBox 'Сохранить задачи' 'Название набора задач:' ('Задачи ' + (Get-Date).ToString('dd.MM.yyyy'))
    if (-not $name -or -not $name.Trim()) { return }
    $tasks = @()
    foreach ($r in $script:TaskRows) {
        $t = @{}
        foreach ($k in @($r.Task.PSBase.Keys)) { $t[$k] = $r.Task[$k] }
        $lg = Get-LoginByName $r.LoginName
        $t['LoginId'] = $(if ($lg) { $lg['Id'] } else { 'current' })
        $t['Folder'] = $(if ($r.FolderName -ne $script:RootFolderLabel) { $r.FolderName } else { '' })
        $t['Enabled'] = $r.Enabled
        $tasks += $t
    }
    Save-TaskSet $name.Trim() $tasks
    Update-SavedTasksPanel
}

function Initialize-ScannerPage {
    $ui.dgTasks.ItemsSource = $script:TaskRows
    $ui.lbLog.ItemsSource = $script:LogItems
    Update-LoginOptions
    Update-FolderOptions
    Update-SubnetsPanel
    Update-SavedTasksPanel
    $dom = Get-CurrentAdDomain
    if ($dom) { $script:State.AdCreds[$dom] = $null }
    Update-AdPanel

    $ui.txtAddTask.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Invoke-Safe { Add-TasksFromInput }; $e.Handled = $true } })
    $ui.btnAddTask.Add_Click({ Invoke-Safe { Add-TasksFromInput } })
    $ui.btnAddHistory.Add_Click({ Invoke-Safe {
        $rec = @(As-Array $script:Settings['RecentTargets'])
        if ($rec.Count -eq 0) { $items = @((New-MenuItem 'Нет недавних адресов' $null '' @() $false)) }
        else { $items = @($rec | ForEach-Object { New-MenuItem ([string]$_) { param($s, $e) $ui.txtAddTask.Text = [string]$s.Header; $ui.txtAddTask.Focus() } 'subnet' }) }
        Show-DropMenu $ui.btnAddHistory $items
    } })
    $ui.btnQuickScan.Add_Click({ Invoke-Safe { Start-QuickScan } })
    $ui.btnStartScan.Add_Click({ Invoke-Safe { Start-Scan } })
    $ui.btnScanSettings.Add_Click({ Invoke-Safe { $r = Show-SettingsDialog 'scanner'; if ($r -eq 'storage') { Switch-Storage $script:Settings.StoragePath } } })
    $ui.btnLogins.Add_Click({ Invoke-Safe {
        if (Show-LoginsDialog) {
            Update-LoginOptions
            foreach ($r in $script:TaskRows) { if (-not [NetInv.ScanTaskRow]::SharedLogins.Contains($r.LoginName)) { $r.LoginName = $script:CurrentUserLabel } }
        }
    } })
    $ui.btnClearTasks.Add_Click({ Invoke-Safe {
        if ($script:State.Engine) { Show-Info 'Дождитесь окончания сканирования или остановите его.'; return }
        $script:TaskRows.Clear(); Update-ScannerView
    } })
    $ui.btnAddThis.Add_Click({ Invoke-Safe { [void](Add-ScanTasks @(New-ScanTask 'Local' ('Этот компьютер ({0})' -f $env:COMPUTERNAME) @{ Target = 'localhost' })) } })
    $ui.btnAddAll.Add_Click({ Invoke-Safe {
        $all = @($script:Store.Devices)
        if ($all.Count -eq 0) { Show-Info 'В хранилище пока нет устройств.'; return }
        $targets = @($all | ForEach-Object { if ($_['Hostname']) { [string]$_['Hostname'] } else { [string]$_['Ip'] } } | Where-Object { $_ })
        [void](Add-ScanTasks @(New-ScanTask 'Devices' ('Все устройства ({0})' -f $targets.Count) @{ Targets = $targets }))
    } })
    $ui.btnAddSelected.Add_Click({ Invoke-Safe {
        $n = $script:State.Node
        if (-not $n -or $n.Kind -eq 'Root') { Show-Info 'Выберите устройство или папку в дереве слева.'; return }
        Add-DeviceTasks (Get-ScopeDevices) $false
    } })
    $ui.icSubnets.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($s, $e)
        Invoke-Safe { $b = $e.OriginalSource; if ($b.Tag) { [void](Add-ScanTasks @(ConvertFrom-ScanInput ([string]$b.Tag))) } }
    })
    $ui.icAdDomains.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($s, $e)
        Invoke-Safe { $b = $e.OriginalSource; if ($b.Tag) { Add-AdDomainTask ([string]$b.Tag) } }
    })
    $ui.btnAdConnect.Add_Click({ Invoke-Safe {
        $r = Show-AdConnectDialog (Get-CurrentAdDomain)
        if (-not $r) { return }
        $script:MainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
        try { $comps = @(Get-AdComputers $r.Domain $r.Credential) }
        catch { $script:MainWindow.Cursor = $null; Show-Warning ('Не удалось подключиться к домену {0}: {1}' -f $r.Domain, $_.Exception.Message); return }
        $script:MainWindow.Cursor = $null
        $script:State.AdCreds[$r.Domain] = $r.Credential
        Update-AdPanel
        Add-Log 'ok' ('Подключено к домену {0}: компьютеров — {1}' -f $r.Domain, $comps.Count)
    } })
    $ui.icSavedTasks.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($s, $e)
        Invoke-Safe { $b = $e.OriginalSource; if ($b.Tag) { [void](Add-ScanTasks @(Load-TaskSet ([string]$b.Tag.Path))) } }
    })
    $ui.btnSaveTasks.Add_Click({ Invoke-Safe { Save-CurrentTasks } })
    $ui.btnOpenTasksFolder.Add_Click({ Invoke-Safe { Start-Process explorer.exe (Get-TasksFolder) } })
    $ui.dgTasks.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($s, $e)
        Invoke-Safe {
            $b = $e.OriginalSource
            if ($b -is [System.Windows.Controls.Button] -and [string]$b.Tag -eq 'delete') {
                if ($script:State.Engine) { return }
                $row = $b.DataContext
                if ($row) { [void]$script:TaskRows.Remove($row); Update-ScannerView }
            } elseif ($b -is [System.Windows.Controls.CheckBox]) { Update-ScannerView }
        }
    })
    $ui.chkAllTasks.Add_Click({ Invoke-Safe { $v = [bool]$ui.chkAllTasks.IsChecked; foreach ($r in $script:TaskRows) { $r.Enabled = $v }; Update-ScannerView } })
    $ui.btnClearLog.Add_Click({ $script:LogItems.Clear(); $ui.txtLogCount.Text = '0'; $ui.txtLogMessages.Text = 'Сообщений: 0' })
    $ui.lnkHideWelcome.Add_Click({ $script:Settings.Scanner.ShowWelcome = $false; Save-Settings; Update-ScannerView })
    $ui.lnkTaskHelp.Add_Click({ Show-TaskHelp })
}

function Show-TaskHelp {
    Show-Info (@(
        'В поле «Добавить» можно ввести:',
        '',
        '  • IP-адрес: 192.168.1.10',
        '  • подсеть: 192.168.1.0/24',
        '  • диапазон: 192.168.1.1-192.168.1.50 или 192.168.1.1-50',
        '  • сетевое имя: PC-ACCOUNTING',
        '  • несколько значений через запятую или пробел',
        '',
        'Для удалённых компьютеров нужен логин с правами администратора',
        '(кнопка «Настроить логины») и доступ по WinRM (рекомендуется)',
        'или WMI/DCOM. Включить WinRM на компьютере: Enable-PSRemoting -Force'
    ) -join "`n") 'Помощь по добавлению задач'
}
