# Main.Software.ps1 — вкладки «Учет ПО» и «Лицензии»

$script:TypeColors = @{ Free = '#2DB84D'; Commercial = '#2F7FD0'; Component = '#B5B5B5'; Unknown = '#DDDDDD' }

function Get-SoftwareSummaryCached {
    param([array]$Devices, [string]$ScopeKey)
    $key = $ScopeKey + '|' + $script:State.DataVersion + '|' + @($script:Store.Licenses).Count
    if ($script:SwCache.Key -eq $key) { return $script:SwCache.Summary }
    $script:MainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
    try { $sum = @(Get-SoftwareSummary $Devices) } finally { $script:MainWindow.Cursor = $null }
    $script:SwCache = @{ Key = $key; Summary = $sum }
    return $sum
}

function Get-ScopeKey {
    $n = $script:State.Node
    if (-not $n) { return 'ROOT' }
    return $n.Id
}

# ===========================================================================
#  Учет ПО
# ===========================================================================
function Build-SoftwareViews {
    $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[NetInv.SideItem]'
    $items.Add((New-SideItem 'hdr:std' 'Header' 'Стандартные'))
    $items.Add((New-SideItem 'list' 'Item' 'Список программ' 'software' 4))
    $items.Add((New-SideItem 'problems' 'Item' 'Программы с проблемами лицензирования' 'warning' 4))
    $items.Add((New-SideItem 'installs' 'Item' 'Установки программ' 'table' 4))
    $items.Add((New-SideItem 'computers' 'Item' 'Компьютеры с проблемами лицензирования' 'Desktop' 4))
    $items.Add((New-SideItem 'fld:keys' 'Folder' 'Лицензионные ключи' '' 4))
    $items.Add((New-SideItem 'keys' 'Item' 'Ключи продуктов' 'key' 16))
    $script:SwViewItems = $items
    $ui.lbSwViews.ItemsSource = $items
    $ui.lbSwViews.SelectedIndex = 1
    $ui.cbSwFilter.ItemsSource = @('Все типы ПО', 'Коммерческое', 'Бесплатное', 'Системные компоненты', 'Тип не определён')
    $ui.cbSwFilter.SelectedIndex = 0
}

function Test-SwProblem {
    param($Group)
    if ($Group.Type -eq 'Free' -or $Group.Type -eq 'Component') { return $false }
    return ($Group.License -like 'Превышено*' -or ($Group.Type -eq 'Commercial' -and $Group.License -eq 'Неизвестно'))
}

