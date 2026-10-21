# Main.ps1 — главное окно: дерево хранилища, вкладки, меню, таймеры

$script:State = @{
    Node          = $null      # выбранный узел дерева
    Tab           = 'scanner'
    SortByIp      = $false
    CardCats      = @('general')
    CardExpanded  = @{}
    Stamp         = ''
    StampDeviceId = ''
    TemplateId    = ''
    SwView        = 'list'
    LicView       = 'all'
    DataVersion   = 0
    TreeExpanded  = @{ '' = $true }
    Engine        = $null
    ScanTotal     = 0
    ScanDone      = 0
    ScanFound     = 0
    ScanErrors    = 0
    TaskProgress  = @{}
    TaskFolders   = @{}
    ChangesDirty  = $false
    AdCreds       = @{}
    LastPing      = [datetime]::MinValue
    Ping          = $null
    SuppressEvents = $false
}
$script:NodeByDevice = @{}
$script:NodeByFolder = @{}
$script:TaskRows = New-Object 'System.Collections.ObjectModel.ObservableCollection[NetInv.ScanTaskRow]'
$script:LogItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[NetInv.LogEntry]'
$script:SwCache = @{ Key = ''; Summary = @() }
$script:CollectorPath = Join-Path $script:SrcDir 'Collector.ps1'

# ===========================================================================
#  Общие помощники
# ===========================================================================
function Get-DeviceIconName {
    param($Device)
    $t = [string]$Device['Type']
    if ($t -and $script:Icons.ContainsKey($t)) { return $t }
    return 'Desktop'
}

function Get-StatusColor {
    param($Device)
    if (-not $script:Settings.OnlineStatus) { return 'Transparent' }
    $o = $Device['Online']
    if ($o -eq $true) { return '#2DB84D' }
    if ($o -eq $false) { return '#C8C8C8' }
    return 'Transparent'
}

function Set-DataChanged {
    $script:State.DataVersion++
}

function Get-ScrollViewer {
    param($Element)
    if ($null -eq $Element) { return $null }
    if ($Element -is [System.Windows.Controls.ScrollViewer]) { return $Element }
    $n = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element)
    for ($i = 0; $i -lt $n; $i++) {
        $r = Get-ScrollViewer ([System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i))
        if ($r) { return $r }
    }
    return $null
}

function Find-Ancestor {
    param($Element, [type]$Type)
    $e = $Element
    while ($e -and -not ($e -is $Type)) {
        if ($e -is [System.Windows.Media.Visual] -or $e -is [System.Windows.Media.Media3D.Visual3D]) { $e = [System.Windows.Media.VisualTreeHelper]::GetParent($e) }
        elseif ($e -is [System.Windows.FrameworkContentElement]) { $e = $e.Parent }
        else { return $null }
    }
    return $e
}

function Set-Placeholder {
    param($TextBox, $Placeholder)
    $Placeholder.Visibility = $(if ($TextBox.Text) { 'Collapsed' } else { 'Visible' })
}

function New-SideItem {
    param([string]$Id, [string]$Kind, [string]$Name, [string]$Icon = '', [double]$Indent = 0, $Tag = $null)
    $it = New-Object NetInv.SideItem
    $it.Id = $Id; $it.Kind = $Kind; $it.Name = $Name; $it.Indent = $Indent; $it.Tag = $Tag
    if ($Icon) { $it.Glyph = Get-IconGlyph $Icon; $it.GlyphColor = Get-IconColor $Icon }
    return $it
}

function Escape-RowFilter {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        switch ($ch) {
            "'" { [void]$sb.Append("''") }
            '*' { [void]$sb.Append('[*]') }
            '%' { [void]$sb.Append('[%]') }
            '[' { [void]$sb.Append('[[]') }
            ']' { [void]$sb.Append('[]]') }
            default { [void]$sb.Append($ch) }
        }
    }
    return $sb.ToString()
}

