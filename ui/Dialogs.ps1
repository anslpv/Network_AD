# Dialogs.ps1 — загрузка XAML, сообщения, диалоги ввода, настройки, логины, лицензии

$script:UiDir = $PSScriptRoot

function Import-Xaml {
    param([string]$Path, [string]$Text)
    if ($Path) { $Text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }
    $obj = [System.Windows.Markup.XamlReader]::Parse($Text)
    $ctl = @{}
    foreach ($m in [regex]::Matches($Text, 'x:Name="([^"]+)"')) {
        $n = $m.Groups[1].Value
        if ($ctl.ContainsKey($n)) { continue }
        try { $o = $obj.FindName($n); if ($o) { $ctl[$n] = $o } } catch { }
    }
    return @{ Root = $obj; C = $ctl }
}

function Invoke-Safe {
    param([scriptblock]$Action)
    try { & $Action }
    catch {
        $msg = $_.Exception.Message
        if ($_.InvocationInfo) { $msg += "`n`n" + $_.InvocationInfo.PositionMessage }
        try { Write-AppLog ('ERROR: ' + $msg) } catch { }
        [System.Windows.MessageBox]::Show($msg, $script:AppName, 'OK', 'Error') | Out-Null
    }
}

function Write-AppLog {
    param([string]$Text)
    try {
        $p = Join-Path $script:AppDataDir 'app.log'
        if (-not (Test-Path -LiteralPath $script:AppDataDir)) { [void](New-Item -ItemType Directory -Path $script:AppDataDir -Force) }
        Add-Content -LiteralPath $p -Value ('{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Text) -Encoding UTF8
    } catch { }
}

function Show-MsgBox {
    param([string]$Text, [string]$Title, [string]$Buttons, [string]$Icon)
    if ($script:MainWindow -and $script:MainWindow.IsVisible) {
        return [System.Windows.MessageBox]::Show($script:MainWindow, $Text, $Title, $Buttons, $Icon)
    }
    return [System.Windows.MessageBox]::Show($Text, $Title, $Buttons, $Icon)
}
function Show-Info { param([string]$Text, [string]$Title = $script:AppName) Show-MsgBox $Text $Title 'OK' 'Information' | Out-Null }
function Show-Warning { param([string]$Text, [string]$Title = $script:AppName) Show-MsgBox $Text $Title 'OK' 'Warning' | Out-Null }
function Confirm-Action {
    param([string]$Text, [string]$Title = $script:AppName)
    return ((Show-MsgBox $Text $Title 'YesNo' 'Question') -eq 'Yes')
}

function New-DialogWindow {
    param([string]$Xaml)
    $d = Import-Xaml -Text $Xaml
    if ($script:MainWindow) { $d.Root.Owner = $script:MainWindow }
    return $d
}

function Show-InputBox {
    param([string]$Title, [string]$Prompt, [string]$Default = '')
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="380" SizeToContent="Height" WindowStartupLocation="CenterOwner" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Tahoma" FontSize="11" Background="White" TextOptions.TextFormattingMode="Display">
  <StackPanel Margin="14,12,14,12">
    <TextBlock x:Name="lbl" TextWrapping="Wrap" Margin="0,0,0,6"/>
    <TextBox x:Name="txt" Height="22"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="ok" Content="OK" Style="{StaticResource PrimaryButton}" IsDefault="True"/>
      <Button Content="Отмена" Style="{StaticResource DialogButton}" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
    $d = New-DialogWindow $x
    $d.Root.Title = $Title
    $d.C.lbl.Text = $Prompt
    $d.C.txt.Text = $Default
    $d.C.ok.Add_Click({ $d.Root.DialogResult = $true })
    $d.Root.Add_ContentRendered({ $d.C.txt.Focus(); $d.C.txt.SelectAll() })
    if ($d.Root.ShowDialog()) { return $d.C.txt.Text }
    return $null
}

function Show-ChoiceDialog {
    # Выбор элемента из списка. $Items — массив строк. Возвращает индекс или -1
    param([string]$Title, [string]$Prompt, [string[]]$Items)
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="400" Height="360" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        FontFamily="Tahoma" FontSize="11" Background="White" TextOptions.TextFormattingMode="Display">
  <DockPanel Margin="12">
    <TextBlock x:Name="lbl" DockPanel.Dock="Top" TextWrapping="Wrap" Margin="0,0,0,6"/>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="ok" Content="OK" Style="{StaticResource PrimaryButton}" IsDefault="True"/>
      <Button Content="Отмена" Style="{StaticResource DialogButton}" IsCancel="True"/>
    </StackPanel>
    <ListBox x:Name="lst" BorderBrush="#C9C9C9"/>
  </DockPanel>
</Window>
"@
    $d = New-DialogWindow $x
    $d.Root.Title = $Title
    $d.C.lbl.Text = $Prompt
    foreach ($i in $Items) { [void]$d.C.lst.Items.Add($i) }
    if ($Items.Count -gt 0) { $d.C.lst.SelectedIndex = 0 }
    $d.C.ok.Add_Click({ $d.Root.DialogResult = $true })
    $d.C.lst.Add_MouseDoubleClick({ if ($d.C.lst.SelectedIndex -ge 0) { $d.Root.DialogResult = $true } })
    if ($d.Root.ShowDialog()) { return $d.C.lst.SelectedIndex }
    return -1
}

function Show-CredentialDialog {
    # Добавление/изменение логина: возвращает @{ Name; User; Password(plain) } или $null
    param($Existing = $null)
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Логин Windows" Width="360" SizeToContent="Height" WindowStartupLocation="CenterOwner" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Tahoma" FontSize="11" Background="White" TextOptions.TextFormattingMode="Display">
  <Grid Margin="14,12,14,12">
    <Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="28"/><RowDefinition Height="28"/><RowDefinition Height="28"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Название" VerticalAlignment="Center"/>
    <TextBox x:Name="nm" Grid.Column="1" Height="22"/>
    <TextBlock Grid.Row="1" Text="Пользователь" VerticalAlignment="Center"/>
    <TextBox x:Name="us" Grid.Row="1" Grid.Column="1" Height="22"/>
    <TextBlock Grid.Row="2" Text="Пароль" VerticalAlignment="Center"/>
    <PasswordBox x:Name="pw" Grid.Row="2" Grid.Column="1" Height="22"/>
    <TextBlock Grid.Row="3" Grid.ColumnSpan="2" Foreground="#888" Margin="0,4,0,0" TextWrapping="Wrap" Text="Формат: ДОМЕН\пользователь или КОМПЬЮТЕР\пользователь. Оставьте пароль пустым, чтобы не менять его."/>
    <StackPanel Grid.Row="4" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="ok" Content="OK" Style="{StaticResource PrimaryButton}" IsDefault="True"/>
      <Button Content="Отмена" Style="{StaticResource DialogButton}" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $d = New-DialogWindow $x
    if ($Existing) { $d.C.nm.Text = [string](Get-Val $Existing 'Name'); $d.C.us.Text = [string](Get-Val $Existing 'User') }
    $d.C.ok.Add_Click({
        if ([string]::IsNullOrWhiteSpace($d.C.us.Text)) { Show-Warning 'Укажите имя пользователя.'; return }
        $d.Root.DialogResult = $true
    })
    $d.Root.Add_ContentRendered({ $d.C.nm.Focus() })
    if ($d.Root.ShowDialog()) {
        $name = $d.C.nm.Text.Trim(); if (-not $name) { $name = $d.C.us.Text.Trim() }
        return @{ Name = $name; User = $d.C.us.Text.Trim(); Password = $d.C.pw.Password }
    }
    return $null
}

function Show-AdConnectDialog {
    param([string]$DefaultDomain = '')
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Подключиться к домену" Width="380" SizeToContent="Height" WindowStartupLocation="CenterOwner" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Tahoma" FontSize="11" Background="White" TextOptions.TextFormattingMode="Display">
  <Grid Margin="14,12,14,12">
    <Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="28"/><RowDefinition Height="28"/><RowDefinition Height="28"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Домен" VerticalAlignment="Center"/>
    <TextBox x:Name="dm" Grid.Column="1" Height="22"/>
    <TextBlock Grid.Row="1" Text="Пользователь" VerticalAlignment="Center"/>
    <TextBox x:Name="us" Grid.Row="1" Grid.Column="1" Height="22"/>
    <TextBlock Grid.Row="2" Text="Пароль" VerticalAlignment="Center"/>
    <PasswordBox x:Name="pw" Grid.Row="2" Grid.Column="1" Height="22"/>
    <TextBlock Grid.Row="3" Grid.ColumnSpan="2" Foreground="#888" Margin="0,4,0,0" TextWrapping="Wrap" Text="Оставьте пользователя пустым, чтобы подключиться от имени текущего пользователя."/>
    <StackPanel Grid.Row="4" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="ok" Content="Подключиться" Style="{StaticResource PrimaryButton}" IsDefault="True"/>
      <Button Content="Отмена" Style="{StaticResource DialogButton}" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $d = New-DialogWindow $x
    $d.C.dm.Text = $DefaultDomain
    $d.C.ok.Add_Click({ if ([string]::IsNullOrWhiteSpace($d.C.dm.Text)) { Show-Warning 'Укажите имя домена.'; return }; $d.Root.DialogResult = $true })
    if ($d.Root.ShowDialog()) {
        $cred = $null
        if ($d.C.us.Text.Trim()) {
            $sec = New-Object System.Security.SecureString
            foreach ($ch in $d.C.pw.Password.ToCharArray()) { $sec.AppendChar($ch) }
            $cred = New-Object System.Management.Automation.PSCredential($d.C.us.Text.Trim(), $sec)
        }
        return @{ Domain = $d.C.dm.Text.Trim(); Credential = $cred }
    }
    return $null
}

function Show-SpecialInfoDialog {
    param($Device)
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Специальная информация" Width="420" SizeToContent="Height" WindowStartupLocation="CenterOwner" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Tahoma" FontSize="11" Background="White" TextOptions.TextFormattingMode="Display">
  <Grid Margin="14,12,14,12">
    <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="28"/><RowDefinition Height="28"/><RowDefinition Height="28"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Имя устройства" VerticalAlignment="Center"/>
    <TextBox x:Name="nm" Grid.Column="1" Height="22"/>
    <TextBlock Grid.Row="1" Text="Закрепленный пользователь" VerticalAlignment="Center"/>
    <TextBox x:Name="au" Grid.Row="1" Grid.Column="1" Height="22"/>
    <TextBlock Grid.Row="2" Text="Расположение" VerticalAlignment="Center"/>
    <TextBox x:Name="lc" Grid.Row="2" Grid.Column="1" Height="22"/>
    <StackPanel Grid.Row="3" Grid.ColumnSpan="2" Margin="0,6,0,0">
      <TextBlock Text="Записка"/>
      <TextBox x:Name="nt" Height="80" AcceptsReturn="True" TextWrapping="Wrap" VerticalContentAlignment="Top" Margin="0,4,0,0"/>
    </StackPanel>
    <StackPanel Grid.Row="4" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="ok" Content="OK" Style="{StaticResource PrimaryButton}" IsDefault="True"/>
      <Button Content="Отмена" Style="{StaticResource DialogButton}" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $d = New-DialogWindow $x
    $d.C.nm.Text = [string]$Device['Name']
    $d.C.au.Text = [string]$Device['AssignedUser']
    $d.C.lc.Text = [string]$Device['Location']
    $d.C.nt.Text = [string]$Device['Note']
    $d.C.ok.Add_Click({ $d.Root.DialogResult = $true })
    if ($d.Root.ShowDialog()) {
        return @{ Name = $d.C.nm.Text.Trim(); AssignedUser = $d.C.au.Text.Trim(); Location = $d.C.lc.Text.Trim(); Note = $d.C.nt.Text }
    }
    return $null
}

function Show-LicenseDialog {
    # Создание/изменение лицензии. Возвращает hashtable лицензии или $null
    param($License = $null, [string]$DefaultSoftware = '')
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Лицензия" Width="460" SizeToContent="Height" WindowStartupLocation="CenterOwner" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Tahoma" FontSize="11" Background="White" TextOptions.TextFormattingMode="Display">
  <StackPanel>
    <Border Background="#DCEBFA" Padding="10,6">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="&#xE8D7;" FontFamily="Segoe MDL2 Assets" Foreground="#D4A017" FontSize="18" Margin="0,0,10,0" VerticalAlignment="Center"/>
        <TextBlock x:Name="hdr" Text="Новая лицензия" FontWeight="Bold" Foreground="#2F7FD0" VerticalAlignment="Center"/>
      </StackPanel>
    </Border>
    <Grid Margin="14,10,14,6">
      <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Grid.RowDefinitions><RowDefinition Height="28"/><RowDefinition Height="Auto"/><RowDefinition Height="28"/><RowDefinition Height="28"/><RowDefinition Height="28"/><RowDefinition Height="28"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <TextBlock Text="Имя лицензии" VerticalAlignment="Center"/>
      <TextBox x:Name="nm" Grid.Column="1" Height="22"/>
      <TextBlock Grid.Row="1" Text="Программы" VerticalAlignment="Top" Margin="0,5,0,0"/>
      <StackPanel Grid.Row="1" Grid.Column="1">
        <TextBox x:Name="sw" Height="22"/>
        <TextBlock Foreground="#888" TextWrapping="Wrap" Margin="0,2,0,4" Text="Часть названия или шаблон (* ?). Несколько значений — через точку с запятой."/>
      </StackPanel>
      <TextBlock Grid.Row="2" Text="Количество мест" VerticalAlignment="Center"/>
      <TextBox x:Name="st" Grid.Row="2" Grid.Column="1" Height="22" Width="80" HorizontalAlignment="Left"/>
      <TextBlock Grid.Row="3" Text="Цена" VerticalAlignment="Center"/>
      <TextBox x:Name="pr" Grid.Row="3" Grid.Column="1" Height="22" Width="120" HorizontalAlignment="Left"/>
      <TextBlock Grid.Row="4" Text="Поставщик" VerticalAlignment="Center"/>
      <TextBox x:Name="vd" Grid.Row="4" Grid.Column="1" Height="22"/>
      <TextBlock Grid.Row="5" Text="Действует до" VerticalAlignment="Center"/>
      <DatePicker x:Name="ex" Grid.Row="5" Grid.Column="1" Width="140" HorizontalAlignment="Left"/>
      <TextBlock Grid.Row="6" Text="Ключи" VerticalAlignment="Top" Margin="0,5,0,0"/>
      <TextBox x:Name="ky" Grid.Row="6" Grid.Column="1" Height="60" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top" Margin="0,3,0,3"/>
      <TextBlock Grid.Row="7" Text="Примечание" VerticalAlignment="Top" Margin="0,5,0,0"/>
      <TextBox x:Name="nt" Grid.Row="7" Grid.Column="1" Height="46" AcceptsReturn="True" TextWrapping="Wrap" VerticalContentAlignment="Top" Margin="0,3,0,3"/>
    </Grid>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,4,14,12">
      <Button x:Name="ok" Content="OK" Style="{StaticResource PrimaryButton}" IsDefault="True"/>
      <Button Content="Отмена" Style="{StaticResource DialogButton}" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
    $d = New-DialogWindow $x
    if ($License) {
        $d.C.hdr.Text = 'Изменение лицензии'
        $d.C.nm.Text = [string](Get-Val $License 'Name')
        $d.C.sw.Text = [string](Get-Val $License 'Software')
        $d.C.st.Text = [string](Get-Val $License 'Seats')
        $d.C.pr.Text = [string](Get-Val $License 'Price')
        $d.C.vd.Text = [string](Get-Val $License 'Vendor')
        $exp = ConvertTo-DateTime (Get-Val $License 'Expires')
        if ($exp) { $d.C.ex.SelectedDate = $exp }
        $d.C.ky.Text = ((As-Array (Get-Val $License 'LicenseKeys')) -join "`r`n")
        $d.C.nt.Text = [string](Get-Val $License 'Note')
    } else {
        $d.C.sw.Text = $DefaultSoftware
        $d.C.nm.Text = $DefaultSoftware
        $d.C.st.Text = '1'
    }
    $d.C.ok.Add_Click({
        $n = 0
        if ([string]::IsNullOrWhiteSpace($d.C.nm.Text)) { Show-Warning 'Укажите имя лицензии.'; return }
        if ([string]::IsNullOrWhiteSpace($d.C.sw.Text)) { Show-Warning 'Укажите, к каким программам относится лицензия.'; return }
        if (-not [int]::TryParse($d.C.st.Text.Trim(), [ref]$n) -or $n -lt 0) { Show-Warning 'Количество мест должно быть целым числом.'; return }
        $d.Root.DialogResult = $true
    })
    $d.Root.Add_ContentRendered({ $d.C.nm.Focus() })
    if (-not $d.Root.ShowDialog()) { return $null }
    $lic = @{}
    if ($License) { foreach ($k in @($License.PSBase.Keys)) { $lic[$k] = $License[$k] } } else { $lic['Id'] = New-Id; $lic['Created'] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') }
    $lic['Name'] = $d.C.nm.Text.Trim()
    $lic['Software'] = $d.C.sw.Text.Trim()
    $lic['Seats'] = [int]$d.C.st.Text.Trim()
    $lic['Price'] = $d.C.pr.Text.Trim()
    $lic['Vendor'] = $d.C.vd.Text.Trim()
    $lic['Expires'] = $(if ($d.C.ex.SelectedDate) { ([datetime]$d.C.ex.SelectedDate).ToString('yyyy-MM-dd') } else { '' })
    $lic['LicenseKeys'] = @($d.C.ky.Text -split "[\r\n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $lic['Note'] = $d.C.nt.Text
    return $lic
}

# ---------------------------------------------------------------------------
#  Настройки
# ---------------------------------------------------------------------------
function Initialize-NumericBox {
    param($Ctl, [string]$Name, [int]$Min, [int]$Max, [int]$Step, [int]$Value)
    $box = $Ctl[$Name]
    $box.Text = [string]$Value
    $box.Tag = @{ Min = $Min; Max = $Max; Step = $Step }
    $dec = $Ctl[$Name + 'Dec']; $inc = $Ctl[$Name + 'Inc']
    $dec.Tag = $box; $inc.Tag = $box
    $dec.Add_Click({ param($s, $e) $b = $s.Tag; $t = $b.Tag; $v = 0; [void][int]::TryParse($b.Text, [ref]$v); $v = [math]::Max($t.Min, $v - $t.Step); $b.Text = [string]$v })
    $inc.Add_Click({ param($s, $e) $b = $s.Tag; $t = $b.Tag; $v = 0; [void][int]::TryParse($b.Text, [ref]$v); $v = [math]::Min($t.Max, $v + $t.Step); $b.Text = [string]$v })
}

function Get-NumericBox {
    param($Box)
    $t = $Box.Tag; $v = 0
    if (-not [int]::TryParse($Box.Text.Trim(), [ref]$v)) { $v = $t.Min }
    return [int][math]::Min($t.Max, [math]::Max($t.Min, $v))
}

function Show-SettingsDialog {
    # Возвращает $true, если настройки изменены
    param([string]$Page = 'general')
    $d = Import-Xaml -Path (Join-Path $script:UiDir 'SettingsDialog.xaml')
    $w = $d.Root; $c = $d.C
    if ($script:MainWindow) { $w.Owner = $script:MainWindow }
    $s = $script:Settings
    $g = $s.General; $sc = $s.Scanner; $rp = $s.Reports; $al = $s.Alerts

    $pages = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($p in @(@('general', 'Общие', 'settings'), @('scanner', 'Сканер', 'scan'), @('reports', 'Отчеты', 'template'), @('alerts', 'Сигналы', 'alerts'))) {
        $it = New-Object NetInv.SideItem
        $it.Id = $p[0]; $it.Kind = 'Item'; $it.Name = $p[1]; $it.Glyph = Get-IconGlyph $p[2]; $it.GlyphColor = Get-IconColor $p[2]
        $pages.Add($it)
    }
    $c.lbPages.ItemsSource = $pages
    $pageMap = @{ general = $c.pageGeneral; scanner = $c.pageScanner; reports = $c.pageReports; alerts = $c.pageAlerts }
    $c.lbPages.Add_SelectionChanged({
        $sel = $c.lbPages.SelectedItem
        if (-not $sel) { return }
        foreach ($k in $pageMap.Keys) { $pageMap[$k].Visibility = $(if ($k -eq $sel.Id) { 'Visible' } else { 'Collapsed' }) }
    })
    $c.txtFind.Add_TextChanged({
        $c.phFind.Visibility = $(if ($c.txtFind.Text) { 'Collapsed' } else { 'Visible' })
        $q = $c.txtFind.Text.Trim()
        if (-not $q) { return }
        $hits = @{ general = 'язык неделя дата формат хранилище папка'; scanner = 'сканер пропускать обнаружение пинг arp порт тайм-аут rpc dcom обновлен поток'; reports = 'отчет пустые запрещенное'; alerts = 'сигнал диск память антивирус брандмауэр устройств' }
        foreach ($k in $hits.Keys) { if ($hits[$k] -match [regex]::Escape($q.ToLowerInvariant())) { foreach ($it in $pages) { if ($it.Id -eq $k) { $c.lbPages.SelectedItem = $it } }; break } }
    })

    # --- Общие
    $c.cbFirstDay.SelectedIndex = [int]$g.FirstDayOfWeek
    $c.chkRelativeDates.IsChecked = [bool]$g.RelativeDates
    $c.chkCustomDate.IsChecked = [bool]$g.CustomDateFormat
    $c.txtDateFormat.Text = [string]$g.DateFormat
    $updPreview = {
        $c.txtDateFormat.IsEnabled = [bool]$c.chkCustomDate.IsChecked
        try { $c.txtDatePreview.Text = 'Сегодня ' + (Get-Date).ToString($c.txtDateFormat.Text, [Globalization.CultureInfo]'ru-RU') } catch { $c.txtDatePreview.Text = 'Неверный формат' }
    }
    $c.chkCustomDate.Add_Click($updPreview)
    $c.txtDateFormat.Add_TextChanged($updPreview)
    & $updPreview
    $c.txtStoragePath.Text = [string]$s.StoragePath
    $c.btnBrowseStorage.Add_Click({
        $p = Select-FolderPath 'Выберите папку хранилища' $c.txtStoragePath.Text
        if ($p) { $c.txtStoragePath.Text = $p }
    })

    # --- Сканер
    $c.chkSkipExisting.IsChecked = [bool]$sc.SkipExisting
    Initialize-NumericBox $c 'numSkipHours' 0 720 1 ([int]$sc.SkipExistingHours)
    Initialize-NumericBox $c 'numThreads' 1 64 1 ([int]$sc.Threads)
    $c.chkDiscovery.IsChecked = [bool]$sc.UseDiscovery
    Initialize-NumericBox $c 'numAttempts' 1 10 1 ([int]$sc.PingAttempts)
    Initialize-NumericBox $c 'numPingTimeout' 100 10000 100 ([int]$sc.PingTimeout)
    switch ([string]$sc.DiscoveryProfile) { 'Fast' { $c.rbFast.IsChecked = $true } 'Slow' { $c.rbSlow.IsChecked = $true } default { $c.rbNormal.IsChecked = $true } }
    $c.chkArp.IsChecked = [bool]$sc.UseArpPing
    if ([string]$sc.PortProfile -eq 'Safe') { $c.rbSafe.IsChecked = $true } else { $c.rbLight.IsChecked = $true }
    Initialize-NumericBox $c 'numPortTimeout' 100 10000 100 ([int]$sc.PortTimeout)
    $c.chkDisableDcom.IsChecked = [bool]$sc.DisableDcom
    $c.chkScanUpdates.IsChecked = [bool]$sc.ScanWindowsUpdates
    Initialize-NumericBox $c 'numUpdTimeout' 1 120 1 ([int]$sc.UpdatesTimeoutMin)
    $updDisc = { $c.pnlDiscovery.IsEnabled = [bool]$c.chkDiscovery.IsChecked }
    $c.chkDiscovery.Add_Click($updDisc); & $updDisc
    $updAdv = { $c.pnlThreads.Visibility = $(if ($c.chkAdvanced.IsChecked) { 'Visible' } else { 'Collapsed' }) }
    $c.chkAdvanced.Add_Click($updAdv); & $updAdv

    # --- Отчеты
    $c.chkShowEmpty.IsChecked = [bool]$rp.ShowEmptyValues
    $c.txtForbidden.Text = (([string]$rp.ForbiddenSoftware) -split '[;\r\n]+' | Where-Object { $_.Trim() }) -join "`r`n"

    # --- Сигналы
    Initialize-NumericBox $c 'numDiskFree' 1 90 1 ([int]$al.DiskFreePercent)
    Initialize-NumericBox $c 'numMinRam' 0 256 1 ([int]$al.MinRamGB)
    $c.chkAlertAv.IsChecked = [bool]$al.CheckAntivirus
    $c.chkAlertFw.IsChecked = [bool]$al.CheckFirewall
    $c.chkAlertDevices.IsChecked = [bool]$al.CheckProblemDevices

    $c.btnOk.Add_Click({ $w.DialogResult = $true })
    foreach ($it in $pages) { if ($it.Id -eq $Page) { $c.lbPages.SelectedItem = $it } }
    if (-not $c.lbPages.SelectedItem) { $c.lbPages.SelectedIndex = 0 }

    if (-not $w.ShowDialog()) { return $false }

    $g.FirstDayOfWeek = [int][math]::Max(0, $c.cbFirstDay.SelectedIndex)
    $g.RelativeDates = [bool]$c.chkRelativeDates.IsChecked
    $g.CustomDateFormat = [bool]$c.chkCustomDate.IsChecked
    $g.DateFormat = $c.txtDateFormat.Text
    $sc.SkipExisting = [bool]$c.chkSkipExisting.IsChecked
    $sc.SkipExistingHours = Get-NumericBox $c.numSkipHours
    $sc.Threads = Get-NumericBox $c.numThreads
    $sc.UseDiscovery = [bool]$c.chkDiscovery.IsChecked
    $sc.PingAttempts = Get-NumericBox $c.numAttempts
    $sc.PingTimeout = Get-NumericBox $c.numPingTimeout
    $sc.DiscoveryProfile = $(if ($c.rbFast.IsChecked) { 'Fast' } elseif ($c.rbSlow.IsChecked) { 'Slow' } else { 'Normal' })
    $sc.UseArpPing = [bool]$c.chkArp.IsChecked
    $sc.PortProfile = $(if ($c.rbSafe.IsChecked) { 'Safe' } else { 'Light' })
    $sc.PortTimeout = Get-NumericBox $c.numPortTimeout
    $sc.DisableDcom = [bool]$c.chkDisableDcom.IsChecked
    $sc.ScanWindowsUpdates = [bool]$c.chkScanUpdates.IsChecked
    $sc.UpdatesTimeoutMin = Get-NumericBox $c.numUpdTimeout
    $rp.ShowEmptyValues = [bool]$c.chkShowEmpty.IsChecked
    $rp.ForbiddenSoftware = (($c.txtForbidden.Text -split '[\r\n]+') | Where-Object { $_.Trim() }) -join ';'
    $al.DiskFreePercent = Get-NumericBox $c.numDiskFree
    $al.MinRamGB = Get-NumericBox $c.numMinRam
    $al.CheckAntivirus = [bool]$c.chkAlertAv.IsChecked
    $al.CheckFirewall = [bool]$c.chkAlertFw.IsChecked
    $al.CheckProblemDevices = [bool]$c.chkAlertDevices.IsChecked
    $newPath = $c.txtStoragePath.Text.Trim()
    $storageChanged = ($newPath -and $newPath -ne [string]$s.StoragePath)
    if ($storageChanged) { $s.StoragePath = $newPath }
    Save-Settings
    if ($storageChanged) { return 'storage' }
    return $true
}

# ---------------------------------------------------------------------------
#  Логины
# ---------------------------------------------------------------------------
function Show-LoginsDialog {
    $d = Import-Xaml -Path (Join-Path $script:UiDir 'LoginsDialog.xaml')
    $w = $d.Root; $c = $d.C
    if ($script:MainWindow) { $w.Owner = $script:MainWindow }
    $c.txtCurrentUser.Text = ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME)
    $list = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($l in (As-Array $script:Settings.Logins)) {
        $h = @{}; foreach ($k in @($l.PSBase.Keys)) { $h[$k] = $l[$k] }
        $list.Add([pscustomobject]@{ Name = [string]$h.Name; Data = $h })
    }
    $c.lbLogins.ItemsSource = $list
    $def = [string]$script:Settings.DefaultLogin
    if ($def -and $def -ne 'current') {
        $c.rbSpecify.IsChecked = $true
        foreach ($i in $list) { if ($i.Data.Id -eq $def) { $c.lbLogins.SelectedItem = $i } }
    } else { $c.rbCurrent.IsChecked = $true }
    $c.lbLogins.Add_SelectionChanged({ if ($c.lbLogins.SelectedItem) { $c.rbSpecify.IsChecked = $true } })
    $c.btnAddLogin.Add_Click({
        $r = Show-CredentialDialog
        if ($r) {
            $h = @{ Id = (New-Id); Name = $r.Name; User = $r.User; Password = (Protect-Password $r.Password) }
            $item = [pscustomobject]@{ Name = $h.Name; Data = $h }
            $list.Add($item); $c.lbLogins.SelectedItem = $item
        }
    })
    $c.btnEditLogin.Add_Click({
        $sel = $c.lbLogins.SelectedItem
        if (-not $sel) { return }
        $r = Show-CredentialDialog $sel.Data
        if ($r) {
            $sel.Data.Name = $r.Name; $sel.Data.User = $r.User
            if ($r.Password) { $sel.Data.Password = Protect-Password $r.Password }
            $idx = $list.IndexOf($sel)
            $new = [pscustomobject]@{ Name = $r.Name; Data = $sel.Data }
            $list[$idx] = $new; $c.lbLogins.SelectedItem = $new
        }
    })
    $c.btnDeleteLogin.Add_Click({
        $sel = $c.lbLogins.SelectedItem
        if ($sel -and (Confirm-Action ('Удалить логин «{0}»?' -f $sel.Name))) { [void]$list.Remove($sel) }
    })
    $c.btnOk.Add_Click({
        if ($c.rbSpecify.IsChecked -and -not $c.lbLogins.SelectedItem) { Show-Warning 'Выберите логин в списке или добавьте новый.'; return }
        $w.DialogResult = $true
    })
    if (-not $w.ShowDialog()) { return $false }
    $script:Settings.Logins = @($list | ForEach-Object { $_.Data })
    if ($c.rbSpecify.IsChecked -and $c.lbLogins.SelectedItem) { $script:Settings.DefaultLogin = $c.lbLogins.SelectedItem.Data.Id } else { $script:Settings.DefaultLogin = 'current' }
    Save-Settings
    return $true
}

# ---------------------------------------------------------------------------
#  Файловые диалоги
# ---------------------------------------------------------------------------
function Select-FolderPath {
    param([string]$Description, [string]$Initial = '')
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Description
    $dlg.ShowNewFolderButton = $true
    if ($Initial -and (Test-Path -LiteralPath $Initial)) { $dlg.SelectedPath = $Initial }
    if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
    return $null
}

function Select-SaveFile {
    param([string]$Filter, [string]$FileName)
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = $Filter
    $dlg.FileName = Get-SafeFileName $FileName
    if ($dlg.ShowDialog($script:MainWindow)) { return $dlg.FileName }
    return $null
}

function Select-OpenFile {
    param([string]$Filter)
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = $Filter
    if ($dlg.ShowDialog($script:MainWindow)) { return $dlg.FileName }
    return $null
}

# ---------------------------------------------------------------------------
#  Контекстные меню
# ---------------------------------------------------------------------------
function New-MenuItem {
    param([string]$Header, [scriptblock]$Action, [string]$Icon = '', [object[]]$Children = @(), [bool]$Enabled = $true, $Tag = $null)
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $Header
    $mi.IsEnabled = $Enabled
    $mi.Tag = $Tag
    if ($Icon) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = Get-IconGlyph $Icon
        $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe MDL2 Assets')
        $tb.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString((Get-IconColor $Icon))
        $tb.HorizontalAlignment = 'Center'; $tb.VerticalAlignment = 'Center'
        $mi.Icon = $tb
    }
    if ($Action) {
        $mi.Add_Click($Action)
    }
    foreach ($ch in $Children) { [void]$mi.Items.Add($ch) }
    return $mi
}

function Show-DropMenu {
    param($Button, [object[]]$Items)
    $cm = New-Object System.Windows.Controls.ContextMenu
    foreach ($i in $Items) { [void]$cm.Items.Add($i) }
    $cm.PlacementTarget = $Button
    $cm.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $cm.IsOpen = $true
}

function New-MenuSeparator { return (New-Object System.Windows.Controls.Separator) }
