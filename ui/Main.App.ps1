# Main.App.ps1 — инициализация окна, верхние меню, таймеры, запуск

function Switch-Storage {
    param([string]$Path)
    if ($script:State.Engine) { Show-Info 'Дождитесь окончания сканирования.'; return }
    [void](Open-Storage $Path)
    $script:Settings.StoragePath = $script:Store.Root
    Save-Settings
    $script:State.Node = $null
    $script:State.TreeExpanded = @{ '' = $true }
    $script:State.Stamp = ''; $script:State.StampDeviceId = ''
    Set-DataChanged
    Build-Tree
    Refresh-CurrentTab
    Add-Log 'info' ('Открыто хранилище: ' + $script:Store.Root)
}

function New-OfflineCollector {
    $dir = Select-FolderPath 'Папка, в которую сохранить автономный сборщик'
    if (-not $dir) { return }
    $code = [System.IO.File]::ReadAllText($script:CollectorPath, [System.Text.Encoding]::UTF8)
    $footer = @'

# ---------------------------------------------------------------------------
#  Запуск автономного сбора: результат сохраняется рядом со скриптом
#  (или в папку, указанную параметром -OutDir). Затем файл импортируется
#  в программу: Хранилище -> Импортировать -> Снимок (JSON).
# ---------------------------------------------------------------------------
$OutDir = $args | Select-Object -First 1
if (-not $OutDir) { $OutDir = $PSScriptRoot }
if (-not $OutDir) { $OutDir = (Get-Location).Path }
Write-Host 'Сбор данных об этом компьютере...'
$data = & $script:CollectorScript -CimSession $null -ScanUpdates $true -UpdatesTimeoutSec 600 -Method 'Автономный сборщик'
$doc = @{ Format = 'NetInventorySnapshot'; Version = 1; Data = $data }
$json = $doc | ConvertTo-Json -Depth 24 -Compress
$file = Join-Path $OutDir ('{0}_{1}.json' -f $env:COMPUTERNAME, (Get-Date).ToString('yyyyMMdd-HHmmss'))
[System.IO.File]::WriteAllText($file, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('Готово: ' + $file)
'@
    $target = Join-Path $dir 'Collect-Inventory.ps1'
    [System.IO.File]::WriteAllText($target, ($code + $footer), (New-Object System.Text.UTF8Encoding($true)))
    $cmd = Join-Path $dir 'Collect-Inventory.cmd'
    [System.IO.File]::WriteAllText($cmd, "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Collect-Inventory.ps1`" `"%~dp0`"`r`npause`r`n", [System.Text.Encoding]::ASCII)
    Show-Info ("Автономный сборщик сохранён:`n$target`n`nЗапустите Collect-Inventory.cmd от имени администратора на нужном компьютере, затем импортируйте полученный файл .json через меню «Хранилище → Импортировать».")
}

function Import-SnapshotsInteractive {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Снимки (*.json)|*.json'
    $dlg.Multiselect = $true
    if (-not $dlg.ShowDialog($script:MainWindow)) { return }
    $folder = ''
    $n = $script:State.Node
    if ($n -and $n.Kind -eq 'Folder') { $folder = [string]$n.Tag }
    $ok = 0
    foreach ($f in $dlg.FileNames) {
        try { $d = Import-SnapshotFile $f $folder; $ok++; Add-Log 'ok' ('Импортировано: {0} -> {1}' -f $f, $d['Name']) }
        catch { Add-Log 'error' ('Ошибка импорта {0}: {1}' -f $f, $_.Exception.Message) }
    }
    Set-DataChanged
    Build-Tree
    Refresh-CurrentTab
    Show-Info ('Импортировано снимков: {0} из {1}' -f $ok, $dlg.FileNames.Count)
}

function Show-StorageMenu {
    $items = @(
        (New-MenuItem 'Создать...' { Invoke-Safe {
            $p = Select-FolderPath 'Выберите пустую папку для нового хранилища'
            if ($p) { Switch-Storage $p }
        } } 'add')
        (New-MenuItem 'Открыть...' { Invoke-Safe {
            $p = Select-FolderPath 'Выберите папку хранилища' $script:Store.Root
            if ($p) { Switch-Storage $p }
        } } 'folder')
        (New-MenuSeparator)
        (New-MenuItem $script:Store.Name $null 'root' @() $false)
        (New-MenuItem 'Импортировать' $null 'add' @(
            (New-MenuItem 'Снимок (JSON), собранный автономно...' { Invoke-Safe { Import-SnapshotsInteractive } } 'add')
        ))
        (New-MenuItem 'Резервная копия' $null 'save' @(
            (New-MenuItem 'Создать резервную копию...' { Invoke-Safe {
                $p = Select-SaveFile 'ZIP-архив (*.zip)|*.zip' ($script:Store.Name + '_' + (Get-Date).ToString('yyyyMMdd') + '.zip')
                if ($p) { Backup-Storage $p; Show-Info ('Резервная копия создана:' + "`n" + $p) }
            } } 'save')
            (New-MenuItem 'Восстановить из копии...' { Invoke-Safe {
                $zip = Select-OpenFile 'ZIP-архив (*.zip)|*.zip'
                if (-not $zip) { return }
                $dir = Select-FolderPath 'Выберите пустую папку, куда восстановить хранилище'
                if (-not $dir) { return }
                if (@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue).Count -gt 0) { Show-Warning 'Папка должна быть пустой.'; return }
                Restore-Storage $zip $dir
                Switch-Storage $dir
            } } 'scan')
        ))
        (New-MenuItem 'Перезагрузить' { Invoke-Safe { Reload-Storage; Set-DataChanged; Build-Tree; Refresh-CurrentTab } } 'scan')
        (New-MenuItem 'Открыть папку хранилища' { Invoke-Safe { Start-Process explorer.exe $script:Store.Root } } 'folder')
    )
    Show-DropMenu $ui.btnStorageMenu $items
}