function Set-TableFilter {
    param([System.Data.DataTable]$Table, [string]$Text)
    if (-not $Table) { return }
    if ([string]::IsNullOrWhiteSpace($Text)) { $Table.DefaultView.RowFilter = ''; return }
    $t = Escape-RowFilter $Text.Trim()
    $parts = @()
    foreach ($c in $Table.Columns) {
        if ($c.DataType -eq [string]) { $parts += ("[{0}] LIKE '%{1}%'" -f $c.ColumnName, $t) }
    }
    try { $Table.DefaultView.RowFilter = ($parts -join ' OR ') } catch { $Table.DefaultView.RowFilter = '' }
}

function Convert-ViewToTable {
    # Отфильтрованное представление DataTable -> новая DataTable (для экспорта)
    param([System.Data.DataTable]$Table)
    $copy = $Table.DefaultView.ToTable()
    for ($i = 0; $i -lt $Table.Columns.Count; $i++) { $copy.Columns[$i].Caption = $Table.Columns[$i].Caption }
    return ,$copy
}

function Set-GridTable {
    # Привязка DataTable к DataGrid с автостолбцами (заголовки из Caption)
    param($Grid, [System.Data.DataTable]$Table)
    $Grid.Tag = $Table
    $Grid.ItemsSource = $null
    if ($Table) { $Grid.ItemsSource = $Table.DefaultView }
}

function Register-AutoColumns {
    param($Grid)
    $Grid.Add_AutoGeneratingColumn({
        param($s, $e)
        $tbl = $s.Tag
        if ($tbl -and $tbl.Columns.Contains($e.PropertyName)) {
            $e.Column.Header = $tbl.Columns[$e.PropertyName].Caption
            if ($tbl.Columns[$e.PropertyName].Caption -eq '№') { $e.Column.Width = New-Object System.Windows.Controls.DataGridLength(40) }
        }
    })
}

function Export-Table {
    # Меню экспорта для таблицы. $GetTable — скрипт-блок, возвращающий DataTable
    param($Button, [scriptblock]$GetTable, [string]$Title)
    $ctx = @{ Get = $GetTable; Title = $Title }
    $items = @(
        (New-MenuItem 'Сохранить как CSV (Excel)...' { param($s, $e) Invoke-Safe {
            $c = $s.Tag; $t = & $c.Get; if (-not $t) { return }
            $p = Select-SaveFile 'CSV (*.csv)|*.csv' ($c.Title + '.csv'); if (-not $p) { return }
            Save-TextFile $p (ConvertTo-CsvText (Convert-ViewToTable $t)) -Bom
            Add-Log 'ok' ('Экспортировано: ' + $p)
        } } 'save' @() $true $ctx)
        (New-MenuItem 'Сохранить как HTML...' { param($s, $e) Invoke-Safe {
            $c = $s.Tag; $t = & $c.Get; if (-not $t) { return }
            $p = Select-SaveFile 'HTML (*.html)|*.html' ($c.Title + '.html'); if (-not $p) { return }
            Save-TextFile $p (ConvertTo-HtmlTable $c.Title ('Создано: ' + (Get-Date).ToString('dd.MM.yyyy HH:mm')) (Convert-ViewToTable $t))
            Open-InShell $p
        } } 'report' @() $true $ctx)
        (New-MenuSeparator)
        (New-MenuItem 'Копировать как текст' { param($s, $e) Invoke-Safe { $t = & $s.Tag.Get; if ($t) { [System.Windows.Clipboard]::SetText((ConvertTo-TabText (Convert-ViewToTable $t))) } } } 'copy' @() $true $ctx)
        (New-MenuItem 'Копировать как CSV' { param($s, $e) Invoke-Safe { $t = & $s.Tag.Get; if ($t) { [System.Windows.Clipboard]::SetText((ConvertTo-CsvText (Convert-ViewToTable $t))) } } } 'copy' @() $true $ctx)
    )
    Show-DropMenu $Button $items
}

# ===========================================================================
#  Дерево хранилища
# ===========================================================================
function Get-SelectedNode { return $script:State.Node }

