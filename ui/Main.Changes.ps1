# Main.Changes.ps1 — вкладка «Журнал изменений»

$script:ChangeCatItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[NetInv.SideItem]'
$script:ChangeRows = @()

function Build-ChangeCategoryList {
    $script:ChangeCatItems.Clear()
    $last = $null
    foreach ($c in $script:ChangeCategories) {
        if ($c.Group -ne $last) {
            $h = New-SideItem ('hdr:' + $c.Group) 'Header' $c.Group '' 0 $c.Group
            $h.IsChecked = $false
            $script:ChangeCatItems.Add($h)
            $last = $c.Group
        }
        $it = New-SideItem $c.Id 'Item' $c.Name $c.Icon 0 $c.Group
        $it.IsChecked = $false
        $script:ChangeCatItems.Add($it)
    }
    $ui.lbChangeCats.ItemsSource = $script:ChangeCatItems
}

function Get-CheckedChangeCats {
    return @($script:ChangeCatItems | Where-Object { $_.Kind -eq 'Item' -and $_.IsChecked -eq $true } | ForEach-Object { $_.Id })
}

function Update-ChangeHeaders {
    foreach ($h in @($script:ChangeCatItems | Where-Object { $_.Kind -eq 'Header' })) {
        $kids = @($script:ChangeCatItems | Where-Object { $_.Kind -eq 'Item' -and $_.Tag -eq $h.Tag })
        $on = @($kids | Where-Object { $_.IsChecked -eq $true }).Count
        if ($on -eq 0) { $h.IsChecked = $false } elseif ($on -eq $kids.Count) { $h.IsChecked = $true } else { $h.IsChecked = $null }
    }
}

function Show-ChangesPage {
    param([switch]$Force)
    $devs = @(Get-ScopeDevices)
    $n = $script:State.Node
    if ($n -and $n.Kind -eq 'Device') {
        $ui.txtChangesScope.Text = [string]$n.Tag['Name']
        $ic = Get-DeviceIconName $n.Tag
    } else {
        $ui.txtChangesScope.Text = 'Выбрано устройств: ' + $devs.Count
        $ic = 'folder'
        if (-not $n -or $n.Kind -eq 'Root') { $ic = 'root' }
    }
    $ui.glyphChangesScope.Text = Get-IconGlyph $ic
    $ui.glyphChangesScope.Foreground = Get-IconColor $ic
    $cats = @(Get-CheckedChangeCats)
    if ($cats.Count -eq 0) {
        $ui.dgChanges.Visibility = 'Collapsed'
        $ui.bdChangesRefresh.Visibility = 'Collapsed'
        $ui.pnlChangesEmpty.Visibility = 'Visible'
        $ui.txtChangesEmptyTitle.Text = 'Не выбрана ни одна категория'
        $ui.txtChangesEmptyText.Text = 'Выберите одну или несколько категорий на боковой панели для обнаружения изменений.'
        foreach ($it in $script:ChangeCatItems) { $it.Count = ''; $it.Visible = $true }
        return
    }
    if (-not $Force -and $devs.Count -gt 25) {
        $ui.bdChangesRefresh.Visibility = 'Visible'
        return
    }
    $ui.bdChangesRefresh.Visibility = 'Collapsed'
    $from = $(if ($ui.dpFrom.SelectedDate) { ([datetime]$ui.dpFrom.SelectedDate).Date } else { [datetime]::MinValue })
    $to = $(if ($ui.dpTo.SelectedDate) { ([datetime]$ui.dpTo.SelectedDate).Date.AddDays(1).AddSeconds(-1) } else { [datetime]::MaxValue })
    $script:MainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
    try { $res = Get-DeviceChanges $devs $from $to $cats } finally { $script:MainWindow.Cursor = $null }
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($c in $res.Rows) {
        $r = New-Object NetInv.ChangeRow
        $r.DateSort = $c.Date
        $r.DateText = Format-DateTimeRu $c.Date
        $r.Device = $c.Device; $r.DeviceId = $c.DeviceId; $r.Ip = $c.Ip
        $r.Category = $c.Category
        $cat = $script:ChangeCategories | Where-Object { $_.Id -eq $c.CategoryId } | Select-Object -First 1
        $r.Glyph = Get-IconGlyph $cat.Icon; $r.GlyphColor = Get-IconColor $cat.Icon
        $r.Change = $c.Change
        switch ($c.Change) {
            'Добавлено' { $r.ChangeGlyph = '+'; $r.ChangeColor = '#2E9E3E' }
            'Удалено'   { $r.ChangeGlyph = [string][char]0x2212; $r.ChangeColor = '#D9302C' }
            default     { $r.ChangeGlyph = '~'; $r.ChangeColor = '#E08A00' }
        }
        $r.Item = $c.Item; $r.Old = $c.Old; $r.New = $c.New
        $rows.Add($r)
    }
    $script:ChangeRows = @($rows | Sort-Object DateSort -Descending)
    foreach ($it in $script:ChangeCatItems) {
        if ($it.Kind -ne 'Item') { continue }
        if ($it.IsChecked -eq $true) { $it.Count = [string]$res.Counts[$it.Id] } else { $it.Count = '' }
    }
    Apply-ChangesFilter
    if ($rows.Count -eq 0) {
        $ui.dgChanges.Visibility = 'Collapsed'
        $ui.pnlChangesEmpty.Visibility = 'Visible'
        $ui.txtChangesEmptyTitle.Text = 'Изменения не найдены для выбранных устройств'
        $ui.txtChangesEmptyText.Text = $(if ($res.DevicesWithHistory -eq 0) { 'Для обнаружения изменений требуется как минимум два снимка одного устройства.' } else { 'За выбранный период изменений в отмеченных категориях нет.' })
    } else {
        $ui.dgChanges.Visibility = 'Visible'
        $ui.pnlChangesEmpty.Visibility = 'Collapsed'
    }
}