function Show-InventoryMenu {
    $items = @(
        (New-MenuItem 'Начать быстрое сканирование' { Invoke-Safe { $ui.tabScanner.IsChecked = $true; Start-QuickScan } } 'scan')
        (New-MenuItem 'Сканировать этот компьютер' { Invoke-Safe {
            $ui.tabScanner.IsChecked = $true
            [void](Add-ScanTasks @(New-ScanTask 'Local' ('Этот компьютер ({0})' -f $env:COMPUTERNAME) @{ Target = 'localhost' }))
            Start-Scan
        } } 'home')
        (New-MenuItem 'Сканировать выбранное в дереве' { Invoke-Safe { Add-DeviceTasks (Get-ScopeDevices) $true } } 'play')
        (New-MenuSeparator)
        (New-MenuItem 'Создать автономный сборщик...' { Invoke-Safe { New-OfflineCollector } } 'save')
        (New-MenuItem 'Импортировать снимки...' { Invoke-Safe { Import-SnapshotsInteractive } } 'add')
    )
    Show-DropMenu $ui.btnInventoryMenu $items
}

function Show-HelpMenu {
    $items = @(
        (New-MenuItem 'Помощь по добавлению задач' { Show-TaskHelp } 'help')
        (New-MenuItem 'Папка настроек и журнала ошибок' { Invoke-Safe { if (-not (Test-Path $script:AppDataDir)) { [void](New-Item -ItemType Directory -Path $script:AppDataDir) }; Start-Process explorer.exe $script:AppDataDir } } 'folder')
        (New-MenuSeparator)
        (New-MenuItem 'О программе' { Show-Info ("{0} {1}`n`nИнвентаризация компьютеров сети на PowerShell и WPF.`nСбор данных: WinRM (PowerShell Remoting) и WMI/DCOM.`n`nХранилище: {2}`nPowerShell: {3}" -f $script:AppName, $script:AppVersion, $script:Store.Root, $PSVersionTable.PSVersion) 'О программе' } 'info')
    )
    Show-DropMenu $ui.btnHelpMenu $items
}

