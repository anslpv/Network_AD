# Main.View.ps1 — вкладки «Просмотр и отчеты» и «Табличные отчеты»

# ===========================================================================
#  Просмотр и отчеты
# ===========================================================================
$script:CategoryItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[NetInv.SideItem]'
$script:CardRowsCache = $null

function Build-CategoryList {
    $script:CategoryItems.Clear()
    $lastGroup = $null
    foreach ($c in $script:CardCategories) {
        if ($c.Group -ne $lastGroup) {
            if ($c.Group -eq '-') { $script:CategoryItems.Add((New-SideItem ('sep') 'Separator' '')) }
            elseif ($c.Group) { $script:CategoryItems.Add((New-SideItem ('hdr:' + $c.Group) 'Header' $c.Group '' 0 $c.Group)) }
            $lastGroup = $c.Group
        }
        $it = New-SideItem $c.Id 'Item' $c.Name $c.Icon 4 $c.Group
        $script:CategoryItems.Add($it)
    }
    $ui.lbCategories.ItemsSource = $script:CategoryItems
    foreach ($it in $script:CategoryItems) { if ($it.Id -eq 'general') { $ui.lbCategories.SelectedItem = $it } }
}

function Update-AlertCount {
    param($Data)
    $cnt = 0
    if ($Data) { $cnt = @(Get-DeviceAlerts $Data).Count }
    foreach ($it in $script:CategoryItems) { if ($it.Id -eq 'alerts') { $it.Count = $(if ($cnt -gt 0) { [string]$cnt } else { '' }) } }
}

function Get-CardData {
    $n = $script:State.Node
    if (-not $n -or $n.Kind -ne 'Device') { return $null }
    $d = $n.Tag
    $stamp = $(if ($script:State.StampDeviceId -eq $d['Id']) { $script:State.Stamp } else { '' })
    return (Get-DeviceSnapshot $d $stamp)
}

function New-CardRow {
    param([string]$Kind, [string]$Text, [string]$Value = '', [string]$Value2 = '', [string]$Mark = '', [double]$Indent = 0, [string]$Icon = '', [bool]$Expandable = $false, [bool]$Expanded = $false, [string]$Key = '')
    $r = New-Object NetInv.CardRow
    $r.Kind = $Kind; $r.Text = $Text; $r.Value = $Value; $r.Value2 = $Value2; $r.Mark = $Mark; $r.Indent = $Indent
    if ($Icon) { $r.Glyph = Get-IconGlyph $Icon; $r.GlyphColor = Get-IconColor $Icon }
    $r.Expandable = $Expandable; $r.Expanded = $Expanded; $r.Key = $Key
    return $r
}