function Get-ScopeDevices {
    $n = $script:State.Node
    if (-not $n -or $n.Kind -eq 'Root') { return @($script:Store.Devices) }
    if ($n.Kind -eq 'Folder') { return @(Get-DevicesUnder ([string]$n.Tag)) }
    return @($n.Tag)
}

function Get-ScopeInfo {
    # Возвращает @{ Title; Icon }
    $n = $script:State.Node
    if (-not $n -or $n.Kind -eq 'Root') { return @{ Title = $script:Store.Name; Icon = 'root' } }
    if ($n.Kind -eq 'Folder') { return @{ Title = $n.Name; Icon = 'folder' } }
    return @{ Title = [string]$n.Tag['Name']; Icon = (Get-DeviceIconName $n.Tag) }
}

function Compare-IpKey {
    param([string]$Ip)
    if ($Ip -match '^(\d+)\.(\d+)\.(\d+)\.(\d+)$') { return ('{0:D3}{1:D3}{2:D3}{3:D3}' -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4]) }
    return '999999999999'
}

function New-DeviceNode {
    param($Device, [int]$Depth, $Parent)
    $n = New-Object NetInv.Node
    $n.Kind = 'Device'; $n.Id = [string]$Device['Id']; $n.Tag = $Device; $n.Depth = $Depth; $n.Parent = $Parent
    $n.Name = [string]$Device['Name']; $n.Ip = [string]$Device['Ip']
    $ic = Get-DeviceIconName $Device
    $n.Glyph = Get-IconGlyph $ic; $n.GlyphColor = Get-IconColor $ic
    $n.StatusColor = Get-StatusColor $Device
    $script:NodeByDevice[$n.Id] = $n
    return $n
}

function Add-FolderNodes {
    param($ParentNode, [string]$Rel, [int]$Depth)
    foreach ($f in (Get-ChildFolders $Rel)) {
        $fn = New-Object NetInv.Node
        $fn.Kind = 'Folder'; $fn.Id = 'F:' + $f; $fn.Tag = $f; $fn.Depth = $Depth; $fn.Parent = $ParentNode
        $fn.Name = Get-FolderLeaf $f
        $fn.Glyph = Get-IconGlyph 'folder'; $fn.GlyphColor = Get-IconColor 'folder'
        $fn.IsExpanded = $(if ($script:State.TreeExpanded.ContainsKey($f)) { [bool]$script:State.TreeExpanded[$f] } else { $true })
        $script:NodeByFolder[$f] = $fn
        Add-FolderNodes $fn $f ($Depth + 1)
        $ParentNode.Children.Add($fn)
    }
    $devs = @($script:Store.Devices | Where-Object { [string]$_['_Folder'] -eq $Rel })
    if ($script:State.SortByIp) { $devs = @($devs | Sort-Object { Compare-IpKey ([string]$_['Ip']) }, { [string]$_['Name'] }) }
    else { $devs = @($devs | Sort-Object { [string]$_['Name'] }) }
    foreach ($d in $devs) { $ParentNode.Children.Add((New-DeviceNode $d $Depth $ParentNode)) }
}

function Update-NodeCounts {
    param($Node)
    if ($Node.Kind -eq 'Device') { return 1 }
    $sum = 0
    foreach ($c in $Node.Children) { $sum += (Update-NodeCounts $c) }
    $Node.Count = '(' + $sum + ')'
    return $sum
}