function Show-SoftwarePage {
    $devs = @(Get-ScopeDevices)
    $sum = @(Get-SoftwareSummaryCached $devs (Get-ScopeKey))
    $view = $script:State.SwView
    $q = $ui.txtSwSearch.Text.Trim()
    $typeFilter = @($null, 'Commercial', 'Free', 'Component', 'Unknown')[[math]::Max(0, $ui.cbSwFilter.SelectedIndex)]
    if ($view -eq 'list' -or $view -eq 'problems') {
        $rows = New-Object 'System.Collections.Generic.List[object]'
        foreach ($g in $sum) {
            if ($view -eq 'problems' -and -not (Test-SwProblem $g)) { continue }
            if ($typeFilter -and $g.Type -ne $typeFilter) { continue }
            if ($q -and -not ((Test-Match $g.Name $q) -or (Test-Match $g.Publisher $q) -or (Test-Match $g.Category $q))) { continue }
            $r = New-Object NetInv.SoftwareRow
            $r.Key = $g.Key; $r.Name = $g.Name; $r.Version = $g.VersionText; $r.Publisher = $g.Publisher
            $r.Category = $g.Category; $r.TypeText = Get-SoftwareTypeText $g.Type; $r.TypeColor = $script:TypeColors[$g.Type]
            $r.Copies = $g.Copies; $r.License = $g.License; $r.VersionCount = $g.VersionCount
            $r.Glyph = Get-IconGlyph 'software'; $r.GlyphColor = $(if ($g.Type -eq 'Component') { '#9AA3AD' } else { '#1F78C8' })
            $r.Tag = $g
            $rows.Add($r)
        }
        $ui.dgSoftware.ItemsSource = $rows
        $ui.dgSoftware.Visibility = 'Visible'; $ui.dgSwAlt.Visibility = 'Collapsed'
        $ui.txtSwVisible.Text = ('Видимые: {0} из {1}' -f $rows.Count, $sum.Count)
        Update-SoftwareSelection
        return
    }
    # альтернативные представления — таблицы
    switch ($view) {
        'installs' {
            $dt = New-SimpleTable @('ПО', 'Версия', 'Издатель', 'Компьютер', 'IP-адрес', 'Дата установки', 'Разрядность')
            foreach ($g in $sum) {
                if ($typeFilter -and $g.Type -ne $typeFilter) { continue }
                foreach ($i in $g.Installs) { Add-TableRow $dt @($i.DisplayName, $i.Version, $g.Publisher, $i.DeviceName, $i.Ip, (Format-DateOnly $i.InstallDate), $i.Arch) }
            }
        }
        'computers' {
            $dt = New-SimpleTable @('Компьютер', 'IP-адрес', 'Проблемных программ', 'Программы') @{ 'Проблемных программ' = [int] }
            $byDev = @{}
            foreach ($g in $sum) {
                if (-not (Test-SwProblem $g)) { continue }
                foreach ($i in $g.Installs) {
                    if (-not $byDev.ContainsKey($i.DeviceId)) { $byDev[$i.DeviceId] = @{ Name = $i.DeviceName; Ip = $i.Ip; List = New-Object System.Collections.ArrayList } }
                    if (-not $byDev[$i.DeviceId].List.Contains($g.Name)) { [void]$byDev[$i.DeviceId].List.Add($g.Name) }
                }
            }
            foreach ($k in $byDev.Keys) { $x = $byDev[$k]; Add-TableRow $dt @($x.Name, $x.Ip, $x.List.Count, (($x.List | Sort-Object) -join '; ')) }
        }
        'keys' {
            $dt = New-SimpleTable @('Продукт', 'Ключ', 'Источник', 'Компьютер', 'IP-адрес')
            foreach ($k in (Get-AllFoundKeys $devs)) { Add-TableRow $dt @($k.Product, $k.Key, $k.Source, $k.DeviceName, $k.Ip) }
        }
    }
    Set-TableFilter $dt $q
    Set-GridTable $ui.dgSwAlt $dt
    $script:SwAltTable = $dt
    $ui.dgSoftware.Visibility = 'Collapsed'; $ui.dgSwAlt.Visibility = 'Visible'
    $ui.txtSwVisible.Text = ('Видимые: {0} из {1}' -f $dt.DefaultView.Count, $dt.Rows.Count)
    $ui.pnlSwNoSelection.Visibility = 'Visible'
}

function Update-SoftwareSelection {
    $sel = @($ui.dgSoftware.SelectedItems)
    if ($sel.Count -eq 0 -or $ui.dgSoftware.Visibility -ne 'Visible') {
        $ui.pnlSwNoSelection.Visibility = 'Visible'
        return
    }
    $ui.pnlSwNoSelection.Visibility = 'Collapsed'
    $groups = @($sel | ForEach-Object { $_.Tag })
    if ($groups.Count -eq 1) {
        $ui.txtSwSelected.Text = $groups[0].Name
        $ui.txtSwSelectedPub.Text = $(if ($groups[0].Publisher) { 'от ' + $groups[0].Publisher } else { '' })
    } else {
        $ui.txtSwSelected.Text = ('Выбрано программ: {0}' -f $groups.Count)
        $ui.txtSwSelectedPub.Text = ''
    }
    $ui.glyphSwSelected.Text = Get-IconGlyph 'software'
    $ui.glyphSwSelected.Foreground = Get-IconColor 'software'
    # версии для фильтра
    $vers = @($groups | ForEach-Object { $_.Installs } | ForEach-Object { $_.Version } | Where-Object { $_ } | Sort-Object -Unique)
    $script:State.SuppressEvents = $true
    $prev = [string]$ui.cbInstallFilter.SelectedItem
    $ui.cbInstallFilter.ItemsSource = @('Все установки') + @($vers | ForEach-Object { 'Версия ' + $_ })
    if ($prev -and @($ui.cbInstallFilter.ItemsSource) -contains $prev) { $ui.cbInstallFilter.SelectedItem = $prev } else { $ui.cbInstallFilter.SelectedIndex = 0 }
    $script:State.SuppressEvents = $false
    Update-InstallsGrid
    # лицензирование
    $sb = New-Object System.Text.StringBuilder
    foreach ($g in $groups) {
        $lics = @(Get-LicensesForSoftware $g.Name)
        [void]$sb.AppendLine(('{0}: {1}' -f $g.Name, $g.License))
        foreach ($l in $lics) {
            $u = Get-LicenseUsage $l $script:SwCache.Summary
            [void]$sb.AppendLine(('    • {0} — мест: {1}, установлено: {2}, состояние: {3}' -f (Get-Val $l 'Name'), $u.Seats, $u.Installed, $u.Status))
        }
        if ($lics.Count -eq 0) { [void]$sb.AppendLine('    Лицензии не заданы.') }
    }
    $ui.txtSwLicensing.Text = $sb.ToString()
    $ui.txtSwInstallsCount.Text = [string](@($groups | ForEach-Object { $_.Installs }).Count)
}

