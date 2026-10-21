# Types.ps1 — классы модели представления (C# 5, компилируются один раз при запуске)

if (-not ('NetInv.Node' -as [type])) {
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.ObjectModel;
using System.ComponentModel;

namespace NetInv
{
    public class Notifier : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        protected void Raise(string name)
        {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h != null) h.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }

    // Узел дерева хранилища
    public class Node : Notifier
    {
        public Node() { Children = new ObservableCollection<Node>(); Visible = true; }
        public string Kind { get; set; }          // Root / Folder / Device
        public string Id { get; set; }
        public object Tag { get; set; }
        public ObservableCollection<Node> Children { get; private set; }
        public Node Parent { get; set; }
        public int Depth { get; set; }
        public string DepthMargin { get { return (Depth * 16).ToString() + ",0,0,0"; } }

        string _name; public string Name { get { return _name; } set { _name = value; Raise("Name"); } }
        string _count; public string Count { get { return _count; } set { _count = value; Raise("Count"); } }
        string _ip; public string Ip { get { return _ip; } set { _ip = value; Raise("Ip"); } }
        string _glyph; public string Glyph { get { return _glyph; } set { _glyph = value; Raise("Glyph"); } }
        string _glyphColor; public string GlyphColor { get { return _glyphColor; } set { _glyphColor = value; Raise("GlyphColor"); } }
        string _status = "Transparent"; public string StatusColor { get { return _status; } set { _status = value; Raise("StatusColor"); } }
        bool _expanded; public bool IsExpanded { get { return _expanded; } set { _expanded = value; Raise("IsExpanded"); } }
        bool _selected; public bool IsSelected { get { return _selected; } set { _selected = value; Raise("IsSelected"); } }
        bool _visible; public bool Visible { get { return _visible; } set { _visible = value; Raise("Visible"); Raise("VisibilityText"); } }
        public string VisibilityText { get { return _visible ? "Visible" : "Collapsed"; } }
        bool _bold; public bool IsBold { get { return _bold; } set { _bold = value; Raise("IsBold"); Raise("Weight"); } }
        public string Weight { get { return _bold ? "Bold" : "Normal"; } }
    }

    // Строка карточки устройства
    public class CardRow
    {
        public string Kind { get; set; }          // Header / Group / Item / Prop / Empty
        public string Key { get; set; }
        public string Text { get; set; }
        public string Value { get; set; }
        public string Value2 { get; set; }
        public string Mark { get; set; }          // yes / no / online / offline
        public double Indent { get; set; }
        public string Glyph { get; set; }
        public string GlyphColor { get; set; }
        public bool Expandable { get; set; }
        public bool Expanded { get; set; }
        public string ExpanderText { get { return Expanded ? "−" : "+"; } }
        public string IndentMargin { get { return Indent.ToString(System.Globalization.CultureInfo.InvariantCulture) + ",0,0,0"; } }
    }

    // Элемент списка категорий / шаблонов на боковых панелях
    public class SideItem : Notifier
    {
        public string Id { get; set; }
        public string Kind { get; set; }          // Item / Header / Folder / Separator
        public string Name { get; set; }
        public string Glyph { get; set; }
        public string GlyphColor { get; set; }
        public double Indent { get; set; }
        public string IndentMargin { get { return Indent.ToString(System.Globalization.CultureInfo.InvariantCulture) + ",0,0,0"; } }
        public object Tag { get; set; }
        string _count; public string Count { get { return _count; } set { _count = value; Raise("Count"); } }
        string _countColor = "#D9302C"; public string CountColor { get { return _countColor; } set { _countColor = value; Raise("CountColor"); } }
        bool? _checked = false; public bool? IsChecked { get { return _checked; } set { _checked = value; Raise("IsChecked"); } }
        bool _collapsed; public bool IsCollapsed { get { return _collapsed; } set { _collapsed = value; Raise("IsCollapsed"); Raise("Arrow"); } }
        public string Arrow { get { return _collapsed ? "▶" : "▼"; } }
        bool _visible = true; public bool Visible { get { return _visible; } set { _visible = value; Raise("Visible"); Raise("VisibilityText"); } }
        public string VisibilityText { get { return _visible ? "Visible" : "Collapsed"; } }
    }

    // Задача сканирования
    public class ScanTaskRow : Notifier
    {
        public static ObservableCollection<string> SharedLogins = new ObservableCollection<string>();
        public static ObservableCollection<string> SharedFolders = new ObservableCollection<string>();
        public ObservableCollection<string> LoginOptions { get { return SharedLogins; } }
        public ObservableCollection<string> FolderOptions { get { return SharedFolders; } }
        public string Id { get; set; }
        public object Task { get; set; }
        public string Glyph { get; set; }
        string _text; public string Text { get { return _text; } set { _text = value; Raise("Text"); } }
        bool _enabled = true; public bool Enabled { get { return _enabled; } set { _enabled = value; Raise("Enabled"); } }
        string _login; public string LoginName { get { return _login; } set { _login = value; Raise("LoginName"); } }
        string _folder; public string FolderName { get { return _folder; } set { _folder = value; Raise("FolderName"); } }
        string _status; public string Status { get { return _status; } set { _status = value; Raise("Status"); } }
        string _statusColor = "#666666"; public string StatusColor { get { return _statusColor; } set { _statusColor = value; Raise("StatusColor"); } }
    }

    // Запись журнала сканирования
    public class LogEntry
    {
        public string Time { get; set; }
        public string Text { get; set; }
        public string Glyph { get; set; }
        public string GlyphColor { get; set; }
    }
    // Строка таблицы «Учет ПО»
    public class SoftwareRow
    {
        public string Key { get; set; }
        public string Name { get; set; }
        public string Version { get; set; }
        public string Publisher { get; set; }
        public string PublisherText { get { return string.IsNullOrEmpty(Publisher) ? "" : "от " + Publisher; } }
        public string Category { get; set; }
        public string TypeText { get; set; }
        public string TypeColor { get; set; }
        public int Copies { get; set; }
        public string License { get; set; }
        public int VersionCount { get; set; }
        public string VersionCountText { get { return VersionCount > 1 ? VersionCount.ToString() : ""; } }
        public string Glyph { get; set; }
        public string GlyphColor { get; set; }
        public object Tag { get; set; }
    }

    // Строка таблицы лицензий
    public class LicenseRow
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Software { get; set; }
        public string Price { get; set; }
        public int Installed { get; set; }
        public int Seats { get; set; }
        public string Status { get; set; }
        public string StatusColor { get; set; }
        public object Tag { get; set; }
    }

    // Найденный ключ продукта
    public class KeyRow
    {
        public string Key { get; set; }
        public string Product { get; set; }
        public string DeviceName { get; set; }
        public string DeviceId { get; set; }
        public string Ip { get; set; }
        public string Source { get; set; }
    }

    // Строка журнала изменений
    public class ChangeRow
    {
        public DateTime DateSort { get; set; }
        public string DateText { get; set; }
        public string Device { get; set; }
        public string DeviceId { get; set; }
        public string Ip { get; set; }
        public string Category { get; set; }
        public string Glyph { get; set; }
        public string GlyphColor { get; set; }
        public string Change { get; set; }
        public string ChangeGlyph { get; set; }
        public string ChangeColor { get; set; }
        public string Item { get; set; }
        public string Old { get; set; }
        public string New { get; set; }
    }

    // Простой элемент списка
    public class ListItem
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Glyph { get; set; }
        public string GlyphColor { get; set; }
        public string Count { get; set; }
        public object Tag { get; set; }
    }
}
'@
}