function Build-Tree {
    # запоминаем раскрытие и выбор
    $selId = $null
    if ($script:State.Node) { $selId = $script:State.Node.Id }
    foreach ($k in @($script:NodeByFolder.Keys)) { $script:State.TreeExpanded[$k] = $script:NodeByFolder[$k].IsExpanded }
    $script:NodeByDevice = @{}; $script:NodeByFolder = @{}
    $root = New-Object NetInv.Node
    $root.Kind = 'Root'; $root.Id = 'ROOT'; $root.Tag = ''; $root.Depth = 0
    $root.Name = $script:Store.Name
    $root.Glyph = Get-IconGlyph 'root'; $root.GlyphColor = Get-IconColor 'root'
    $root.IsExpanded = $true
    $script:NodeByFolder[''] = $root
    Add-FolderNodes $root '' 1
    [void](Update-NodeCounts $root)
    $col = New-Object 'System.Collections.ObjectModel.ObservableCollection[NetInv.Node]'
    $col.Add($root)
    $script:TreeRoot = $root
    $script:State.SuppressEvents = $true
    $ui.tvStorage.ItemsSource = $col
    $script:State.SuppressEvents = $false
    # восстановление выбора
    $target = $null
    if ($selId) {
        if ($selId -eq 'ROOT') { $target = $root }
        elseif ($selId.StartsWith('F:')) { $target = $script:NodeByFolder[$selId.Substring(2)] }
        else { $target = $script:NodeByDevice[$selId] }
    }
    if (-not $target) { $target = $root }
    $target.IsSelected = $true
    $script:State.Node = $target
    Apply-TreeFilter
    Update-StatusBar
    Update-FolderOptions
}

function Apply-TreeFilter {
    $q = $ui.txtTreeSearch.Text.Trim()
    if (-not $script:TreeRoot) { return }
    [void](Set-NodeVisibility $script:TreeRoot $q)
}