function Update-InstallsGrid {
    $sel = @($ui.dgSoftware.SelectedItems)
    $dt = New-SimpleTable @('ПО', 'Компьютер', 'IP-адрес', 'Установлено', 'Добавлено в хранилище', 'Разрядность', 'Папка установки')
    $vf = [string]$ui.cbInstallFilter.SelectedItem
    foreach ($r in $sel) {
        foreach ($i in $r.Tag.Installs) {
            if ($vf -and $vf -ne 'Все установки' -and ('Версия ' + $i.Version) -ne $vf) { continue }
            Add-TableRow $dt @(('~ ' + $i.DisplayName), $i.DeviceName, $i.Ip, (Format-DateOnly $i.InstallDate), (Format-DateOnly $i.Added), $i.Arch, $i.Location)
        }
    }
    Set-TableFilter $dt $ui.txtInstallSearch.Text
    Set-GridTable $ui.dgInstalls $dt
    $script:InstallsTable = $dt
}

function Get-SoftwareExportTable {
    if ($ui.dgSwAlt.Visibility -eq 'Visible') { return $script:SwAltTable }
    $dt = New-SimpleTable @('Название', 'Версия', 'Издатель', 'Категория', 'Тип', 'Копии', 'Лицензирование') @{ 'Копии' = [int] }
    foreach ($r in @($ui.dgSoftware.ItemsSource)) { Add-TableRow $dt @($r.Name, $r.Version, $r.Publisher, $r.Category, $r.TypeText, $r.Copies, $r.License) }
    return ,$dt
}

function Initialize-SoftwarePage {
    Build-SoftwareViews
    Register-AutoColumns $ui.dgSwAlt
    Register-AutoColumns $ui.dgInstalls
    $ui.lbSwViews.Add_SelectionChanged({ Invoke-Safe {
        $it = $ui.lbSwViews.SelectedItem
        if (-not $it) { return }
        if ($it.Kind -ne 'Item') { $ui.lbSwViews.SelectedItem = $null; return }
        $script:State.SwView = $it.Id
        if ($script:State.Tab -eq 'software') { Show-SoftwarePage }
    } })
    $ui.cbSwFilter.Add_SelectionChanged({ Invoke-Safe { if ($script:State.Tab -eq 'software') { Show-SoftwarePage } } })
    $ui.txtSwSearch.Add_TextChanged({ Set-Placeholder $ui.txtSwSearch $ui.phSwSearch; Invoke-Safe { if ($script:State.Tab -eq 'software') { Show-SoftwarePage } } })
    $ui.dgSoftware.Add_SelectionChanged({ Invoke-Safe { Update-SoftwareSelection } })
    $ui.cbInstallFilter.Add_SelectionChanged({ Invoke-Safe { if (-not $script:State.SuppressEvents) { Update-InstallsGrid } } })
    $ui.txtInstallSearch.Add_TextChanged({ Set-Placeholder $ui.txtInstallSearch $ui.phInstallSearch; Invoke-Safe { Set-TableFilter $script:InstallsTable $ui.txtInstallSearch.Text } })
    $ui.tabSwInstalls.Add_Checked({ $ui.dgInstalls.Visibility = 'Visible'; $ui.pnlSwLicensing.Visibility = 'Collapsed' })
    $ui.tabSwLicensing.Add_Checked({ $ui.dgInstalls.Visibility = 'Collapsed'; $ui.pnlSwLicensing.Visibility = 'Visible' })
    $ui.btnSwCreateLicense.Add_Click({ Invoke-Safe {
        $sel = @($ui.dgSoftware.SelectedItems)
        $name = $(if ($sel.Count -gt 0) { $sel[0].Name } else { '' })
        $lic = Show-LicenseDialog $null $name
        if ($lic) { $script:Store.Licenses = @($script:Store.Licenses) + @($lic); Save-Licenses; Show-SoftwarePage }
    } })
    $ui.btnSwExport.Add_Click({ Invoke-Safe { Export-Table $ui.btnSwExport { Get-SoftwareExportTable } ('Учет ПО — ' + (Get-ScopeInfo).Title) } })
    $ui.dgInstalls.Add_MouseDoubleClick({ Invoke-Safe {
        $it = $ui.dgInstalls.SelectedItem
        if (-not $it) { return }
        $name = [string]$it.Row['c1']
        $d = $script:Store.Devices | Where-Object { [string]$_['Name'] -eq $name } | Select-Object -First 1
        if ($d) { Select-DeviceInTree $d['Id']; $script:State.CardCats = @('software'); $ui.tabView.IsChecked = $true }
    } })
}