function Initialize-MainWindow {
    $script:Xaml = Import-Xaml -Path (Join-Path $script:UiDir 'MainWindow.xaml')
    $script:MainWindow = $script:Xaml.Root
    $script:ui = $script:Xaml.C
    $w = $script:MainWindow

    $ws = $script:Settings.Window
    try {
        if ($ws.Width -ge 900) { $w.Width = [double]$ws.Width }
        if ($ws.Height -ge 600) { $w.Height = [double]$ws.Height }
        if ($ws.Maximized) { $w.WindowState = 'Maximized' }
    } catch { }

    # --- верхние меню
    $ui.btnStorageMenu.Add_Click({ Invoke-Safe { Show-StorageMenu } })
    $ui.btnInventoryMenu.Add_Click({ Invoke-Safe { Show-InventoryMenu } })
    $ui.btnHelpMenu.Add_Click({ Invoke-Safe { Show-HelpMenu } })
    $ui.btnSettings.Add_Click({ Invoke-Safe {
        $r = Show-SettingsDialog 'general'
        if ($r -eq 'storage') { Switch-Storage $script:Settings.StoragePath }
        elseif ($r) { Set-DataChanged; Refresh-CurrentTab }
    } })

    # --- дерево
    $ui.tvStorage.Add_SelectedItemChanged({ param($s, $e) Invoke-Safe {
        if ($script:State.SuppressEvents) { return }
        $n = $e.NewValue
        if (-not $n) { return }
        $script:State.Node = $n
        Refresh-CurrentTab
    } })
    $ui.tvStorage.Add_PreviewMouseRightButtonDown({ param($s, $e) Invoke-Safe {
        $item = Find-Ancestor $e.OriginalSource ([System.Windows.Controls.TreeViewItem])
        if ($item) { $item.IsSelected = $true; $item.Focus() | Out-Null }
    } })
    $ui.tvStorage.Add_MouseRightButtonUp({ Invoke-Safe { Show-TreeContextMenu } })
    $ui.tvStorage.Add_MouseDoubleClick({ param($s, $e) Invoke-Safe {
        $n = $script:State.Node
        if ($n -and $n.Kind -eq 'Device') { $ui.tabView.IsChecked = $true }
    } })
    $ui.tvStorage.Add_KeyDown({ param($s, $e) Invoke-Safe {
        $n = $script:State.Node
        if ($e.Key -eq 'Delete' -and $n -and $n.Kind -ne 'Root') { Show-TreeContextMenu }
        if ($e.Key -eq 'F2' -and $n -and $n.Kind -eq 'Device') { Edit-SpecialInfo }
    } })
    $ui.txtTreeSearch.Add_TextChanged({ Set-Placeholder $ui.txtTreeSearch $ui.phTreeSearch; Invoke-Safe { Apply-TreeFilter } })
    $ui.btnTreeSort.Add_Click({ Invoke-Safe {
        $script:State.SortByIp = -not $script:State.SortByIp
        $ui.txtTreeSort.Text = $(if ($script:State.SortByIp) { 'IP' + [char]0x2193 } else { 'A' + [char]0x2193 })
        Build-Tree
    } })
    $ui.btnNewFolder.Add_Click({ Invoke-Safe { New-FolderInteractive } })
    $ui.btnAssistToggle.Add_Click({
        $vis = $ui.pnlAssist.Visibility -eq 'Visible'
        $ui.pnlAssist.Visibility = $(if ($vis) { 'Collapsed' } else { 'Visible' })
        $ui.txtAssistArrow.Text = $(if ($vis) { [string][char]0x2304 } else { [string][char]0x2303 })
    })
    $ui.tglOnline.IsChecked = [bool]$script:Settings.OnlineStatus
    $ui.tglOnline.Add_Click({ Invoke-Safe {
        $script:Settings.OnlineStatus = [bool]$ui.tglOnline.IsChecked
        Save-Settings
        Update-OnlineDots
        if ($script:Settings.OnlineStatus) { $script:State.LastPing = [datetime]::MinValue }
    } })

    # --- вкладки
    $ui.tabScanner.Add_Checked({ Invoke-Safe { Show-Tab 'scanner' } })
    $ui.tabView.Add_Checked({ Invoke-Safe { Show-Tab 'view' } })
    $ui.tabTables.Add_Checked({ Invoke-Safe { Show-Tab 'tables' } })
    $ui.tabSoftware.Add_Checked({ Invoke-Safe { Show-Tab 'software' } })
    $ui.tabLicenses.Add_Checked({ Invoke-Safe { Show-Tab 'licenses' } })
    $ui.tabChanges.Add_Checked({ Invoke-Safe { Show-Tab 'changes' } })
    $ui.btnHome.Add_Click({ Invoke-Safe { if ($script:TreeRoot) { $script:TreeRoot.IsSelected = $true }; $ui.tabView.IsChecked = $true } })

    Initialize-ScannerPage
    Initialize-ViewPage
    Initialize-TablesPage
    Initialize-SoftwarePage
    Initialize-LicensesPage
    Initialize-ChangesPage

    # --- клавиатура
    $w.Add_PreviewKeyDown({ param($s, $e) Invoke-Safe {
        if ($e.Key -eq 'F5') {
            if ($script:State.Tab -eq 'changes') { Show-ChangesPage -Force } else { Set-DataChanged; Refresh-CurrentTab }
            $e.Handled = $true
        }
        if ($e.Key -eq 'F' -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) { $ui.txtTreeSearch.Focus() | Out-Null; $e.Handled = $true }
    } })

    # --- таймер: сообщения сканера и онлайн-статус
    $script:Timer = New-Object System.Windows.Threading.DispatcherTimer
    $script:Timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:Timer.Add_Tick({
        try {
            Process-ScanMessages
            Receive-OnlinePing
            if ($script:Settings.OnlineStatus -and -not $script:State.Ping -and ((Get-Date) - $script:State.LastPing).TotalSeconds -ge 60) { Start-OnlinePing }
        } catch { Write-AppLog ('Timer: ' + $_.Exception.Message) }
    })

    $w.Add_Loaded({ Invoke-Safe {
        Build-Tree
        Update-ScannerView
        $script:Timer.Start()
        if (@($script:Store.Devices).Count -gt 0) { $ui.tabView.IsChecked = $true }
        Add-Log 'info' ('Хранилище: {0} (устройств: {1})' -f $script:Store.Root, @($script:Store.Devices).Count)
    } })
    $w.Add_Closing({ param($s, $e)
        try {
            if ($script:State.Engine -and $script:State.Engine.Running) {
                if (-not (Confirm-Action 'Идёт сканирование. Прервать его и закрыть программу?')) { $e.Cancel = $true; return }
                Stop-ScanEngine $script:State.Engine
            }
            $script:Timer.Stop()
            $script:Settings.Window.Maximized = ($w.WindowState -eq 'Maximized')
            if ($w.WindowState -eq 'Normal') { $script:Settings.Window.Width = [int]$w.ActualWidth; $script:Settings.Window.Height = [int]$w.ActualHeight }
            Save-Settings
        } catch { }
    })
}

function Start-App {
    # Ресурсы оформления — на уровне приложения (доступны всем окнам)
    $app = [System.Windows.Application]::Current
    if (-not $app) {
        $app = New-Object System.Windows.Application
        $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    }
    $theme = [System.Windows.Markup.XamlReader]::Parse([System.IO.File]::ReadAllText((Join-Path $script:UiDir 'Theme.xaml'), [System.Text.Encoding]::UTF8))
    $app.Resources.MergedDictionaries.Clear()
    $app.Resources.MergedDictionaries.Add($theme)

    try { [void](Open-Storage $script:Settings.StoragePath) }
    catch {
        Show-Warning ("Не удалось открыть хранилище:`n{0}`n`n{1}`n`nБудет использована папка по умолчанию." -f $script:Settings.StoragePath, $_.Exception.Message)
        $script:Settings.StoragePath = (Get-DefaultSettings).StoragePath
        [void](Open-Storage $script:Settings.StoragePath)
    }
    Save-Settings

    Initialize-MainWindow
    [void]$script:MainWindow.ShowDialog()
}