function Set-NodeVisibility {
    param($Node, [string]$Query)
    if ($Node.Kind -eq 'Device') {
        $vis = $true
        if ($Query) {
            $d = $Node.Tag
            $vis = ([string]$d['Name']).IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                   ([string]$d['Ip']).IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                   ([string]$d['User']).IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                   ([string]$d['OsName']).IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0
        }
        $Node.Visible = $vis
        return $vis
    }
    $any = $false
    foreach ($c in $Node.Children) { if (Set-NodeVisibility $c $Query) { $any = $true } }
    if ($Node.Kind -eq 'Root') { $Node.Visible = $true; return $true }
    $self = (-not $Query) -or ($Node.Name.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    $Node.Visible = ($any -or $self)
    if ($Query -and $any) { $Node.IsExpanded = $true }
    return $Node.Visible
}

function Select-DeviceInTree {
    param([string]$DeviceId)
    $n = $script:NodeByDevice[$DeviceId]
    if (-not $n) { return }
    $p = $n.Parent
    while ($p) { $p.IsExpanded = $true; $p = $p.Parent }
    $n.IsSelected = $true
}

function Update-StatusBar {
    $all = @($script:Store.Devices)
    $ui.txtStatDevices.Text = [string]$all.Count
    $ui.txtStatOnline.Text = [string]@($all | Where-Object { $_['Online'] -eq $true }).Count
    $ui.txtStatFolders.Text = [string]$script:Store.Folders.Count
    $script:MainWindow.Title = '{0} — {1}' -f $script:AppName, $script:Store.Name
    $ui.txtStoragePath.Text = $script:Store.Root
}

function Show-TreeContextMenu {
    $n = $script:State.Node
    if (-not $n) { return }
    $items = @()
    if ($n.Kind -eq 'Device') {
        $dev = $n.Tag
        $items += New-MenuItem 'Сканировать снова' { Invoke-Safe { Add-DeviceTasks @($script:State.Node.Tag) $true } } 'scan'
        $items += New-MenuItem 'Открыть в просмотре' { $ui.tabView.IsChecked = $true } 'view'
        $items += New-MenuItem 'Специальная информация...' { Invoke-Safe { Edit-SpecialInfo } } 'special'
        $items += New-MenuItem 'Переименовать...' { Invoke-Safe {
            $d = $script:State.Node.Tag
            $nn = Show-InputBox 'Переименование' 'Новое имя устройства:' ([string]$d['Name'])
            if ($nn -and $nn.Trim() -ne [string]$d['Name']) { Rename-StorageDevice $d $nn.Trim(); Build-Tree; Set-DataChanged; Refresh-CurrentTab }
        } } 'special'
        $moveItems = @()
        $folders = @('') + @($script:Store.Folders | Sort-Object)
        foreach ($f in $folders) {
            $label = $(if ($f) { $f } else { $script:Store.Name + ' (корень)' })
            $moveItems += New-MenuItem $label { param($s, $e) Invoke-Safe {
                $d = $script:State.Node.Tag
                Move-StorageDevice $d ([string]$s.Tag); Build-Tree; Select-DeviceInTree $d['Id']; Set-DataChanged
            } } 'folder' @() ([string]$dev['_Folder'] -ne $f) $f
        }
        $items += New-MenuItem 'Переместить в' $null 'folder' $moveItems
        $items += New-MenuSeparator
        $items += New-MenuItem 'Удалить...' { Invoke-Safe {
            $d = $script:State.Node.Tag
            if (Confirm-Action ('Удалить устройство «{0}» и всю его историю сканирований?' -f $d['Name'])) {
                Remove-StorageDevice $d; $script:State.Node = $null; Build-Tree; Set-DataChanged; Refresh-CurrentTab
            }
        } } 'delete'
    } else {
        $isRoot = ($n.Kind -eq 'Root')
        $items += New-MenuItem $(if ($isRoot) { 'Сканировать все устройства' } else { 'Сканировать устройства папки' }) { Invoke-Safe { Add-DeviceTasks (Get-ScopeDevices) $true } } 'scan'
        $items += New-MenuItem $(if ($isRoot) { 'Создать папку...' } else { 'Создать подпапку...' }) { Invoke-Safe { New-FolderInteractive } } 'folder'
        if (-not $isRoot) {
            $items += New-MenuItem 'Переименовать...' { Invoke-Safe {
                $rel = [string]$script:State.Node.Tag
                $nn = Show-InputBox 'Переименование' 'Новое имя папки:' (Get-FolderLeaf $rel)
                if ($nn -and $nn.Trim()) { Rename-StorageFolder $rel $nn.Trim(); $script:State.Node = $null; Build-Tree; Set-DataChanged }
            } } 'special'
            $items += New-MenuSeparator
            $items += New-MenuItem 'Удалить папку...' { Invoke-Safe {
                $rel = [string]$script:State.Node.Tag
                $cnt = @(Get-DevicesUnder $rel).Count
                if (Confirm-Action ('Удалить папку «{0}»{1}?' -f (Get-FolderLeaf $rel), $(if ($cnt) { " и все устройства в ней ($cnt)" } else { '' }))) {
                    Remove-StorageFolder $rel; $script:State.Node = $null; Build-Tree; Set-DataChanged; Refresh-CurrentTab
                }
            } } 'delete'
        } else {
            $items += New-MenuItem 'Перечитать хранилище' { Invoke-Safe { Reload-Storage; Build-Tree; Set-DataChanged; Refresh-CurrentTab } } 'scan'
        }
    }
    $cm = New-Object System.Windows.Controls.ContextMenu
    foreach ($i in $items) { [void]$cm.Items.Add($i) }
    $cm.PlacementTarget = $ui.tvStorage
    $cm.IsOpen = $true
}

function New-FolderInteractive {
    $n = $script:State.Node
    $parent = ''
    if ($n -and $n.Kind -eq 'Folder') { $parent = [string]$n.Tag }
    elseif ($n -and $n.Kind -eq 'Device') { $parent = [string]$n.Tag['_Folder'] }
    $name = Show-InputBox 'Новая папка' 'Имя папки:' 'Новая папка'
    if (-not $name -or -not $name.Trim()) { return }
    $rel = New-StorageFolder $parent $name.Trim()
    $script:State.TreeExpanded[$parent] = $true
    Build-Tree
    $fn = $script:NodeByFolder[$rel]
    if ($fn) { $fn.IsSelected = $true }
}

function Edit-SpecialInfo {
    $n = $script:State.Node
    if (-not $n -or $n.Kind -ne 'Device') { return }
    $d = $n.Tag
    $r = Show-SpecialInfoDialog $d
    if (-not $r) { return }
    $d['AssignedUser'] = $r.AssignedUser; $d['Location'] = $r.Location; $d['Note'] = $r.Note
    if ($r.Name -and $r.Name -ne [string]$d['Name']) { Rename-StorageDevice $d $r.Name } else { Save-DeviceHeader $d }
    Build-Tree; Select-DeviceInTree $d['Id']; Refresh-CurrentTab
}

# ===========================================================================
#  Онлайн-статус (фоновый пинг)
# ===========================================================================
$script:PingScript = {
    param($Targets, $Timeout)
    $res = @{}
    $tasks = @{}
    foreach ($t in $Targets) {
        try { $p = New-Object System.Net.NetworkInformation.Ping; $tasks[$t] = $p.SendPingAsync($t, $Timeout) } catch { $res[$t] = $false }
    }
    if ($tasks.Count -gt 0) {
        try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($tasks.Values), ($Timeout + 3000)) } catch { }
        foreach ($k in $tasks.Keys) {
            $tk = $tasks[$k]
            $ok = $false
            try { if ($tk.Status -eq 'RanToCompletion' -and $tk.Result.Status -eq 'Success') { $ok = $true } } catch { }
            $res[$k] = $ok
        }
    }
    return $res
}