# ===========================================================================
#  Лицензии
# ===========================================================================
function Build-LicenseViews {
    $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[NetInv.SideItem]'
    $items.Add((New-SideItem 'hdr:std' 'Header' 'Стандартные'))
    $items.Add((New-SideItem 'all' 'Item' 'Список лицензий' 'licenses' 4))
    $items.Add((New-SideItem 'over' 'Item' 'Лицензии с превышением' 'warning' 4))
    $items.Add((New-SideItem 'expired' 'Item' 'Истекшие лицензии' 'calendar' 4))
    $items.Add((New-SideItem 'unused' 'Item' 'Неиспользуемые лицензии' 'licenses' 4))
    $ui.lbLicViews.ItemsSource = $items
    $ui.lbLicViews.SelectedIndex = 1
}

function Show-LicensesPage {
    $allDevs = @($script:Store.Devices)
    $sum = @(Get-SoftwareSummaryCached $allDevs 'ROOT')
    $lics = @($script:Store.Licenses)
    # слева — фильтр по ПО
    $q = $ui.txtLicSearch.Text.Trim()
    $left = New-Object 'System.Collections.Generic.List[object]'
    $all = New-Object NetInv.ListItem
    $all.Id = '*'; $all.Name = 'Лицензии для всего ПО'; $all.Count = [string]$lics.Count; $all.Glyph = Get-IconGlyph 'licenses'; $all.GlyphColor = Get-IconColor 'licenses'
    $left.Add($all)
    foreach ($sw in ($lics | ForEach-Object { [string](Get-Val $_ 'Software') } | Sort-Object -Unique)) {
        if ($q -and -not (Test-Match $sw $q)) { continue }
        $li = New-Object NetInv.ListItem
        $li.Id = $sw; $li.Name = $sw; $li.Count = [string]@($lics | Where-Object { [string](Get-Val $_ 'Software') -eq $sw }).Count
        $li.Glyph = Get-IconGlyph 'software'; $li.GlyphColor = Get-IconColor 'software'
        $left.Add($li)
    }
    $prevSel = $(if ($ui.lbLicSoftware.SelectedItem) { $ui.lbLicSoftware.SelectedItem.Id } else { '*' })
    $script:State.SuppressEvents = $true
    $ui.lbLicSoftware.ItemsSource = $left
    $ui.lbLicSoftware.SelectedItem = ($left | Where-Object { $_.Id -eq $prevSel } | Select-Object -First 1)
    if (-not $ui.lbLicSoftware.SelectedItem) { $ui.lbLicSoftware.SelectedIndex = 0 }
    $script:State.SuppressEvents = $false
    $swFilter = $ui.lbLicSoftware.SelectedItem.Id

    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($l in $lics) {
        if ($swFilter -ne '*' -and [string](Get-Val $l 'Software') -ne $swFilter) { continue }
        $u = Get-LicenseUsage $l $sum
        switch ($script:State.LicView) {
            'over'    { if ($u.Status -ne 'Превышено') { continue } }
            'expired' { if ($u.Status -ne 'Истекла') { continue } }
            'unused'  { if ($u.Status -ne 'Не используется') { continue } }
        }
        $r = New-Object NetInv.LicenseRow
        $r.Id = [string](Get-Val $l 'Id'); $r.Name = [string](Get-Val $l 'Name'); $r.Software = [string](Get-Val $l 'Software')
        $r.Price = [string](Get-Val $l 'Price'); $r.Installed = $u.Installed; $r.Seats = $u.Seats; $r.Status = $u.Status
        $r.StatusColor = switch ($u.Status) { 'В норме' { '#2E9E3E' } 'Превышено' { '#D9302C' } 'Истекла' { '#D9302C' } default { '#888888' } }
        $r.Tag = $l
        $rows.Add($r)
    }
    $ui.dgLicenses.ItemsSource = $rows
    $ui.pnlNoLicenses.Visibility = $(if ($lics.Count -eq 0) { 'Visible' } else { 'Collapsed' })
    $ui.txtLicVisible.Text = ('Видимые: {0} из {1}' -f $rows.Count, $lics.Count)
    Show-UnboundKeys
}

