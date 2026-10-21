# Export.ps1 — экспорт: CSV, текст, HTML (таблицы и карточки для печати)

function ConvertTo-CsvText {
    param([System.Data.DataTable]$Table, [string]$Delimiter = ';')
    $sb = New-Object System.Text.StringBuilder
    $esc = {
        param($v)
        $s = [string]$v
        if ($s -eq [string][char]0x2014) { $s = '' }
        if ($s.Contains($Delimiter) -or $s.Contains('"') -or $s.Contains("`n") -or $s.Contains("`r")) { $s = '"' + $s.Replace('"', '""') + '"' }
        return $s
    }
    $cols = @($Table.Columns | ForEach-Object { $_.Caption })
    [void]$sb.AppendLine((($cols | ForEach-Object { & $esc $_ }) -join $Delimiter))
    foreach ($r in $Table.Rows) {
        $vals = for ($i = 0; $i -lt $cols.Count; $i++) { & $esc $r[$i] }
        [void]$sb.AppendLine(($vals -join $Delimiter))
    }
    return $sb.ToString()
}

function ConvertTo-TabText {
    param([System.Data.DataTable]$Table)
    $sb = New-Object System.Text.StringBuilder
    $cols = @($Table.Columns | ForEach-Object { $_.Caption })
    [void]$sb.AppendLine(($cols -join "`t"))
    foreach ($r in $Table.Rows) {
        $vals = for ($i = 0; $i -lt $cols.Count; $i++) { ([string]$r[$i]) -replace "[\t\r\n]+", ' ' }
        [void]$sb.AppendLine(($vals -join "`t"))
    }
    return $sb.ToString()
}

function ConvertTo-HtmlEncoded {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

$script:HtmlStyle = @'
<style>
body { font-family: Tahoma, "Segoe UI", Arial, sans-serif; font-size: 12px; color: #222; margin: 20px; }
h1 { font-size: 20px; color: #2F7FD0; font-weight: normal; margin: 0 0 4px 0; }
.sub { color: #888; margin-bottom: 16px; }
table.grid { border-collapse: collapse; width: 100%; }
table.grid th { background: #F3F3F3; color: #555; font-weight: normal; text-align: left; border: 1px solid #DADADA; padding: 4px 6px; }
table.grid td { border: 1px solid #E4E4E4; padding: 3px 6px; vertical-align: top; }
table.grid tr:nth-child(even) td { background: #FAFAFA; }
.cat { background: #DCEBFA; color: #2F7FD0; font-size: 16px; padding: 5px 8px; margin-top: 18px; }
.grp { background: #F0F0F0; color: #666; font-weight: bold; padding: 3px 8px; margin-top: 6px; }
table.props { border-collapse: collapse; width: 100%; }
table.props td { padding: 2px 8px; vertical-align: top; }
table.props td.k { color: #2F7FD0; width: 260px; }
.v2 { color: #2F7FD0; }
.yes { color: #2E9E3E; } .no { color: #D9302C; }
.page { page-break-after: always; }
@media print { body { margin: 0; } }
</style>
'@

function ConvertTo-HtmlTable {
    param([string]$Title, [string]$Subtitle, [System.Data.DataTable]$Table)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!DOCTYPE html><html><head><meta charset="utf-8"><title>' + (ConvertTo-HtmlEncoded $Title) + '</title>' + $script:HtmlStyle + '</head><body>')
    [void]$sb.Append('<h1>' + (ConvertTo-HtmlEncoded $Title) + '</h1><div class="sub">' + (ConvertTo-HtmlEncoded $Subtitle) + '</div>')
    [void]$sb.Append('<table class="grid"><tr>')
    foreach ($c in $Table.Columns) { [void]$sb.Append('<th>' + (ConvertTo-HtmlEncoded $c.Caption) + '</th>') }
    [void]$sb.Append('</tr>')
    foreach ($r in $Table.Rows) {
        [void]$sb.Append('<tr>')
        for ($i = 0; $i -lt $Table.Columns.Count; $i++) { [void]$sb.Append('<td>' + (ConvertTo-HtmlEncoded ([string]$r[$i])) + '</td>') }
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</table></body></html>')
    return $sb.ToString()
}

function ConvertTo-HtmlBlocks {
    param([array]$Blocks)
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $Blocks) {
        $t = ConvertTo-HtmlEncoded $b.Title
        if ($b.Extra) { $t += ' <span style="font-weight:normal;color:#888">' + (ConvertTo-HtmlEncoded $b.Extra) + '</span>' }
        [void]$sb.Append('<div class="grp">' + $t + '</div><table class="props">')
        foreach ($p in $b.Props) {
            $cls = ''
            if ($p.Mark -eq 'yes' -or $p.Mark -eq 'online') { $cls = ' class="yes"' } elseif ($p.Mark -eq 'no' -or $p.Mark -eq 'offline') { $cls = ' class="no"' }
            $v = '<span' + $cls + '>' + (ConvertTo-HtmlEncoded $p.V) + '</span>'
            if ($p.V2) { $v += ' <span class="v2">' + (ConvertTo-HtmlEncoded $p.V2) + '</span>' }
            [void]$sb.Append('<tr><td class="k">' + (ConvertTo-HtmlEncoded $p.K) + '</td><td>' + $v + '</td></tr>')
        }
        [void]$sb.Append('</table>')
        if ($b.Subs) { [void]$sb.Append((ConvertTo-HtmlBlocks $b.Subs)) }
    }
    return $sb.ToString()
}

function ConvertTo-HtmlCards {
    # $Pages: массив @{ Title; Subtitle; Sections = @( @{ Name; Blocks } ) }
    param([string]$DocTitle, [array]$Pages)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!DOCTYPE html><html><head><meta charset="utf-8"><title>' + (ConvertTo-HtmlEncoded $DocTitle) + '</title>' + $script:HtmlStyle + '</head><body>')
    $n = 0
    foreach ($pg in $Pages) {
        $n++
        $cls = if ($n -lt $Pages.Count) { ' class="page"' } else { '' }
        [void]$sb.Append('<div' + $cls + '><h1>' + (ConvertTo-HtmlEncoded $pg.Title) + '</h1><div class="sub">' + (ConvertTo-HtmlEncoded $pg.Subtitle) + '</div>')
        foreach ($s in $pg.Sections) {
            [void]$sb.Append('<div class="cat">' + (ConvertTo-HtmlEncoded $s.Name) + '</div>')
            [void]$sb.Append((ConvertTo-HtmlBlocks $s.Blocks))
        }
        [void]$sb.Append('</div>')
    }
    [void]$sb.Append('</body></html>')
    return $sb.ToString()
}

function Save-TextFile {
    param([string]$Path, [string]$Text, [switch]$Bom)
    $enc = New-Object System.Text.UTF8Encoding([bool]$Bom)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Open-InShell {
    param([string]$Path)
    try { Start-Process -FilePath $Path | Out-Null } catch { }
}