function Start-OnlinePing {
    if (-not $script:Settings.OnlineStatus) { return }
    if ($script:State.Ping) { return }
    $targets = @($script:Store.Devices | ForEach-Object { if ($_['Ip']) { [string]$_['Ip'] } } | Sort-Object -Unique)
    if ($targets.Count -eq 0) { return }
    $ps = [powershell]::Create()
    [void]$ps.AddScript($script:PingScript.ToString()).AddArgument($targets).AddArgument(1500)
    $script:State.Ping = @{ PS = $ps; Handle = $ps.BeginInvoke() }
    $script:State.LastPing = Get-Date
    $ui.txtOnlineInfo.Text = 'проверка...'
}

function Receive-OnlinePing {
    $p = $script:State.Ping
    if (-not $p -or -not $p.Handle.IsCompleted) { return }
    $res = $null
    try { $out = $p.PS.EndInvoke($p.Handle); if ($out.Count -gt 0) { $res = $out[0] } } catch { }
    $p.PS.Dispose()
    $script:State.Ping = $null
    $ui.txtOnlineInfo.Text = ''
    if (-not $res -or -not $script:Settings.OnlineStatus) { return }
    $now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    foreach ($d in $script:Store.Devices) {
        $ip = [string]$d['Ip']
        if (-not $ip -or -not $res.ContainsKey($ip)) { continue }
        $on = [bool]$res[$ip]
        $changed = ($d['Online'] -ne $on)
        $d['Online'] = $on
        if ($on) { $d['LastPing'] = $now }
        if ($changed) { try { Save-DeviceHeader $d } catch { } }
        $n = $script:NodeByDevice[[string]$d['Id']]
        if ($n) { $n.StatusColor = Get-StatusColor $d }
    }
    Update-StatusBar
}

function Update-OnlineDots {
    foreach ($d in $script:Store.Devices) {
        $n = $script:NodeByDevice[[string]$d['Id']]
        if ($n) { $n.StatusColor = Get-StatusColor $d }
    }
}

# ===========================================================================
#  Вкладки
# ===========================================================================
function Show-Tab {
    param([string]$Name)
    $script:State.Tab = $Name
    $map = @{ scanner = $ui.pageScanner; view = $ui.pageView; tables = $ui.pageTables; software = $ui.pageSoftware; licenses = $ui.pageLicenses; changes = $ui.pageChanges }
    foreach ($k in $map.Keys) { $map[$k].Visibility = $(if ($k -eq $Name) { 'Visible' } else { 'Collapsed' }) }
    Refresh-CurrentTab
}

function Refresh-CurrentTab {
    switch ($script:State.Tab) {
        'scanner'  { Update-ScannerView }
        'view'     { Show-ViewPage }
        'tables'   { Show-TablesPage }
        'software' { Show-SoftwarePage }
        'licenses' { Show-LicensesPage }
        'changes'  { Show-ChangesPage }
    }
}