function Show-UnboundKeys {
    $keys = @(Get-UnboundKeys @($script:Store.Devices))
    $ui.txtUnboundStrip.Text = 'Непривязанные ключи: ' + $keys.Count
    $prods = New-Object 'System.Collections.Generic.List[object]'
    $all = New-Object NetInv.ListItem
    $all.Id = '*'; $all.Name = 'Все ключи'; $all.Count = [string]$keys.Count; $all.Glyph = Get-IconGlyph 'key'; $all.GlyphColor = Get-IconColor 'key'
    $prods.Add($all)
    foreach ($g in ($keys | Group-Object { $_.Product } | Sort-Object Name)) {
        $li = New-Object NetInv.ListItem
        $li.Id = $g.Name; $li.Name = $g.Name; $li.Count = [string]$g.Count; $li.Glyph = Get-IconGlyph 'os'; $li.GlyphColor = Get-IconColor 'os'
        $prods.Add($li)
    }
    $prev = $(if ($ui.lbKeyProducts.SelectedItem) { $ui.lbKeyProducts.SelectedItem.Id } else { '*' })
    $script:State.SuppressEvents = $true
    $ui.lbKeyProducts.ItemsSource = $prods
    $ui.lbKeyProducts.SelectedItem = ($prods | Where-Object { $_.Id -eq $prev } | Select-Object -First 1)
    if (-not $ui.lbKeyProducts.SelectedItem) { $ui.lbKeyProducts.SelectedIndex = 0 }
    $script:State.SuppressEvents = $false
    $pf = $ui.lbKeyProducts.SelectedItem.Id
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($k in $keys) {
        if ($pf -ne '*' -and $k.Product -ne $pf) { continue }
        $r = New-Object NetInv.KeyRow
        $r.Key = $k.Key; $r.Product = $k.Product; $r.DeviceName = $k.DeviceName; $r.DeviceId = $k.DeviceId; $r.Ip = $k.Ip; $r.Source = $k.Source
        $rows.Add($r)
    }
    $ui.dgKeys.ItemsSource = $rows
}

function Edit-License {
    param($License)
    $new = Show-LicenseDialog $License
    if (-not $new) { return }
    $list = @()
    foreach ($l in $script:Store.Licenses) { if ((Get-Val $l 'Id') -eq (Get-Val $new 'Id')) { $list += $new } else { $list += $l } }
    $script:Store.Licenses = $list
    Save-Licenses
    Show-LicensesPage
}

function Bind-KeyToLicense {
    param($KeyRow)
    $lics = @($script:Store.Licenses)
    $names = @('Создать новую лицензию...') + @($lics | ForEach-Object { '{0}  ({1})' -f (Get-Val $_ 'Name'), (Get-Val $_ 'Software') })
    $i = Show-ChoiceDialog 'Привязать ключ' ('Ключ {0} ({1}, {2}). Выберите лицензию:' -f $KeyRow.Key, $KeyRow.Product, $KeyRow.DeviceName) $names
    if ($i -lt 0) { return }
    if ($i -eq 0) {
        $prod = $KeyRow.Product -replace '\s*\(OEM\)$', ''
        $lic = Show-LicenseDialog $null $prod
        if (-not $lic) { return }
        $lic['LicenseKeys'] = @(@(As-Array $lic['LicenseKeys']) + @($KeyRow.Key) | Sort-Object -Unique)
        $script:Store.Licenses = @($lics) + @($lic)
    } else {
        $l = $lics[$i - 1]
        $l['LicenseKeys'] = @(@(As-Array $l['LicenseKeys']) + @($KeyRow.Key) | Sort-Object -Unique)
    }
    Save-Licenses
    Show-LicensesPage
}