function Test-Match {
    param([string]$Text, [string]$Query)
    if (-not $Query) { return $true }
    if ($null -eq $Text) { return $false }
    return ($Text.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Add-BlockRows {
    param($List, $Block, [string]$KeyPrefix, [double]$Indent, [string]$Query)
    $key = $KeyPrefix + '|' + $Block.Title
    $exp = $Block.Expanded
    if ($script:State.CardExpanded.ContainsKey($key)) { $exp = [bool]$script:State.CardExpanded[$key] }
    $titleHit = Test-Match ($Block.Title + ' ' + $Block.Extra) $Query
    $props = @($Block.Props)
    if ($Query -and -not $titleHit) { $props = @($props | Where-Object { (Test-Match $_.K $Query) -or (Test-Match $_.V $Query) -or (Test-Match $_.V2 $Query) }) }
    $subsHit = $false
    if ($Query) { foreach ($sb in $Block.Subs) { foreach ($p in $sb.Props) { if ((Test-Match $p.K $Query) -or (Test-Match $p.V $Query)) { $subsHit = $true } } } }
    if ($Query -and -not $titleHit -and $props.Count -eq 0 -and -not $subsHit) { return }
    if ($Query) { $exp = $true }
    $kind = $(if ($Block.Style -eq 'item') { 'Item' } else { 'Group' })
    $List.Add((New-CardRow $kind $Block.Title $Block.Extra '' '' $Indent $Block.Icon $true $exp $key))
    if (-not $exp) { return }
    $pi = $Indent
    if ($kind -eq 'Item') { $pi = $Indent + 18 }
    foreach ($p in $props) { $List.Add((New-CardRow 'Prop' $p.K $p.V $p.V2 $p.Mark $pi)) }
    foreach ($sb in $Block.Subs) { Add-BlockRows $List $sb $key ($Indent + 18) $Query }
}

function Build-CardRows {
    param($Device, $Data, [string[]]$CategoryIds, [string]$Query)
    $list = New-Object 'System.Collections.Generic.List[object]'
    $script:CardBlocksForExport = @()
    foreach ($cid in $CategoryIds) {
        $cat = Get-CardCategory $cid
        if (-not $cat) { continue }
        $blocks = @(Get-CardBlocks $cid $Device $Data)
        $script:CardBlocksForExport += @{ Name = $cat.Name; Blocks = $blocks }
        $list.Add((New-CardRow 'Header' $cat.Name))
        $before = $list.Count
        foreach ($b in $blocks) { Add-BlockRows $list $b $cid 0 $Query }
        if ($list.Count -eq $before) {
            $list.Add((New-CardRow 'Empty' $(if ($Query) { 'Ничего не найдено' } else { 'Нет данных' })))
        }
    }
    return ,$list
}

function Render-Card {
    param([bool]$KeepScroll = $false)
    $n = $script:State.Node
    if (-not $n -or $n.Kind -ne 'Device') { return }
    $data = Get-CardData
    $sv = Get-ScrollViewer $ui.lbCard
    $offset = 0
    if ($sv -and $KeepScroll) { $offset = $sv.VerticalOffset }
    if (-not $data) {
        $ui.lbCard.ItemsSource = $null
        $ui.lbCard.Visibility = 'Collapsed'
        $ui.pnlViewEmpty.Visibility = 'Visible'
        $ui.txtViewEmptyTitle.Text = 'Нет данных'
        $ui.txtViewEmptyText.Text = 'Для этого устройства нет сохранённых снимков. Отсканируйте его на вкладке «Сканер».'
        return
    }
    $rows = Build-CardRows $n.Tag $data $script:State.CardCats $ui.txtCardSearch.Text.Trim()
    $ui.lbCard.ItemsSource = $rows
    $ui.lbCard.Visibility = 'Visible'
    $ui.pnlViewEmpty.Visibility = 'Collapsed'
    $ui.dgFolder.Visibility = 'Collapsed'
    Update-AlertCount $data
    if ($sv) {
        if ($KeepScroll) { $ui.lbCard.UpdateLayout(); $sv.ScrollToVerticalOffset($offset) } else { $sv.ScrollToTop() }
    }
}

function Update-SnapshotSelector {
    param($Device)
    $script:State.SuppressEvents = $true
    try {
        $ui.cbSnapshots.Items.Clear()
        $snaps = @(As-Array $Device['Snapshots'] | Sort-Object)
        foreach ($s in $snaps) {
            $it = New-Object System.Windows.Controls.ComboBoxItem
            $it.Content = Format-DateTimeRu (ConvertFrom-Stamp $s) -NoRelative
            $it.Tag = $s
            [void]$ui.cbSnapshots.Items.Add($it)
        }
        $sel = $snaps.Count - 1
        if ($script:State.StampDeviceId -eq $Device['Id'] -and $script:State.Stamp) {
            $i = [array]::IndexOf($snaps, $script:State.Stamp); if ($i -ge 0) { $sel = $i }
        } else {
            $script:State.StampDeviceId = $Device['Id']
            $script:State.Stamp = $(if ($snaps.Count) { $snaps[$snaps.Count - 1] } else { '' })
        }
        if ($sel -ge 0) { $ui.cbSnapshots.SelectedIndex = $sel }
        $ui.btnSnapPrev.IsEnabled = ($sel -gt 0)
        $ui.btnSnapNext.IsEnabled = ($sel -lt $snaps.Count - 1)
        $ui.btnSnapDelete.IsEnabled = ($snaps.Count -gt 1)
    } finally { $script:State.SuppressEvents = $false }
}

function Show-FolderOverview {
    $devs = @(Get-ScopeDevices)
    $dt = New-SimpleTable @('Имя', 'IP-адрес', 'Тип', 'Операционная система', 'Модель', 'Пользователь', 'Последнее сканирование', 'Папка')
    $types = @{ Desktop = 'Настольный'; Laptop = 'Ноутбук'; Server = 'Сервер'; Virtual = 'Виртуальный' }
    foreach ($d in ($devs | Sort-Object { [string]$_['Name'] })) {
        Add-TableRow $dt @([string]$d['Name'], [string]$d['Ip'], $types[[string]$d['Type']], [string]$d['OsName'], [string]$d['Model'], [string]$d['User'], (Format-DateTimeRu $d['LastScan']), [string]$d['_Folder'])
    }
    Set-GridTable $ui.dgFolder $dt
    $script:FolderTable = $dt
    $ui.lbCard.Visibility = 'Collapsed'
    $ui.dgFolder.Visibility = $(if ($devs.Count) { 'Visible' } else { 'Collapsed' })
    $ui.pnlViewEmpty.Visibility = $(if ($devs.Count) { 'Collapsed' } else { 'Visible' })
    $ui.txtViewEmptyTitle.Text = 'Нет устройств'
    $ui.txtViewEmptyText.Text = 'В выбранной папке нет устройств. Добавьте задачи на вкладке «Сканер».'
}

function Show-ViewPage {
    $n = $script:State.Node
    $scope = Get-ScopeInfo
    $ui.txtViewTitle.Text = $scope.Title
    $ui.glyphViewTitle.Text = Get-IconGlyph $scope.Icon
    $ui.glyphViewTitle.Foreground = Get-IconColor $scope.Icon
    if ($n -and $n.Kind -eq 'Device') {
        $ui.pnlSnapshots.Visibility = 'Visible'
        $ui.lbCategories.IsEnabled = $true
        $ui.btnAddNote.IsEnabled = $true
        Update-SnapshotSelector $n.Tag
        Render-Card
    } else {
        $ui.pnlSnapshots.Visibility = 'Collapsed'
        $ui.lbCategories.IsEnabled = $false
        $ui.btnAddNote.IsEnabled = $false
        Update-AlertCount $null
        Show-FolderOverview
    }
}

function Select-Categories {
    if ($script:State.SuppressEvents) { return }
    $sel = @($ui.lbCategories.SelectedItems | Where-Object { $_.Kind -eq 'Item' })
    $bad = @($ui.lbCategories.SelectedItems | Where-Object { $_.Kind -ne 'Item' })
    if ($bad.Count -gt 0) {
        $script:State.SuppressEvents = $true
        if ($ui.lbCategories.SelectionMode -eq 'Single') { $ui.lbCategories.SelectedItem = $null }
        else { foreach ($b in $bad) { [void]$ui.lbCategories.SelectedItems.Remove($b) } }
        $script:State.SuppressEvents = $false
        foreach ($b in $bad) { if ($b.Kind -eq 'Header') { Toggle-CategoryGroup $b } }
    }
    if ($sel.Count -eq 0) {
        $script:State.SuppressEvents = $true
        foreach ($it in $script:CategoryItems) {
            if ($script:State.CardCats -contains $it.Id) {
                if ($ui.lbCategories.SelectionMode -eq 'Single') { $ui.lbCategories.SelectedItem = $it; break }
                [void]$ui.lbCategories.SelectedItems.Add($it)
            }
        }
        $script:State.SuppressEvents = $false
        return
    }
    $ids = @()
    foreach ($it in $script:CategoryItems) { if ($sel -contains $it) { $ids += $it.Id } }
    $script:State.CardCats = $ids
    if ($script:State.Tab -eq 'view') { Render-Card }
}

function Toggle-CategoryGroup {
    param($Header)
    $Header.IsCollapsed = -not $Header.IsCollapsed
    foreach ($it in $script:CategoryItems) { if ($it.Kind -eq 'Item' -and $it.Tag -eq $Header.Tag) { $it.Visible = -not $Header.IsCollapsed } }
}

function Get-CardExportPages {
    param([array]$Devices, [switch]$AllCategories)
    $pages = @()
    foreach ($d in $Devices) {
        $data = Get-DeviceSnapshot $d
        if (-not $data) { continue }
        $cats = $(if ($AllCategories) { @($script:CardCategories | Where-Object { $_.Id -notin @('snapshot') } | ForEach-Object { $_.Id }) } else { $script:State.CardCats })
        $sections = @()
        foreach ($cid in $cats) {
            $cat = Get-CardCategory $cid
            $blocks = @(Get-CardBlocks $cid $d $data)
            if ($blocks.Count -gt 0) { $sections += @{ Name = $cat.Name; Blocks = $blocks } }
        }
        $pages += @{ Title = [string]$d['Name']; Subtitle = ('{0}   {1}   снимок: {2}' -f $d['Ip'], $d['OsName'], (Format-DateTimeRu (Get-Val $data 'Meta' 'Timestamp') -NoRelative)); Sections = $sections }
    }
    return $pages
}

function Get-CurrentCardText {
    $n = $script:State.Node
    if (-not $n -or $n.Kind -ne 'Device') { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($s in $script:CardBlocksForExport) { [void]$sb.AppendLine((ConvertTo-PlainText $s.Name $s.Blocks)) }
    return $sb.ToString()
}

function Get-CurrentCardCsv {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('Категория;Группа;Свойство;Значение')
    foreach ($s in $script:CardBlocksForExport) {
        foreach ($b in $s.Blocks) {
            foreach ($p in $b.Props) {
                $v = ('{0} {1}' -f $p.V, $p.V2).Trim()
                [void]$sb.AppendLine((@($s.Name, $b.Title, $p.K, $v) | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }) -join ';')
            }
        }
    }
    return $sb.ToString()
}

function Initialize-ViewPage {
    Build-CategoryList
    Register-AutoColumns $ui.dgFolder
    $ui.lbCategories.Add_SelectionChanged({ Invoke-Safe { Select-Categories } })
    $ui.chkMultiCat.Add_Click({ Invoke-Safe {
        $multi = [bool]$ui.chkMultiCat.IsChecked
        $script:State.SuppressEvents = $true
        $cur = $ui.lbCategories.SelectedItem
        $ui.lbCategories.SelectionMode = $(if ($multi) { 'Multiple' } else { 'Single' })
        if (-not $multi -and $cur) { $ui.lbCategories.SelectedItem = $cur }
        $script:State.SuppressEvents = $false
        Select-Categories
    } })
    $ui.lbCard.Add_PreviewMouseLeftButtonUp({ param($s, $e) Invoke-Safe {
        $src = $e.OriginalSource
        $row = $null
        if ($src -and $src.PSObject.Properties['DataContext']) { $row = $src.DataContext }
        if ($row -is [NetInv.CardRow] -and $row.Expandable) {
            $script:State.CardExpanded[$row.Key] = -not $row.Expanded
            Render-Card $true
        }
    } })
    $ui.cbSnapshots.Add_SelectionChanged({ Invoke-Safe {
        if ($script:State.SuppressEvents) { return }
        $it = $ui.cbSnapshots.SelectedItem
        if (-not $it) { return }
        $script:State.Stamp = [string]$it.Tag
        $n = $script:State.Node
        if ($n -and $n.Kind -eq 'Device') { $script:State.StampDeviceId = $n.Tag['Id']; Update-SnapshotSelector $n.Tag; Render-Card $true }
    } })
    $ui.btnSnapPrev.Add_Click({ if ($ui.cbSnapshots.SelectedIndex -gt 0) { $ui.cbSnapshots.SelectedIndex-- } })
    $ui.btnSnapNext.Add_Click({ if ($ui.cbSnapshots.SelectedIndex -lt $ui.cbSnapshots.Items.Count - 1) { $ui.cbSnapshots.SelectedIndex++ } })
    $ui.btnSnapDelete.Add_Click({ Invoke-Safe {
        $n = $script:State.Node
        $it = $ui.cbSnapshots.SelectedItem
        if (-not $n -or $n.Kind -ne 'Device' -or -not $it) { return }
        if (-not (Confirm-Action ('Удалить снимок от {0}?' -f $it.Content))) { return }
        Remove-DeviceSnapshot $n.Tag ([string]$it.Tag)
        $script:State.Stamp = ''
        $script:State.StampDeviceId = ''
        Set-DataChanged
        Show-ViewPage
    } })
    $ui.txtCardSearch.Add_TextChanged({ Set-Placeholder $ui.txtCardSearch $ui.phCardSearch; Invoke-Safe { Render-Card } })
    $ui.btnViewCopy.Add_Click({ Invoke-Safe {
        $n = $script:State.Node
        if ($n -and $n.Kind -ne 'Device') {
            Export-Table $ui.btnViewCopy { $script:FolderTable } 'Устройства'
            return
        }
        Show-DropMenu $ui.btnViewCopy @(
            (New-MenuItem 'Копировать как текст' { Invoke-Safe { [System.Windows.Clipboard]::SetText((Get-CurrentCardText)) } } 'copy')
            (New-MenuItem 'Копировать как CSV' { Invoke-Safe { [System.Windows.Clipboard]::SetText((Get-CurrentCardCsv)) } } 'copy')
        )
    } })
    $ui.btnViewExport.Add_Click({ Invoke-Safe {
        $n = $script:State.Node
        if ($n -and $n.Kind -ne 'Device') { Export-Table $ui.btnViewExport { $script:FolderTable } 'Устройства'; return }
        Show-DropMenu $ui.btnViewExport @(
            (New-MenuItem 'Сохранить как HTML...' { Invoke-Safe {
                $d = $script:State.Node.Tag
                $p = Select-SaveFile 'HTML (*.html)|*.html' ([string]$d['Name'] + '.html'); if (-not $p) { return }
                Save-TextFile $p (ConvertTo-HtmlCards ([string]$d['Name']) @(Get-CardExportPages @($d)))
                Open-InShell $p
            } } 'report')
            (New-MenuItem 'Сохранить как текст...' { Invoke-Safe {
                $d = $script:State.Node.Tag
                $p = Select-SaveFile 'Текст (*.txt)|*.txt' ([string]$d['Name'] + '.txt'); if (-not $p) { return }
                Save-TextFile $p (Get-CurrentCardText) -Bom
            } } 'save')
            (New-MenuItem 'Сохранить как CSV...' { Invoke-Safe {
                $d = $script:State.Node.Tag
                $p = Select-SaveFile 'CSV (*.csv)|*.csv' ([string]$d['Name'] + '.csv'); if (-not $p) { return }
                Save-TextFile $p (Get-CurrentCardCsv) -Bom
            } } 'save')
        )
    } })
    $ui.btnPrintReports.Add_Click({ Invoke-Safe {
        $devs = @(Get-ScopeDevices)
        if ($devs.Count -eq 0) { Show-Info 'Нет устройств для отчета.'; return }
        if ($devs.Count -gt 50 -and -not (Confirm-Action ('Будет сформирован отчет по {0} устройствам. Продолжить?' -f $devs.Count))) { return }
        $scope = Get-ScopeInfo
        $script:MainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
        try {
            $html = ConvertTo-HtmlCards $scope.Title @(Get-CardExportPages $devs -AllCategories)
            $p = Join-Path ([IO.Path]::GetTempPath()) ('NetInventory_' + (Get-SafeFileName $scope.Title) + '_' + (Get-Date).ToString('yyyyMMdd_HHmmss') + '.html')
            Save-TextFile $p $html
        } finally { $script:MainWindow.Cursor = $null }
        Open-InShell $p
    } })
    $ui.btnAddNote.Add_Click({ Invoke-Safe { Edit-SpecialInfo } })
    $ui.dgFolder.Add_MouseDoubleClick({ Invoke-Safe {
        $it = $ui.dgFolder.SelectedItem
        if (-not $it) { return }
        $name = [string]$it.Row['c0']
        $d = $script:Store.Devices | Where-Object { [string]$_['Name'] -eq $name } | Select-Object -First 1
        if ($d) { Select-DeviceInTree $d['Id'] }
    } })
}

# ===========================================================================
#  Табличные отчеты
# ===========================================================================
$script:TemplateItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[NetInv.SideItem]'

function Build-TemplateList {
    $script:TemplateItems.Clear()
    $script:TemplateItems.Add((New-SideItem 'hdr:std' 'Header' 'Стандартные'))
    $emitted = @{}
    foreach ($t in $script:ReportTemplates) {
        $path = @($t.Path)
        for ($i = 0; $i -lt $path.Count; $i++) {
            $key = ($path[0..$i] -join '/')
            if (-not $emitted.ContainsKey($key)) {
                $script:TemplateItems.Add((New-SideItem ('fld:' + $key) 'Folder' $path[$i] '' (4 + $i * 12)))
                $emitted[$key] = $true
            }
        }
        $script:TemplateItems.Add((New-SideItem $t.Id 'Item' $t.Name $t.Icon (4 + $path.Count * 12)))
    }
    $ui.lbTemplates.ItemsSource = $script:TemplateItems
}

function Show-TablesPage {
    $scope = Get-ScopeInfo
    $ui.txtTablesScope.Text = $scope.Title
    $ui.glyphTablesScope.Text = Get-IconGlyph $scope.Icon
    $ui.glyphTablesScope.Foreground = Get-IconColor $scope.Icon
    $tpl = Get-ReportTemplate $script:State.TemplateId
    if (-not $tpl) {
        $ui.dgReport.Visibility = 'Collapsed'; $ui.pnlTablesEmpty.Visibility = 'Visible'; $ui.txtTablesRows.Text = ''
        return
    }
    $script:MainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        $dt = New-ReportTable $tpl @(Get-ScopeDevices)
        $script:ReportTable = $dt
        Set-TableFilter $dt $ui.txtTableSearch.Text
        Set-GridTable $ui.dgReport $dt
    } finally { $script:MainWindow.Cursor = $null }
    $ui.dgReport.Visibility = 'Visible'; $ui.pnlTablesEmpty.Visibility = 'Collapsed'
    Update-TablesRowCount
}

function Update-TablesRowCount {
    if ($script:ReportTable) { $ui.txtTablesRows.Text = 'Строк в отчете: ' + $script:ReportTable.DefaultView.Count }
}

function Initialize-TablesPage {
    Build-TemplateList
    Register-AutoColumns $ui.dgReport
    $ui.lbTemplates.Add_SelectionChanged({ Invoke-Safe {
        $it = $ui.lbTemplates.SelectedItem
        if (-not $it) { return }
        if ($it.Kind -ne 'Item') { $ui.lbTemplates.SelectedItem = $null; return }
        $script:State.TemplateId = $it.Id
        Show-TablesPage
    } })
    $ui.txtTableSearch.Add_TextChanged({ Set-Placeholder $ui.txtTableSearch $ui.phTableSearch; Invoke-Safe { Set-TableFilter $script:ReportTable $ui.txtTableSearch.Text; Update-TablesRowCount } })
    $ui.btnTableCopy.Add_Click({ Invoke-Safe {
        if (-not $script:ReportTable) { return }
        Show-DropMenu $ui.btnTableCopy @(
            (New-MenuItem 'Копировать как текст' { Invoke-Safe { [System.Windows.Clipboard]::SetText((ConvertTo-TabText (Convert-ViewToTable $script:ReportTable))) } } 'copy')
            (New-MenuItem 'Копировать как CSV' { Invoke-Safe { [System.Windows.Clipboard]::SetText((ConvertTo-CsvText (Convert-ViewToTable $script:ReportTable))) } } 'copy')
        )
    } })
    $ui.btnTableExport.Add_Click({ Invoke-Safe {
        $tpl = Get-ReportTemplate $script:State.TemplateId
        if (-not $tpl -or -not $script:ReportTable) { return }
        Export-Table $ui.btnTableExport { $script:ReportTable } ($tpl.Name + ' — ' + (Get-ScopeInfo).Title)
    } })
    $ui.dgReport.Add_MouseDoubleClick({ Invoke-Safe {
        $it = $ui.dgReport.SelectedItem
        if (-not $it) { return }
        $name = [string]$it.Row['c1']
        $d = $script:Store.Devices | Where-Object { [string]$_['Name'] -eq $name } | Select-Object -First 1
        if ($d) { Select-DeviceInTree $d['Id']; $ui.tabView.IsChecked = $true }
    } })
}