function Apply-ChangesFilter {
    $q = $ui.txtChangesSearch.Text.Trim()
    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($r in $script:ChangeRows) {
        if ($q -and -not ((Test-Match $r.Device $q) -or (Test-Match $r.Item $q) -or (Test-Match $r.Category $q) -or (Test-Match $r.Old $q) -or (Test-Match $r.New $q))) { continue }
        $list.Add($r)
    }
    $ui.dgChanges.ItemsSource = $list
    # «Только с изменениями» — скрываем отмеченные категории без изменений
    $only = [bool]$ui.chkChangesOnlyChanged.IsChecked
    foreach ($it in $script:ChangeCatItems) { if ($it.Kind -eq 'Item') { $it.Visible = -not ($only -and $it.IsChecked -eq $true -and $it.Count -eq '0') } }
}

function Get-ChangesExportTable {
    $dt = New-SimpleTable @('Дата', 'Устройство', 'IP-адрес', 'Категория', 'Изменение', 'Элемент', 'Было', 'Стало')
    foreach ($r in @($ui.dgChanges.ItemsSource)) { Add-TableRow $dt @($r.DateText, $r.Device, $r.Ip, $r.Category, $r.Change, $r.Item, $r.Old, $r.New) }
    return ,$dt
}

function Initialize-ChangesPage {
    Build-ChangeCategoryList
    $ui.dpFrom.SelectedDate = (Get-Date).Date.AddMonths(-1)
    $ui.dpTo.SelectedDate = (Get-Date).Date
    $ui.lbChangeCats.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($s, $e)
        Invoke-Safe {
            $cb = $e.OriginalSource
            if (-not ($cb -is [System.Windows.Controls.CheckBox])) { return }
            $it = $cb.Tag
            if (-not $it) { return }
            if ($it.Kind -eq 'Header') {
                $v = ($it.IsChecked -eq $true)
                foreach ($x in $script:ChangeCatItems) { if ($x.Kind -eq 'Item' -and $x.Tag -eq $it.Tag) { $x.IsChecked = $v } }
            }
            Update-ChangeHeaders
            Show-ChangesPage
        }
    })
    $ui.lbChangeCats.Add_SelectionChanged({ $ui.lbChangeCats.SelectedItem = $null })
    $ui.dpFrom.Add_SelectedDateChanged({ Invoke-Safe { if ($script:State.Tab -eq 'changes') { Show-ChangesPage } } })
    $ui.dpTo.Add_SelectedDateChanged({ Invoke-Safe { if ($script:State.Tab -eq 'changes') { Show-ChangesPage } } })
    $ui.bdChangesRefresh.Add_MouseLeftButtonUp({ Invoke-Safe { Show-ChangesPage -Force } })
    $ui.chkChangesOnlyChanged.Add_Click({ Invoke-Safe { Apply-ChangesFilter } })
    $ui.txtChangesSearch.Add_TextChanged({ Set-Placeholder $ui.txtChangesSearch $ui.phChangesSearch; Invoke-Safe { Apply-ChangesFilter } })
    $ui.btnChangesExport.Add_Click({ Invoke-Safe { Export-Table $ui.btnChangesExport { Get-ChangesExportTable } ('Журнал изменений — ' + (Get-ScopeInfo).Title) } })
    $ui.dgChanges.Add_MouseDoubleClick({ Invoke-Safe {
        $r = $ui.dgChanges.SelectedItem
        if ($r) { Select-DeviceInTree $r.DeviceId }
    } })
}