function Get-LicensesExportTable {
    $dt = New-SimpleTable @('Имя лицензии', 'Программы', 'Цена', 'Мест', 'Установлено', 'Статус', 'Действует до', 'Поставщик') @{ 'Мест' = [int]; 'Установлено' = [int] }
    foreach ($r in @($ui.dgLicenses.ItemsSource)) {
        Add-TableRow $dt @($r.Name, $r.Software, $r.Price, $r.Seats, $r.Installed, $r.Status, (Get-Val $r.Tag 'Expires'), (Get-Val $r.Tag 'Vendor'))
    }
    return ,$dt
}

function Initialize-LicensesPage {
    Build-LicenseViews
    $ui.lbLicViews.Add_SelectionChanged({ Invoke-Safe {
        $it = $ui.lbLicViews.SelectedItem
        if (-not $it) { return }
        if ($it.Kind -ne 'Item') { $ui.lbLicViews.SelectedItem = $null; return }
        $script:State.LicView = $it.Id
        if ($script:State.Tab -eq 'licenses') { Show-LicensesPage }
    } })
    $ui.lbLicSoftware.Add_SelectionChanged({ Invoke-Safe { if (-not $script:State.SuppressEvents -and $script:State.Tab -eq 'licenses') { Show-LicensesPage } } })
    $ui.lbKeyProducts.Add_SelectionChanged({ Invoke-Safe { if (-not $script:State.SuppressEvents) { Show-UnboundKeys } } })
    $ui.txtLicSearch.Add_TextChanged({ Set-Placeholder $ui.txtLicSearch $ui.phLicSearch; Invoke-Safe { if ($script:State.Tab -eq 'licenses') { Show-LicensesPage } } })
    $ui.btnCreateLicense.Add_Click({ Invoke-Safe {
        $lic = Show-LicenseDialog
        if ($lic) { $script:Store.Licenses = @($script:Store.Licenses) + @($lic); Save-Licenses; Show-LicensesPage }
    } })
    $ui.dgLicenses.Add_MouseDoubleClick({ Invoke-Safe { $r = $ui.dgLicenses.SelectedItem; if ($r) { Edit-License $r.Tag } } })
    $ui.dgLicenses.Add_PreviewMouseRightButtonUp({ Invoke-Safe {
        $r = $ui.dgLicenses.SelectedItem
        if (-not $r) { return }
        $cm = New-Object System.Windows.Controls.ContextMenu
        [void]$cm.Items.Add((New-MenuItem 'Изменить...' { Invoke-Safe { Edit-License $ui.dgLicenses.SelectedItem.Tag } } 'special'))
        [void]$cm.Items.Add((New-MenuItem 'Удалить' { Invoke-Safe {
            $r = $ui.dgLicenses.SelectedItem
            if ($r -and (Confirm-Action ('Удалить лицензию «{0}»?' -f $r.Name))) {
                $script:Store.Licenses = @($script:Store.Licenses | Where-Object { (Get-Val $_ 'Id') -ne $r.Id })
                Save-Licenses; Show-LicensesPage
            }
        } } 'delete'))
        $cm.PlacementTarget = $ui.dgLicenses
        $cm.IsOpen = $true
    } })
    $ui.dgKeys.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($s, $e)
        Invoke-Safe { $b = $e.OriginalSource; if ([string]$b.Tag -eq 'bindkey' -and $b.DataContext) { Bind-KeyToLicense $b.DataContext } }
    })
    $ui.bdUnboundStrip.Add_MouseLeftButtonUp({ $ui.dgKeys.Focus() })
    $ui.btnLicExport.Add_Click({ Invoke-Safe { Export-Table $ui.btnLicExport { Get-LicensesExportTable } 'Лицензии' } })
}
