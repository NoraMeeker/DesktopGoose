# Goose on the Loose, desktop edition.
# A goose walks around your Windows desktop. It steals your cursor, drags windows by
# their title bars, brings you sticky notes, tracks mud everywhere, and naps while you type.
#
# Settings: Ctrl+Shift+O. Send it home: Ctrl+Shift+G, or right-click the tray icon. Holding any mouse button makes
# it let go of whatever it has. Settings (tray icon > Settings) live in
# %APPDATA%\GooseOnTheLoose\settings.ini; note messages in notes.txt in the same folder.
param([switch]$CheckOnly)

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes, WindowsBase, Accessibility -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;
using System.Windows.Forms;

public static class GooseNative {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
    [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr h, uint id, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out object obj);
    [DllImport("oleacc.dll")] public static extern int AccessibleChildren(Accessibility.IAccessible parent, int start, int count, [Out] object[] children, out int obtained);
    [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromPoint(POINT pt, [MarshalAs(UnmanagedType.Interface)] out Accessibility.IAccessible acc, out object child);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

    public static bool Down(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
    public static bool AnyMouseButton() { return Down(0x01) || Down(0x02) || Down(0x04) || Down(0x05) || Down(0x06); }
    public static bool AnyKey() {
        for (int vk = 0x08; vk < 0xFF; vk++) if (Down(vk)) return true;
        return false;
    }
    public static string TitleOf(IntPtr h) { StringBuilder sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
    public static string ClassOf(IntPtr h) { StringBuilder sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    public static Rectangle RectOf(IntPtr h) { RECT r; GetWindowRect(h, out r); return Rectangle.FromLTRB(r.Left, r.Top, r.Right, r.Bottom); }
    public static void KeepOnTop(IntPtr h) { SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x1 | 0x2 | 0x10); }
}

public class GooseSettings {
    public int Chaos = 5, Volume = 60, Speed = 100;
    public bool StealCursor = true, DragWindows = true, FetchNotes = true, Footprints = true,
                SleepWhenTyping = true, WorkMode = false, Fernrel = false, OpenTabs = true, TypeGibberish = true, SearchGibberish = true,
                Knife = true, StabScreen = true, Swordfight = true, FootstepSounds = true, SnoreSounds = true;

    public static string Dir { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "GooseOnTheLoose"); } }
    static string FilePath { get { return Path.Combine(Dir, "settings.ini"); } }
    public static void Log(string msg) {
        try { File.AppendAllText(Path.Combine(Dir, "error.log"), DateTime.Now.ToString("s") + " " + msg + Environment.NewLine); } catch { }
    }
    public static string NotesPath { get { return Path.Combine(Dir, "notes.txt"); } }

    public static readonly string[] DefaultNotes = {
        "HONK",
        "Code freeze is a state of mind.",
        "I know where your cursor lives.",
        "Nothing ships. Everything honks.",
        "Did you save that file? Are you sure?",
        "This note was delivered by goose. Tipping is mandatory.",
        "Bread. Now.",
    };

    public static GooseSettings Load() {
        GooseSettings s = new GooseSettings();
        try {
            Directory.CreateDirectory(Dir);
            if (File.Exists(FilePath))
                foreach (string line in File.ReadAllLines(FilePath)) {
                    int i = line.IndexOf('=');
                    if (i > 0) s.Set(line.Substring(0, i).Trim(), line.Substring(i + 1).Trim());
                }
            if (!File.Exists(NotesPath)) File.WriteAllLines(NotesPath, DefaultNotes);
        } catch { }
        return s;
    }

    void Set(string k, string v) {
        int n; bool b = v.Equals("true", StringComparison.OrdinalIgnoreCase);
        switch (k) {
            case "Chaos": if (int.TryParse(v, out n)) Chaos = Math.Max(1, Math.Min(10, n)); break;
            case "Volume": if (int.TryParse(v, out n)) Volume = Math.Max(0, Math.Min(100, n)); break;
            case "Speed": if (int.TryParse(v, out n)) Speed = Math.Max(50, Math.Min(200, n)); break;
            case "StealCursor": StealCursor = b; break;
            case "DragWindows": DragWindows = b; break;
            case "FetchNotes": FetchNotes = b; break;
            case "Footprints": Footprints = b; break;
            case "SleepWhenTyping": SleepWhenTyping = b; break;
            case "WorkMode": WorkMode = b; break;
            case "Fernrel": Fernrel = b; break;
            case "Knife": Knife = b; break;
            case "StabScreen": StabScreen = b; break;
            case "Swordfight": Swordfight = b; break;
            case "FootstepSounds": FootstepSounds = b; break;
            case "SnoreSounds": SnoreSounds = b; break;
            case "OpenTabs": OpenTabs = b; break;
            case "TypeGibberish": TypeGibberish = b; break;
            case "SearchGibberish": SearchGibberish = b; break;
        }
    }

    public void Save() {
        try {
            Directory.CreateDirectory(Dir);
            File.WriteAllLines(FilePath, new string[] {
                "Chaos=" + Chaos, "Volume=" + Volume, "Speed=" + Speed,
                "StealCursor=" + StealCursor.ToString().ToLower(), "DragWindows=" + DragWindows.ToString().ToLower(),
                "FetchNotes=" + FetchNotes.ToString().ToLower(), "Footprints=" + Footprints.ToString().ToLower(),
                "SleepWhenTyping=" + SleepWhenTyping.ToString().ToLower(), "WorkMode=" + WorkMode.ToString().ToLower(),
                "Knife=" + Knife.ToString().ToLower(), "StabScreen=" + StabScreen.ToString().ToLower(),
                "Swordfight=" + Swordfight.ToString().ToLower(), "FootstepSounds=" + FootstepSounds.ToString().ToLower(),
                "SnoreSounds=" + SnoreSounds.ToString().ToLower(),
                "Fernrel=" + Fernrel.ToString().ToLower(), "OpenTabs=" + OpenTabs.ToString().ToLower(),
                "TypeGibberish=" + TypeGibberish.ToString().ToLower(), "SearchGibberish=" + SearchGibberish.ToString().ToLower(),
            });
        } catch { }
    }
}

// Full-screen, click-through layer that holds the mud. Prints dry lighter, then flake away.
// No alpha here (transparency key), so "fading" is three solid shades of mud.
public class PrintLayer : Form {
    class Print { public float X, Y, A, Age; public int Stage; }
    class Crack { public List<PointF[]> Lines = new List<PointF[]>(); public PointF[] Hole; public Rectangle Box; public float Age; }
    List<Print> prints = new List<Print>();
    List<Crack> cracks = new List<Crack>();
    Random rng = new Random();
    static readonly Color GlassDark = Color.FromArgb(40, 44, 52), GlassLight = Color.FromArgb(236, 241, 246);
    Timer timer = new Timer();
    static readonly Color Key = Color.FromArgb(255, 0, 255);
    static readonly Color[] Mud = { Color.FromArgb(88, 64, 38), Color.FromArgb(122, 95, 62), Color.FromArgb(160, 138, 104) };

    public PrintLayer() {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
        StartPosition = FormStartPosition.Manual; BackColor = Key; TransparencyKey = Key; DoubleBuffered = true;
        Bounds = SystemInformation.VirtualScreen;
        timer.Interval = 100; timer.Tick += delegate { Age(0.1f); }; timer.Start();
    }
    protected override CreateParams CreateParams {
        get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x80000 | 0x20 | 0x80 | 0x08000000; return cp; }
    }
    protected override bool ShowWithoutActivation { get { return true; } }

    Rectangle Area(Print p) { return new Rectangle((int)p.X - 10, (int)p.Y - 10, 20, 20); }

    public void Add(float sx, float sy, float a) {
        Print p = new Print { X = sx - Left, Y = sy - Top, A = a };
        prints.Add(p); Invalidate(Area(p));
        if (prints.Count > 220) { Invalidate(Area(prints[0])); prints.RemoveAt(0); }
    }
    public void Wipe() { prints.Clear(); Invalidate(); }

    float R(float a, float b) { return a + (float)rng.NextDouble() * (b - a); }

    // A spiderweb crack: jagged spokes out from the impact, joined by broken rings
    public void AddCrack(float sx, float sy) {
        float cx = sx - Left, cy = sy - Top;
        Crack c = new Crack();
        int spokes = rng.Next(7, 12);
        float[] rings = { R(22, 34), R(50, 75), R(95, 130) };
        PointF[,] ringPts = new PointF[spokes, rings.Length];
        float minX = cx, minY = cy, maxX = cx, maxY = cy;
        for (int i = 0; i < spokes; i++) {
            float a = (float)(i * 2 * Math.PI / spokes) + R(-0.25f, 0.25f), len = R(80, 200);
            List<PointF> pts = new List<PointF>();
            pts.Add(new PointF(cx, cy));
            int ri = 0;
            for (float r = 14; r < len; r += R(12, 26)) {
                float aj = a + R(-0.12f, 0.12f);
                PointF p = new PointF(cx + (float)Math.Cos(aj) * r, cy + (float)Math.Sin(aj) * r);
                pts.Add(p);
                while (ri < rings.Length && r >= rings[ri]) ringPts[i, ri++] = p;
                minX = Math.Min(minX, p.X); minY = Math.Min(minY, p.Y); maxX = Math.Max(maxX, p.X); maxY = Math.Max(maxY, p.Y);
            }
            for (; ri < rings.Length; ri++) ringPts[i, ri] = PointF.Empty;   // spoke too short to reach this ring
            c.Lines.Add(pts.ToArray());
        }
        for (int k = 0; k < rings.Length; k++)
            for (int i = 0; i < spokes; i++) {
                PointF p1 = ringPts[i, k], p2 = ringPts[(i + 1) % spokes, k];
                if (p1.IsEmpty || p2.IsEmpty || rng.NextDouble() < 0.3) continue;
                c.Lines.Add(new PointF[] { p1, new PointF((p1.X + p2.X) / 2 + R(-5, 5), (p1.Y + p2.Y) / 2 + R(-5, 5)), p2 });
            }
        c.Hole = new PointF[10];   // the impact point: a little shattered star
        for (int i = 0; i < 10; i++) {
            float a = (float)(i * Math.PI / 5), r = i % 2 == 0 ? R(7, 11) : R(2, 4);
            c.Hole[i] = new PointF(cx + (float)Math.Cos(a) * r, cy + (float)Math.Sin(a) * r);
        }
        c.Box = Rectangle.FromLTRB((int)minX - 12, (int)minY - 12, (int)maxX + 12, (int)maxY + 12);
        cracks.Add(c); Invalidate(c.Box);
        if (cracks.Count > 8) { Invalidate(cracks[0].Box); cracks.RemoveAt(0); }
    }

    public void SweepGlass() { foreach (Crack c in cracks) Invalidate(c.Box); cracks.Clear(); }

    // A red X where the goose's blade hit your cursor; gone after 1.5s
    class Slash { public float X, Y, Age, A; }
    List<Slash> slashes = new List<Slash>();
    static readonly Color SlashRed = Color.FromArgb(220, 38, 38);
    Rectangle Area(Slash s) { return new Rectangle((int)s.X - 26, (int)s.Y - 26, 52, 52); }
    public void AddSlash(float sx, float sy) {
        Slash s = new Slash { X = sx - Left, Y = sy - Top, A = R(-0.4f, 0.4f) };
        slashes.Add(s); Invalidate(Area(s));
    }

    void Age(float dt) {
        for (int i = prints.Count - 1; i >= 0; i--) {
            Print p = prints[i]; p.Age += dt;
            int st = (int)(p.Age / 3.5f);
            if (st != p.Stage) { p.Stage = st; Invalidate(Area(p)); if (st > 2) prints.RemoveAt(i); }
        }
        for (int i = cracks.Count - 1; i >= 0; i--) {
            cracks[i].Age += dt;
            if (cracks[i].Age > 40) { Invalidate(cracks[i].Box); cracks.RemoveAt(i); }
        }
        for (int i = slashes.Count - 1; i >= 0; i--) {
            slashes[i].Age += dt;
            if (slashes[i].Age > 1.5f) { Invalidate(Area(slashes[i])); slashes.RemoveAt(i); }
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.None;
        foreach (Print p in prints) {
            using (Pen pen = new Pen(Mud[p.Stage], 2.4f)) {
                GraphicsState st = g.Save();
                g.TranslateTransform(p.X, p.Y); g.RotateTransform(p.A * 180f / (float)Math.PI);
                g.DrawLine(pen, -5, 0, 4, 0); g.DrawLine(pen, -1, 0, 5, -5); g.DrawLine(pen, -1, 0, 5, 5);
                g.Restore(st);
            }
        }
        // dark under light, so cracks read on any background
        using (Pen dark = new Pen(GlassDark, 3f)) using (Pen thin = new Pen(GlassDark, 1.5f))
        using (Pen light = new Pen(GlassLight, 1.3f)) using (SolidBrush lightB = new SolidBrush(GlassLight)) {
            foreach (Crack c in cracks) {
                foreach (PointF[] l in c.Lines) g.DrawLines(dark, l);
                foreach (PointF[] l in c.Lines) g.DrawLines(light, l);
                g.FillPolygon(lightB, c.Hole); g.DrawPolygon(thin, c.Hole);
            }
        }
        using (Pen outline = new Pen(GlassDark, 7)) using (Pen red = new Pen(SlashRed, 4)) {
            outline.StartCap = outline.EndCap = red.StartCap = red.EndCap = LineCap.Round;
            foreach (Slash sl in slashes) {
                GraphicsState st = g.Save();
                g.TranslateTransform(sl.X, sl.Y); g.RotateTransform(sl.A * 57.3f);
                g.DrawLine(outline, -18, -18, 18, 18); g.DrawLine(outline, -18, 18, 18, -18);
                g.DrawLine(red, -18, -18, 18, 18); g.DrawLine(red, -18, 18, 18, -18);
                g.Restore(st);
            }
        }
    }
}

// A sticky note the goose drags in. You can drag it by any part, and the x closes it.
public class NoteForm : Form {
    string text;
    public bool Held;
    static readonly Color Paper = Color.FromArgb(255, 241, 168), Edge = Color.FromArgb(224, 203, 98), Ink = Color.FromArgb(31, 42, 28), Muted = Color.FromArgb(120, 110, 70);

    public NoteForm(string text) {
        this.text = text;
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
        StartPosition = FormStartPosition.Manual; Size = new Size(220, 140); BackColor = Paper; DoubleBuffered = true;
    }
    protected override CreateParams CreateParams {
        get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x80 | 0x08000000; return cp; }
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    Rectangle CloseBox { get { return new Rectangle(Width - 28, 4, 24, 24); } }

    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x231) Held = true;   // WM_ENTERSIZEMOVE
        if (m.Msg == 0x232) Held = false;  // WM_EXITSIZEMOVE
        base.WndProc(ref m);
        if (m.Msg == 0x84 && (int)m.Result == 1) {  // WM_NCHITTEST on client: drag from anywhere but the x
            long lp = m.LParam.ToInt64();
            Point p = PointToClient(new Point((short)(lp & 0xFFFF), (short)((lp >> 16) & 0xFFFF)));
            if (!CloseBox.Contains(p)) m.Result = (IntPtr)2;
        }
    }
    protected override void OnMouseClick(MouseEventArgs e) {
        if (CloseBox.Contains(e.Location)) Close();
        base.OnMouseClick(e);
    }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (SolidBrush edge = new SolidBrush(Edge)) g.FillRectangle(edge, 0, Height - 5, Width, 5);
        using (Font f = new Font("Segoe Print", 11f))
        using (Font small = new Font("Segoe UI", 8f, FontStyle.Italic))
        using (Font x = new Font("Segoe UI", 11f, FontStyle.Bold))
        using (SolidBrush ink = new SolidBrush(Ink))
        using (SolidBrush muted = new SolidBrush(Muted)) {
            g.DrawString(text, f, ink, new RectangleF(14, 12, Width - 44, Height - 40));
            g.DrawString("delivered by goose", small, muted, 14, Height - 26);
            g.DrawString("\u00d7", x, muted, Width - 25, 4);
        }
    }
}

public class SettingsForm : Form {
    TableLayoutPanel t = new TableLayoutPanel();
    Action changed;

    public SettingsForm(GooseSettings s, Action changed) {
        this.changed = changed;
        Text = "Goose on the Loose"; FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false; MinimizeBox = false; StartPosition = FormStartPosition.CenterScreen; TopMost = true;
        AutoSize = true; AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Font = new Font("Segoe UI", 9.5f); Padding = new Padding(14);
        t.ColumnCount = 2; t.AutoSize = true; t.Dock = DockStyle.Fill;

        Header("Behavior");
        Slider("Chaos", "how often it makes trouble", 1, 10, 1, s.Chaos, delegate(int v) { s.Chaos = v; });
        Slider("Speed", "% of normal goose speed", 50, 200, 10, s.Speed, delegate(int v) { s.Speed = v; });
        Slider("Honk volume", "0 is silent", 0, 100, 10, s.Volume, delegate(int v) { s.Volume = v; });
        Check("Footstep sounds", s.FootstepSounds, delegate(bool v) { s.FootstepSounds = v; });
        Check("Snoring while it naps", s.SnoreSounds, delegate(bool v) { s.SnoreSounds = v; });
        Header("Mischief");
        Check("Steal my cursor", s.StealCursor, delegate(bool v) { s.StealCursor = v; });
        Check("Drag my windows around (only moves them, never resizes or closes)", s.DragWindows, delegate(bool v) { s.DragWindows = v; });
        Check("Bring me sticky notes", s.FetchNotes, delegate(bool v) { s.FetchNotes = v; });
        Check("Open new tabs in Firefox (pecks the + button)", s.OpenTabs, delegate(bool v) { s.OpenTabs = v; });
        Check("Type gibberish into the new tab's address bar", s.TypeGibberish, delegate(bool v) { s.TypeGibberish = v; });
        Check("...then peck the arrow to search for it", s.SearchGibberish, delegate(bool v) { s.SearchGibberish = v; });
        Check("Leave muddy footprints", s.Footprints, delegate(bool v) { s.Footprints = v; });
        Header("Manners");
        Check("Nap while I'm typing", s.SleepWhenTyping, delegate(bool v) { s.SleepWhenTyping = v; });
        Check("Work mode: walk around, no mischief", s.WorkMode, delegate(bool v) { s.WorkMode = v; });
        Header("Knife");
        Check("Give the goose a knife", s.Knife, delegate(bool v) { s.Knife = v; });
        Check("Let it stab the screen (cracks the glass)", s.StabScreen, delegate(bool v) { s.StabScreen = v; });
        Check("Let it swordfight my cursor", s.Swordfight, delegate(bool v) { s.Swordfight = v; });
        Header("Costume");
        Check("Fernrel mode (Astral Elf ranger goose)", s.Fernrel, delegate(bool v) { s.Fernrel = v; });

        FlowLayoutPanel buttons = new FlowLayoutPanel(); buttons.AutoSize = true; buttons.Margin = new Padding(0, 14, 0, 0);
        Button notes = new Button(); notes.Text = "Edit note messages\u2026"; notes.AutoSize = true;
        notes.Click += delegate { try { Process.Start("notepad.exe", "\"" + GooseSettings.NotesPath + "\""); } catch { } };
        Button done = new Button(); done.Text = "Done"; done.AutoSize = true; done.Click += delegate { Close(); };
        buttons.Controls.Add(notes); buttons.Controls.Add(done);
        Row(buttons, null);
        AcceptButton = done;
        Controls.Add(t);
    }

    void Row(Control a, Control b) {
        int r = t.RowCount++;
        t.Controls.Add(a, 0, r);
        if (b != null) t.Controls.Add(b, 1, r); else t.SetColumnSpan(a, 2);
    }
    void Header(string text) {
        Label l = new Label(); l.Text = text; l.AutoSize = true;
        l.Font = new Font("Segoe UI", 10f, FontStyle.Bold); l.Margin = new Padding(0, 12, 0, 4);
        Row(l, null);
    }
    void Slider(string name, string hint, int min, int max, int step, int val, Action<int> set) {
        Label l = new Label(); l.AutoSize = true; l.Anchor = AnchorStyles.Left; l.Margin = new Padding(0, 0, 12, 0);
        TrackBar tb = new TrackBar(); tb.Minimum = min; tb.Maximum = max; tb.Value = val; tb.Width = 220;
        tb.TickFrequency = step; tb.SmallChange = step; tb.LargeChange = step;
        l.Text = name + ": " + val + "\n" + hint;
        tb.ValueChanged += delegate {
            int v = (int)Math.Round((double)tb.Value / step) * step;
            l.Text = name + ": " + v + "\n" + hint;
            set(v); changed();
        };
        Row(l, tb);
    }
    void Check(string text, bool val, Action<bool> set) {
        CheckBox c = new CheckBox(); c.Text = text; c.Checked = val; c.AutoSize = true;
        c.CheckedChanged += delegate { set(c.Checked); changed(); };
        Row(c, null);
    }
}

// A separate waveOut stream for small ambient sounds (footsteps, snores). SoundPlayer can only
// play one sound per process, so these get their own channel and Windows mixes them with the honks.
public class SfxChannel : IDisposable {
    [DllImport("winmm.dll")] static extern int waveOutOpen(out IntPtr h, uint dev, ref WaveFormat fmt, IntPtr cb, IntPtr inst, uint flags);
    [DllImport("winmm.dll")] static extern int waveOutPrepareHeader(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int waveOutUnprepareHeader(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int waveOutWrite(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int waveOutReset(IntPtr h);
    [DllImport("winmm.dll")] static extern int waveOutClose(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] struct WaveFormat { public ushort Tag, Channels; public uint Rate, BytesPerSec; public ushort Align, Bits, Extra; }
    [StructLayout(LayoutKind.Sequential)] struct WaveHdr { public IntPtr Data; public uint Length, Recorded; public IntPtr User; public uint Flags, Loops; public IntPtr Next, Reserved; }

    IntPtr dev;
    List<IntPtr> hdrs = new List<IntPtr>(), datas = new List<IntPtr>();
    static readonly int HdrSize = Marshal.SizeOf(typeof(WaveHdr));

    public SfxChannel(List<short[]> clips, int rate) {
        WaveFormat f = new WaveFormat { Tag = 1, Channels = 1, Rate = (uint)rate, BytesPerSec = (uint)rate * 2, Align = 2, Bits = 16 };
        if (waveOutOpen(out dev, 0xFFFFFFFF, ref f, IntPtr.Zero, IntPtr.Zero, 0) != 0) { dev = IntPtr.Zero; GooseSettings.Log("Couldn't open an audio channel"); return; }
        foreach (short[] clip in clips) {
            IntPtr data = Marshal.AllocHGlobal(clip.Length * 2);
            Marshal.Copy(clip, 0, data, clip.Length);
            WaveHdr h = new WaveHdr { Data = data, Length = (uint)clip.Length * 2 };
            IntPtr hp = Marshal.AllocHGlobal(HdrSize);
            Marshal.StructureToPtr(h, hp, false);
            waveOutPrepareHeader(dev, hp, HdrSize);
            hdrs.Add(hp); datas.Add(data);
        }
    }

    // Plays a random clip that isn't already queued
    public void Play(Random rng) {
        if (dev == IntPtr.Zero || hdrs.Count == 0) return;
        int start = rng.Next(hdrs.Count);
        for (int i = 0; i < hdrs.Count; i++) {
            IntPtr hp = hdrs[(start + i) % hdrs.Count];
            WaveHdr h = (WaveHdr)Marshal.PtrToStructure(hp, typeof(WaveHdr));
            if ((h.Flags & 0x10) == 0) { waveOutWrite(dev, hp, HdrSize); return; }   // WHDR_INQUEUE
        }
    }

    public void Dispose() {
        if (dev != IntPtr.Zero) {
            waveOutReset(dev);
            foreach (IntPtr hp in hdrs) waveOutUnprepareHeader(dev, hp, HdrSize);
            waveOutClose(dev);
            dev = IntPtr.Zero;
        }
        foreach (IntPtr hp in hdrs) Marshal.FreeHGlobal(hp);
        foreach (IntPtr d in datas) Marshal.FreeHGlobal(d);
        hdrs.Clear(); datas.Clear();
    }
}

public class GooseForm : Form {
    static readonly Color Key = Color.FromArgb(255, 0, 255);
    static readonly Color Ink = Color.FromArgb(31, 42, 28);
    static readonly Color Beak = Color.FromArgb(232, 137, 43);
    static readonly Color Feather = Color.FromArgb(251, 251, 247);
    static readonly Color Wing = Color.FromArgb(222, 224, 214);
    // Fernrel: brown hair, freckles, green eyes with purple lightning, white plates, blue gems, twin rapiers
    static readonly Color Hair = Color.FromArgb(107, 68, 35);
    static readonly Color Freckle = Color.FromArgb(160, 100, 62);
    static readonly Color EyeGreen = Color.FromArgb(52, 150, 70);
    static readonly Color Plate = Color.FromArgb(232, 239, 250);
    static readonly Color Gem = Color.FromArgb(47, 111, 214);
    static readonly Color Steel = Color.FromArgb(140, 150, 162);
    static readonly Color Storm = Color.FromArgb(160, 70, 250);
    static readonly Color KnifeHandle = Color.FromArgb(110, 72, 40);
    static readonly Color Blade = Color.FromArgb(214, 220, 228);
    static readonly Color Spark = Color.FromArgb(255, 214, 64);

    static readonly string[] FernrelQuotes = {
        "Slayer's Prey: your cursor.",
        "By Linxa'Kasendalor's Fangs! HONK!",
        "Rolled Stealth. Nat 1. HONK.",
        "Natural Explorer: this desktop is my terrain.",
        "Lucky. Rerolling that.",
        "Zone of Truth: you have too many tabs open.",
        "Favored Enemy: the mouse pointer.",
    };
    static readonly string[] FernrelNotes = {
        "Ask the DM what 'resistance to magic' covers.",
        "Do not use the lightning. (I will use the lightning.)",
        "Rations: 1 day. Snacks: 0. HONK.",
        "Slayer's Prey target: you.",
        "Zhol'Vadir had better desks than this.",
    };

    const float S = 1.4f;                               // goose scale
    const int WW = 480, WH = 210, FX = 240, FY = 190;   // window size, and where the feet sit in it

    GooseSettings cfg = GooseSettings.Load();
    PrintLayer layer = new PrintLayer();
    SettingsForm settingsForm;
    List<NoteForm> notes = new List<NoteForm>();
    Random rng = new Random();
    Timer timer = new Timer();
    NotifyIcon tray = new NotifyIcon();
    Stopwatch clock = Stopwatch.StartNew();
    Dictionary<string, List<byte[]>> honks;
    int lastHonk = -1;
    double lastTick;

    float x, y, vx, vy, phase, neck, stateT, timerT, stepAcc, flapT, sayT, sparkleT, zapT, nextZap = 30;
    int dir = 1, stepSide = 1;
    string state = "wander", say;
    PointF target;
    bool sleeping, stepped, settingsKeyWasDown, fightKeyWasDown;
    float cmdCheckT, danceHop; int danceBeat; bool danceEncore;
    IntPtr win; Point grabOff; int dragDir;
    // Knife: screen stabbing and cursor duels
    SfxChannel steps, snores; int sfxVolume = -1; float snoreT;
    float windT, lungeT, lungeCd, parryCd, sparkT, mouseSpeed; int duelHits, parries; PointF stabSpot; Point lastMouse;
    // Firefox tab pecking: the button lookup runs on a worker thread (UI Automation can be slow)
    IntPtr fox; int tabsLeft, lastTyped; float peckT; bool lookupStarted;
    volatile bool lookupDone; AutomationElement tabButton; Rectangle tabRect;
    // Gibberish: typed into the address bar through UI Automation (sets the text, no key presses)
    AutomationElement urlbar; Rectangle urlRect, goRect; string gibText = "";
    volatile int typedLen; volatile bool typingDone, abortTyping;
    static readonly string[] GibBits = { "honk", "HONK", "hjonk", "bread", "asdfjkl", "gooose", "hnnk", "wheres the bread",
        "jkjkjk", "???", "!!", "honkhonk", "plz", "mlem", "zzt", "8", "ahahsh", "qwghk", "breadbreadbread", "hOnK" };
    NoteForm carried;
    double lastKeyAt = -100, typingSince = -100;

    public GooseForm() {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
        StartPosition = FormStartPosition.Manual; BackColor = Key; TransparencyKey = Key;
        Size = new Size(WW, WH); DoubleBuffered = true;

        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        x = wa.Left + wa.Width * 0.5f; y = wa.Top + wa.Height * 0.6f;
        target = RandPt(); timerT = 5;
        Location = new Point((int)x - FX, (int)y - FY);
        honks = MakeHonkBank(cfg.Volume, rng);
        BuildSfx();

        tray.Icon = MakeIcon();
        tray.Text = "Goose on the Loose (Ctrl+Shift+O settings, Ctrl+Shift+G home)";
        ContextMenu menu = new ContextMenu();
        menu.MenuItems.Add("Settings\u2026", delegate { OpenSettings(); });
        menu.MenuItems.Add("Sweep up the glass", delegate { layer.SweepGlass(); });
        menu.MenuItems.Add("Send goose home", delegate { Close(); });
        tray.ContextMenu = menu;
        tray.DoubleClick += delegate { OpenSettings(); };
        tray.Visible = true;
        tray.ShowBalloonTip(5000, "A goose has arrived",
            "Ctrl+Shift+O opens settings. Ctrl+Shift+G sends it home.", ToolTipIcon.Info);

        timer.Interval = 16; timer.Tick += delegate { Tick(); }; timer.Start();
    }

    // Layered + click-through + hidden from alt-tab + never takes focus
    protected override CreateParams CreateParams {
        get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x80000 | 0x20 | 0x80 | 0x08000000; return cp; }
    }
    protected override bool ShowWithoutActivation { get { return true; } }

    protected override void OnShown(EventArgs e) {
        base.OnShown(e);
        layer.Show();
        GooseNative.KeepOnTop(Handle);
    }

    protected override void OnFormClosed(FormClosedEventArgs e) {
        timer.Stop();
        tray.Visible = false; tray.Dispose();
        layer.Close();
        if (steps != null) steps.Dispose();
        if (snores != null) snores.Dispose();
        foreach (NoteForm n in notes.ToArray()) if (!n.IsDisposed) n.Close();
        if (settingsForm != null && !settingsForm.IsDisposed) settingsForm.Close();
        base.OnFormClosed(e);
    }

    void OpenSettings() {
        try {
            if (settingsForm == null || settingsForm.IsDisposed) {
                settingsForm = new SettingsForm(cfg, SettingsChanged);
                settingsForm.Show();
            }
            settingsForm.WindowState = FormWindowState.Normal;
            GooseNative.KeepOnTop(settingsForm.Handle);
            settingsForm.Activate();
        } catch (Exception ex) { GooseSettings.Log("OpenSettings: " + ex); }
    }

    void SettingsChanged() {
        cfg.Save();
        honks = MakeHonkBank(cfg.Volume, rng);
        BuildSfx();
        if (!cfg.Footprints) layer.Wipe();
        if (cfg.WorkMode && state != "wander" && state != "sleep") { carried = null; SetState("wander", MischiefDelay()); }
    }

    // ---------- helpers ----------
    float Rand(float a, float b) { return a + (float)rng.NextDouble() * (b - a); }
    static float Dist(float ax, float ay, float bx, float by) { return (float)Math.Sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by)); }
    static Rectangle WA { get { return Screen.PrimaryScreen.WorkingArea; } }
    PointF RandPt() { Rectangle wa = WA; return new PointF(Rand(wa.Left + 80, wa.Right - 80), Rand(wa.Top + 140, wa.Bottom - 20)); }
    PointF FarPt() {
        Rectangle wa = WA; float mid = wa.Left + wa.Width / 2f;
        float tx = x < mid ? Rand(wa.Left + wa.Width * 0.65f, wa.Right - 80) : Rand(wa.Left + 80, wa.Left + wa.Width * 0.35f);
        return new PointF(tx, Rand(wa.Top + 140, wa.Bottom - 20));
    }
    float MischiefDelay() { float b = 30 - (cfg.Chaos - 1) * 3f; return Rand(b * 0.6f, b * 1.4f); }

    static PointF HeadLocal(float n) { return new PointF(20 + 16 * n, -58 + 22 * n); }
    PointF BeakLocal() { PointF h = HeadLocal(neck); return new PointF(h.X + 15, h.Y + 3); }
    PointF BeakTip() { PointF b = BeakLocal(); return new PointF(x + b.X * S * dir, y + b.Y * S); }
    float BladeLen { get { return cfg.Fernrel ? 55 : 40; } }   // Fernrel carries a rapier
    PointF KnifeLocal() { PointF h = HeadLocal(neck); return new PointF(h.X + BladeLen, h.Y + 3.5f); }
    PointF KnifeTip() { PointF k = KnifeLocal(); return new PointF(x + k.X * S * dir, y + k.Y * S); }

    void SetState(string s, float t) {
        state = s; stateT = 0; timerT = t;
        if (s == "wander") target = RandPt();
    }

    void Say(string text, float secs) { say = text; sayT = secs; }

    // Moods: honk (plain), angry (fast, high, raspy, repeated), happy (rises at the end),
    // sleepy (low and slow), sad (long droop). Never the same recording twice in a row.
    byte[] PickSound(string kind) {
        List<byte[]> bank = honks[kind];
        int i = rng.Next(bank.Count);
        if (bank.Count > 1 && i == lastHonk) i = (i + 1) % bank.Count;
        lastHonk = i;
        return bank[i];
    }

    // One sound at a time per process, so combos (clang + honk) are mixed into one clip
    void PlayWav(byte[] wav) { if (cfg.Volume > 0) try { new SoundPlayer(new MemoryStream(wav)).Play(); } catch { } }

    void Honk(string mood) {
        byte[] wav = PickSound(mood);
        flapT = Math.Max(0.3f, (wav.Length - 44) / 2f / HonkRate);
        string line = mood == "angry" ? "HONK!!" : mood == "happy" ? "honk honk!" : mood == "sleepy" ? "hnnk\u2026" : mood == "sad" ? "honk\u2026" : "HONK!";
        if (cfg.Fernrel && rng.NextDouble() < 0.35) Say(FernrelQuotes[rng.Next(FernrelQuotes.Length)], 2.4f);
        else Say(line, flapT + 0.3f);
        PlayWav(wav);
    }

    bool FullscreenAppActive() {
        IntPtr f = GooseNative.GetForegroundWindow();
        if (f == IntPtr.Zero) return false;
        string c = GooseNative.ClassOf(f);
        if (c == "Progman" || c == "WorkerW") return false;
        Rectangle r = GooseNative.RectOf(f), b = Screen.FromHandle(f).Bounds;
        return r.Left <= b.Left && r.Top <= b.Top && r.Right >= b.Right && r.Bottom >= b.Bottom;
    }

    // A normal, visible, un-maximized app window near the top of the z-order
    IntPtr PickWindow() {
        List<IntPtr> found = new List<IntPtr>();
        uint me = (uint)Process.GetCurrentProcess().Id;
        Rectangle vs = SystemInformation.VirtualScreen;
        GooseNative.EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (found.Count >= 5) return false;
            if (!GooseNative.IsWindowVisible(h) || GooseNative.IsIconic(h) || GooseNative.IsZoomed(h)) return true;
            if (GooseNative.GetWindowTextLength(h) == 0 || GooseNative.GetWindow(h, 4) != IntPtr.Zero) return true;
            int ex = GooseNative.GetWindowLong(h, -20);
            if ((ex & 0x80) != 0 || (ex & 0x8) != 0) return true;          // tool windows, always-on-top windows
            uint pid; GooseNative.GetWindowThreadProcessId(h, out pid);
            if (pid == me) return true;
            int cloaked;
            if (GooseNative.DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
            string c = GooseNative.ClassOf(h);
            if (c == "Progman" || c == "WorkerW" || c.StartsWith("Shell_")) return true;
            Rectangle r = GooseNative.RectOf(h);
            if (r.Width < 250 || r.Height < 150 || !vs.Contains(new Point(r.Left + 60, r.Top + 12))) return true;
            found.Add(h);
            return true;
        }, IntPtr.Zero);
        return found.Count == 0 ? IntPtr.Zero : found[rng.Next(found.Count)];
    }

    bool WindowStillGrabbable() {
        return GooseNative.IsWindow(win) && GooseNative.IsWindowVisible(win) && !GooseNative.IsIconic(win) && !GooseNative.IsZoomed(win);
    }

    string NextNoteText() {
        List<string> pool = new List<string>();
        try { foreach (string l in File.ReadAllLines(GooseSettings.NotesPath)) if (l.Trim().Length > 0) pool.Add(l.Trim()); } catch { }
        if (pool.Count == 0) pool.AddRange(GooseSettings.DefaultNotes);
        if (cfg.Fernrel) pool.AddRange(FernrelNotes);
        return pool[rng.Next(pool.Count)];
    }

    void PlaceNote(NoteForm n) {
        PointF b = BeakTip();
        n.Location = new Point(dir == 1 ? (int)b.X - 8 : (int)b.X - n.Width + 8, (int)b.Y - 10);
    }

    void PickMischief() {
        List<string> opts = new List<string>();
        IntPtr w = IntPtr.Zero;
        if (!cfg.WorkMode && !FullscreenAppActive()) {
            if (cfg.StealCursor) opts.Add("chase");
            if (cfg.FetchNotes) opts.Add("notego");
            if (cfg.DragWindows) { w = PickWindow(); if (w != IntPtr.Zero) opts.Add("wingo"); }
            if (cfg.Knife && cfg.StabScreen) opts.Add("stab");
            if (cfg.Knife && cfg.Swordfight) opts.Add("duel");
            if (cfg.OpenTabs) { IntPtr f = FirefoxForeground(); if (f != IntPtr.Zero) { fox = f; opts.Add("tab"); opts.Add("tab"); } }
        }
        if (opts.Count == 0 || rng.NextDouble() < 0.2) { SetState("wander", MischiefDelay()); return; }
        string pick = opts[rng.Next(opts.Count)];
        if (pick == "chase") { stepped = false; Honk("angry"); SetState("chase", 0); }
        else if (pick == "notego") {
            Rectangle wa = WA; bool left = rng.Next(2) == 0;
            SetState("notego", 0);
            target = new PointF(left ? wa.Left + 50 : wa.Right - 50, Rand(wa.Top + 160, wa.Bottom - 60));
        } else if (pick == "stab") StartStab();
        else if (pick == "duel") StartDuel();
        else if (pick == "tab") { tabsLeft = rng.Next(1, 4); StartTabLookup(0); }
        else { win = w; SetState("wingo", 0); }
    }

    IntPtr FirefoxForeground() {
        IntPtr f = GooseNative.GetForegroundWindow();
        if (f == IntPtr.Zero || GooseNative.IsIconic(f) || GooseNative.ClassOf(f) != "MozillaWindowClass") return IntPtr.Zero;
        try {
            uint pid; GooseNative.GetWindowThreadProcessId(f, out pid);
            if (!Process.GetProcessById((int)pid).ProcessName.Equals("firefox", StringComparison.OrdinalIgnoreCase)) return IntPtr.Zero;
        } catch { return IntPtr.Zero; }
        return f;
    }

    void StartTabLookup(float delay) { SetState("tablook", delay); lookupStarted = false; lookupDone = false; tabButton = null; }

    // Breadth-first walk of Firefox's UI, skipping web page content, for the "+" (new tab) button.
    public static AutomationElement FindNewTabButton(IntPtr hwnd) {
        TreeWalker walker = TreeWalker.RawViewWalker;
        Queue<KeyValuePair<AutomationElement, int>> q = new Queue<KeyValuePair<AutomationElement, int>>();
        q.Enqueue(new KeyValuePair<AutomationElement, int>(AutomationElement.FromHandle(hwnd), 0));
        int seen = 0;
        while (q.Count > 0 && seen < 800) {
            KeyValuePair<AutomationElement, int> kv = q.Dequeue();
            AutomationElement c = walker.GetFirstChild(kv.Key);
            while (c != null && seen < 800) {
                seen++;
                ControlType ct = c.Current.ControlType;
                if (ct == ControlType.Button) {
                    // tabs-newtab-button sits after the last tab; new-tab-button replaces it when tabs overflow
                    string id = c.Current.AutomationId ?? "";
                    if ((id == "tabs-newtab-button" || id == "new-tab-button") && !c.Current.IsOffscreen) return c;
                }
                if (ct != ControlType.Document && kv.Value < 10) q.Enqueue(new KeyValuePair<AutomationElement, int>(c, kv.Value + 1));
                c = walker.GetNextSibling(c);
            }
        }
        return null;
    }

    // Firefox's UI Automation bridge can't press buttons, but its MSAA tree can ("default action")
    public static Accessibility.IAccessible FindNewTabAcc(IntPtr hwnd) {
        Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
        object root;
        if (GooseNative.AccessibleObjectFromWindow(hwnd, 0xFFFFFFFC, ref iid, out root) != 0) return null;  // OBJID_CLIENT
        Queue<KeyValuePair<Accessibility.IAccessible, int>> q = new Queue<KeyValuePair<Accessibility.IAccessible, int>>();
        q.Enqueue(new KeyValuePair<Accessibility.IAccessible, int>((Accessibility.IAccessible)root, 0));
        int seen = 0;
        while (q.Count > 0 && seen < 800) {
            KeyValuePair<Accessibility.IAccessible, int> kv = q.Dequeue();
            int n; try { n = kv.Key.accChildCount; } catch { continue; }
            if (n <= 0) continue;
            object[] kids = new object[n]; int got;
            if (GooseNative.AccessibleChildren(kv.Key, 0, n, kids, out got) != 0) continue;
            for (int i = 0; i < got; i++) {
                Accessibility.IAccessible a = kids[i] as Accessibility.IAccessible;
                if (a == null) continue;
                seen++;
                string name = null; object role = null;
                try { name = a.get_accName(0); role = a.get_accRole(0); } catch { }
                bool isButton = role is int && (int)role == 0x2B;    // ROLE_SYSTEM_PUSHBUTTON
                bool isPage = role is int && (int)role == 0x0F;      // ROLE_SYSTEM_DOCUMENT
                if (isButton && name != null && name.StartsWith("Open a new tab", StringComparison.OrdinalIgnoreCase)) return a;
                if (!isPage && kv.Value < 14) q.Enqueue(new KeyValuePair<Accessibility.IAccessible, int>(a, kv.Value + 1));
            }
        }
        return null;
    }

    // A fresh tab's window title is just "Mozilla Firefox" (or starts with "New Tab")
    static bool IsNewTab(IntPtr h) {
        string t = GooseNative.TitleOf(h);
        return t == "Mozilla Firefox" || t.StartsWith("New Tab");
    }

    string MakeGibberish() {
        StringBuilder sb = new StringBuilder();
        int len = rng.Next(14, 32);
        const string keys = "asdfghjklqwertyuiopzxcvbnm";
        while (sb.Length < len) {
            if (rng.NextDouble() < 0.6) sb.Append(GibBits[rng.Next(GibBits.Length)]);
            else for (int i = rng.Next(3, 7); i > 0; i--) sb.Append(keys[rng.Next(keys.Length)]);
            if (rng.NextDouble() < 0.6) sb.Append(' ');
        }
        return sb.ToString().TrimEnd();
    }

    // Types one character at a time on a worker thread. Stops if Firefox loses focus,
    // the tab stops being new, or you press a key. Only ever sets text; never presses Enter.
    void StartTyping() {
        string text = MakeGibberish();
        gibText = text; typedLen = 0; lastTyped = 0; typingDone = false; abortTyping = false;
        AutomationElement bar = urlbar; IntPtr h = fox;
        System.Threading.ThreadPool.QueueUserWorkItem(delegate {
            try {
                object p;
                if (!bar.TryGetCurrentPattern(ValuePattern.Pattern, out p)) { GooseSettings.Log("Address bar can't be typed into"); return; }
                ValuePattern vp = (ValuePattern)p;
                Random r = new Random();
                for (int i = 1; i <= text.Length; i++) {
                    if (abortTyping || GooseNative.GetForegroundWindow() != h || !IsNewTab(h)) break;
                    vp.SetValue(text.Substring(0, i));
                    typedLen = i;
                    System.Threading.Thread.Sleep(r.Next(60, 220));
                }
            } catch (Exception ex) { GooseSettings.Log("gibberish: " + ex); }
            finally { typingDone = true; }
        });
    }

    // Press whatever button is under the arrow's center through MSAA (no mouse involved)
    void PressGoArrow() {
        Rectangle r = goRect; IntPtr h = fox;
        System.Threading.ThreadPool.QueueUserWorkItem(delegate {
            try {
                if (GooseNative.GetForegroundWindow() != h) return;
                GooseNative.POINT pt = new GooseNative.POINT { X = r.Left + r.Width / 2, Y = r.Top + r.Height / 2 };
                Accessibility.IAccessible a; object child;
                if (GooseNative.AccessibleObjectFromPoint(pt, out a, out child) != 0 || a == null) { GooseSettings.Log("Nothing under the go arrow"); return; }
                object role = a.get_accRole(child);
                if (role is int && (int)role == 0x2B) a.accDoDefaultAction(child);   // ROLE_SYSTEM_PUSHBUTTON
                else GooseSettings.Log("Thing under the go arrow isn't a button: " + a.get_accName(child));
            } catch (Exception ex) { GooseSettings.Log("go arrow: " + ex); }
        });
    }

    // Fallback when the arrow isn't showing. Only fires if Firefox is in front with the address bar focused.
    void PressEnterInUrlbar() {
        IntPtr h = fox;
        System.Threading.ThreadPool.QueueUserWorkItem(delegate {
            try {
                if (GooseNative.GetForegroundWindow() != h) return;
                AutomationElement f = AutomationElement.FocusedElement;
                if (f == null || f.Current.AutomationId != "urlbar-input") { GooseSettings.Log("Didn't press Enter: address bar isn't focused"); return; }
                GooseNative.keybd_event(0x0D, 0, 0, UIntPtr.Zero);
                GooseNative.keybd_event(0x0D, 0, 2, UIntPtr.Zero);
            } catch (Exception ex) { GooseSettings.Log("enter: " + ex); }
        });
    }

    void PressTabButton() {
        IntPtr h = fox;
        System.Threading.ThreadPool.QueueUserWorkItem(delegate {
            try {
                Accessibility.IAccessible a = FindNewTabAcc(h);
                if (a != null) a.accDoDefaultAction(0);
                else GooseSettings.Log("Couldn't find Firefox's new-tab button to press");
            } catch (Exception ex) { GooseSettings.Log("tab press: " + ex); }
        });
    }

    void StartStab() {
        Rectangle wa = WA;
        stabSpot = new PointF(Rand(wa.Left + 140, wa.Right - 140), Rand(wa.Top + 140, wa.Bottom - 140));
        SetState("stabgo", 0);
    }

    void StartDance() {
        SetState("dance", 0);
        danceBeat = 0; danceEncore = false;
        Honk("happy");
        Say(cfg.Fernrel ? "Natural 20!" : "Victory!", 2.8f);
    }

    void StartDuel() {
        duelHits = 0; parries = 0; lungeT = 0; lungeCd = 1;
        Honk("angry");
        Say(cfg.Fernrel ? "Draw your blade!" : "En garde!", 1.5f);
        SetState("duel", Rand(7, 11));
    }

    // Challenge it any time with Ctrl+Shift+F, or by writing "duel" to command.txt in the settings folder (needs Knife on)
    void Challenge() {
        if (state == "heist" || state == "windrag") return;
        if (!cfg.Knife) { Honk("sad"); Say("No sword, no duel.", 1.5f); return; }
        if (sleeping) { sleeping = false; typingSince = clock.Elapsed.TotalSeconds; }
        if (carried != null) carried = null;
        StartDuel();
    }

    void Done(float calm) { SetState("wander", calm < 0 ? MischiefDelay() : calm); }

    // ---------- the loop ----------
    void Tick() {
        double now = clock.Elapsed.TotalSeconds;
        float dt = (float)Math.Min(0.05, now - lastTick);
        lastTick = now;

        bool ctrlShift = GooseNative.Down(0x11) && GooseNative.Down(0x10);
        if (ctrlShift && GooseNative.Down(0x47)) { Close(); return; } // Ctrl+Shift+G
        bool fightKey = ctrlShift && GooseNative.Down(0x46);           // Ctrl+Shift+F
        if (fightKey && !fightKeyWasDown) Challenge();
        fightKeyWasDown = fightKey;
        cmdCheckT -= dt;
        if (cmdCheckT <= 0) {
            cmdCheckT = 0.5f;
            string cmd = Path.Combine(GooseSettings.Dir, "command.txt");
            try {
                if (File.Exists(cmd)) {
                    string c = File.ReadAllText(cmd).Trim().ToLower();
                    File.Delete(cmd);
                    if (c == "duel" || c == "fight") Challenge();
                    else if ((c == "steal" || c == "chase") && cfg.StealCursor && state != "heist" && state != "windrag") { sleeping = false; carried = null; stepped = false; Honk("angry"); SetState("chase", 0); }
                    else if (c == "dance" && !sleeping && state != "heist" && state != "windrag") { carried = null; StartDance(); }
                    else if (c == "stab" && state != "heist" && state != "windrag") { sleeping = false; carried = null; StartStab(); }
                }
            } catch (Exception ex) { GooseSettings.Log("command: " + ex); }
        }
        bool settingsKey = ctrlShift && GooseNative.Down(0x4F);        // Ctrl+Shift+O
        if (settingsKey && !settingsKeyWasDown) OpenSettings();
        settingsKeyWasDown = settingsKey;

        stateT += dt; timerT -= dt;
        flapT = Math.Max(0, flapT - dt); sayT = Math.Max(0, sayT - dt);
        sparkleT = Math.Max(0, sparkleT - dt); zapT = Math.Max(0, zapT - dt); peckT = Math.Max(0, peckT - dt);

        // Typing: a run of keys with no gap longer than 2.5s
        if (GooseNative.AnyKey()) { if (now - lastKeyAt > 2.5) typingSince = now; lastKeyAt = now; }
        bool typing = now - lastKeyAt < 2.5;
        if (!sleeping && cfg.SleepWhenTyping && typing && now - typingSince > 12 && state != "heist" && state != "windrag") {
            sleeping = true; carried = null; vx = vy = 0; snoreT = 1.5f; SetState("sleep", 0);
            if (cfg.Fernrel) Say("Astral Trance\u2026", 2.5f);
        }
        if (sleeping) {
            if (!cfg.SleepWhenTyping || now - lastKeyAt > 8) { sleeping = false; Honk("sleepy"); Done(Rand(3, 6)); }
            else {
                snoreT -= dt;
                if (cfg.SnoreSounds && cfg.Volume > 0 && snoreT <= 0) { snores.Play(rng); snoreT = Rand(3f, 3.8f); }
                Place(); return;
            }
        }

        if (cfg.Fernrel) {
            nextZap -= dt;
            if (nextZap <= 0) { zapT = 0.6f; Say("The ring is glowing purple\u2026", 2.2f); nextZap = Rand(30, 60); }
        }

        Point m = Cursor.Position;
        mouseSpeed = mouseSpeed * 0.5f + Dist(m.X, m.Y, lastMouse.X, lastMouse.Y) / Math.Max(dt, 0.001f) * 0.5f;
        lastMouse = m;
        lungeCd -= dt; parryCd -= dt; sparkT = Math.Max(0, sparkT - dt);
        bool buttons = GooseNative.AnyMouseButton();
        float speed = 90, neckT = 0;
        bool aimBeak = false, aimKnife = false;

        switch (state) {
            case "wander":
                if (Dist(x, y, target.X, target.Y) < 15) target = RandPt();
                if (timerT <= 0) PickMischief();
                break;

            case "chase": {
                speed = 300; neckT = 1; aimBeak = true;
                target = new PointF(m.X, m.Y);
                if (!cfg.StealCursor || stateT > 8) { Honk("sad"); Done(-1); break; }
                if (cfg.Fernrel && !stepped && stateT > 1 && Dist(x, y, m.X, m.Y) > 350) {
                    // Starlight Step: teleport next to the prey
                    stepped = true; sparkleT = 0.7f; vx = vy = 0;
                    x = m.X + (x < m.X ? -150 : 150); y = m.Y + 70;
                    Say("Starlight Step!", 1.5f);
                }
                PointF b = BeakTip();
                if (!buttons && Dist(b.X, b.Y, m.X, m.Y) < 22) { Honk("angry"); SetState("heist", 0); target = FarPt(); }
                break;
            }

            case "heist":
                speed = 320; neckT = 0.3f;
                if (buttons) { Honk("angry"); Done(-1); }
                break;

            case "notego":
                speed = 170;
                if (Dist(x, y, target.X, target.Y) < 20) {
                    NoteForm n = new NoteForm(NextNoteText());
                    n.FormClosed += delegate { notes.Remove(n); };
                    PlaceNote(n); n.Show(); GooseNative.KeepOnTop(Handle);
                    notes.Add(n); carried = n;
                    if (notes.Count > 5) notes[0].Close();
                    SetState("notecarry", 0);
                    Rectangle wa = WA;
                    target = new PointF(Rand(wa.Left + wa.Width * 0.3f, wa.Right - wa.Width * 0.3f), Rand(wa.Top + 160, wa.Bottom - 80));
                } else if (stateT > 15) Done(-1);
                break;

            case "notecarry":
                speed = 110; neckT = 0.5f;
                if (carried == null || carried.IsDisposed || carried.Held) { carried = null; Honk("angry"); Done(-1); }
                else if (Dist(x, y, target.X, target.Y) < 15 || stateT > 12) { carried = null; Honk("happy"); Done(-1); }
                break;

            case "wingo": {
                speed = 170; neckT = 0.6f; aimBeak = true;
                if (!WindowStillGrabbable() || stateT > 10) { Done(-1); break; }
                Rectangle r = GooseNative.RectOf(win);
                target = new PointF(r.Left + Math.Min(120, r.Width / 3), r.Top + 12);
                PointF b = BeakTip();
                if (!buttons && Dist(b.X, b.Y, target.X, target.Y) < 22) {
                    grabOff = new Point((int)b.X - r.Left, (int)b.Y - r.Top);
                    dragDir = dir; Honk("honk");
                    SetState("windrag", 0);
                    target = new PointF(x - dragDir * Rand(180, 360), y + Rand(-80, 80));
                }
                break;
            }

            case "windrag":
                speed = 110; neckT = 0.6f;
                if (buttons || !WindowStillGrabbable()) { Honk("sad"); Done(-1); }
                break;

            case "tablook":
                if (Dist(x, y, target.X, target.Y) < 15) target = RandPt();
                if (FirefoxForeground() != fox) { Done(-1); break; }
                if (!lookupStarted && timerT <= 0) {
                    lookupStarted = true;
                    IntPtr h = fox;
                    System.Threading.ThreadPool.QueueUserWorkItem(delegate {
                        AutomationElement el = null;
                        try {
                            el = FindNewTabButton(h);
                            if (el != null) {
                                System.Windows.Rect r = el.Current.BoundingRectangle;
                                tabRect = new Rectangle((int)r.X, (int)r.Y, (int)r.Width, (int)r.Height);
                            }
                        } catch (Exception ex) { el = null; GooseSettings.Log("tab lookup: " + ex); }
                        tabButton = el;
                        lookupDone = true;
                    });
                }
                if (lookupDone) {
                    if (tabButton != null && tabRect.Width > 0) { Honk("honk"); SetState("tabgo", 0); }
                    else Done(-1);
                } else if (stateT > 6) Done(-1);
                break;

            case "giblook":
                if (FirefoxForeground() != fox) { Done(-1); break; }
                if (!lookupStarted && timerT <= 0) {
                    lookupStarted = true;
                    IntPtr h = fox;
                    System.Threading.ThreadPool.QueueUserWorkItem(delegate {
                        AutomationElement el = null;
                        try {
                            if (IsNewTab(h)) {
                                el = AutomationElement.FromHandle(h).FindFirst(TreeScope.Descendants,
                                    new PropertyCondition(AutomationElement.AutomationIdProperty, "urlbar-input"));
                                if (el != null) {
                                    System.Windows.Rect r = el.Current.BoundingRectangle;
                                    urlRect = new Rectangle((int)r.X, (int)r.Y, (int)r.Width, (int)r.Height);
                                }
                            } else GooseSettings.Log("Skipped gibberish: tab doesn't look new (title '" + GooseNative.TitleOf(h) + "')");
                        } catch (Exception ex) { el = null; GooseSettings.Log("urlbar lookup: " + ex); }
                        urlbar = el;
                        lookupDone = true;
                    });
                }
                if (lookupDone) { if (urlbar != null && urlRect.Width > 0) SetState("gibgo", 0); else Done(-1); }
                else if (stateT > 5) Done(-1);
                break;

            case "gibgo": {
                speed = 200; neckT = 0.3f; aimBeak = true;
                target = new PointF(urlRect.Left + Math.Min(60, urlRect.Width / 4f), urlRect.Top + urlRect.Height / 2f);
                if (FirefoxForeground() != fox || stateT > 8) { Done(-1); break; }
                PointF b = BeakTip();
                if (Dist(b.X, b.Y, target.X, target.Y) < 14) { SetState("gibtype", 0); StartTyping(); }
                break;
            }

            case "gibtype": {
                speed = 0; neckT = 0.3f;
                int n = typedLen;
                if (n > 0 && n != lastTyped) { peckT = 0.1f; lastTyped = n; Say(gibText.Substring(0, n), 1f); }
                if (GooseNative.AnyKey() || FirefoxForeground() != fox) abortTyping = true;   // you take over, it stops
                if (typingDone || stateT > 15) {
                    bool finished = typingDone && typedLen == gibText.Length && !abortTyping;
                    abortTyping = true;
                    if (finished && cfg.SearchGibberish) { SetState("golook", 0.4f); lookupStarted = false; lookupDone = false; }
                    else { Honk("sad"); Done(-1); }
                }
                break;
            }

            case "golook":
                if (FirefoxForeground() != fox) { Done(-1); break; }
                if (!lookupStarted && timerT <= 0) {
                    lookupStarted = true;
                    IntPtr h = fox;
                    System.Threading.ThreadPool.QueueUserWorkItem(delegate {
                        Rectangle found = Rectangle.Empty;
                        try {
                            AutomationElement el = AutomationElement.FromHandle(h).FindFirst(TreeScope.Descendants,
                                new PropertyCondition(AutomationElement.AutomationIdProperty, "urlbar-go-button"));
                            if (el != null && !el.Current.IsOffscreen) {
                                System.Windows.Rect r = el.Current.BoundingRectangle;
                                found = new Rectangle((int)r.X, (int)r.Y, (int)r.Width, (int)r.Height);
                            }
                        } catch (Exception ex) { GooseSettings.Log("go-arrow lookup: " + ex); }
                        goRect = found;
                        lookupDone = true;
                    });
                }
                if (lookupDone) {
                    if (goRect.Width > 0) SetState("gogo", 0);
                    else { peckT = 0.3f; Honk("happy"); PressEnterInUrlbar(); Done(-1); }   // no arrow showing: hit Enter instead
                } else if (stateT > 5) Done(-1);
                break;

            case "gogo": {
                speed = 160; neckT = 0.3f; aimBeak = true;
                target = new PointF(goRect.Left + goRect.Width / 2f, goRect.Top + goRect.Height / 2f);
                if (FirefoxForeground() != fox || stateT > 8) { Done(-1); break; }
                PointF b = BeakTip();
                if (Dist(b.X, b.Y, target.X, target.Y) < 10) {
                    peckT = 0.3f; Honk("happy"); PressGoArrow();
                    if (cfg.Fernrel) Say("Primeval Awareness: searching\u2026", 2f);
                    Done(-1);
                }
                break;
            }

            case "stabgo": {
                speed = 150; neckT = 0.4f; aimKnife = true; target = stabSpot;
                PointF tip = KnifeTip();
                if (Dist(tip.X, tip.Y, stabSpot.X, stabSpot.Y) < 12) SetState("stabwind", 0);
                else if (stateT > 10) Done(-1);
                break;
            }

            case "stabwind":   // rear back and tremble
                speed = 0; neckT = -0.35f;
                if (stateT > 0.45f) SetState("stablunge", 0);
                break;

            case "stablunge":
                speed = 0; neckT = 1.35f;
                if (stateT > 0.09f) {
                    PointF tip = KnifeTip();
                    layer.AddCrack(tip.X, tip.Y);
                    PlayWav(Mix(PickSound("crack"), PickSound("angry"), 0.15));
                    flapT = 0.5f;
                    Say(cfg.Fernrel ? "Linxa'Kasendalor's Fang!" : "STAB!", 1.2f);
                    SetState("stabhold", 0);
                }
                break;

            case "stabhold":   // admire the damage
                speed = 0; neckT = 1.35f;
                if (stateT > 0.6f) Done(-1);
                break;

            case "duel": {
                // knife tip hovers just off the cursor, lunges now and then; swing the cursor through the blade to parry
                speed = 230; neckT = 0.4f; aimKnife = true;
                target = new PointF(m.X + (x < m.X ? -45 : 45), m.Y);
                PointF tip = KnifeTip();
                if (windT > 0) {
                    // the tell: rear back and tremble, giving you a moment to dodge
                    speed = 0; neckT = -0.1f; windT -= dt;
                    if (windT <= 0) {
                        lungeT = 0.18f;
                        float ddx = m.X - tip.X, ddy = m.Y - tip.Y, dd = Math.Max(1, (float)Math.Sqrt(ddx * ddx + ddy * ddy));
                        vx = ddx / dd * 700; vy = ddy / dd * 700;
                    }
                } else if (lungeT > 0) {
                    // dash the blade straight at the cursor
                    speed = 900; target = new PointF(m.X, m.Y); lungeT -= dt;
                    if (!buttons && Dist(tip.X, tip.Y, m.X, m.Y) < 24) {
                        layer.AddSlash(m.X, m.Y);
                        Rectangle vsr = SystemInformation.VirtualScreen;
                        GooseNative.SetCursorPos(Math.Max(vsr.Left + 5, Math.Min(vsr.Right - 5, m.X + dir * 80)),
                                                 Math.Max(vsr.Top + 5, Math.Min(vsr.Bottom - 5, m.Y + rng.Next(-30, 31))));
                        duelHits++; sparkT = 0.3f; flapT = 0.4f; lungeT = 0;
                        vx = -dir * 250;
                        PlayWav(Mix(PickSound("clash"), PickSound("happy"), 0.1));
                        string[] hits = { "Touch\u00e9!", "Got you!", "HONK!" };
                        Say(hits[rng.Next(hits.Length)] + " (" + duelHits + "/3)", 1.2f);
                        lungeCd = Rand(0.7f, 1.4f);
                    } else if (lungeT <= 0) lungeCd = Rand(0.5f, 1.1f);   // missed
                } else if (lungeCd <= 0 && Dist(tip.X, tip.Y, m.X, m.Y) < 90) windT = 0.25f;
                if (parryCd <= 0 && mouseSpeed > 1300 && Dist(tip.X, tip.Y, m.X, m.Y) < 45) {
                    parries++; parryCd = 0.4f; sparkT = 0.25f;
                    vx = -dir * 420; lungeT = 0; windT = 0; lungeCd = Rand(0.6f, 1.2f);
                    PlayWav(PickSound("clash"));
                    string[] parryLines = { "Parry!", "Hah!", "Clang!", "En garde!" };
                    Say(cfg.Fernrel ? "Slayer's Counter!" : parryLines[rng.Next(parryLines.Length)], 0.9f);
                }
                if (timerT <= 0 || duelHits >= 3 || parries >= 5) {
                    if (parries >= 5) { Honk("sad"); Say("I yield\u2026 for now.", 2f); }
                    else if (duelHits >= 3) { StartDance(); break; }
                    else { Honk("happy"); Say("A draw. HONK.", 1.6f); }
                    Done(-1);
                }
                break;
            }

            case "dance": {
                // hop on every beat, turning to face the other way, head bobbing; honk an encore halfway
                speed = 0;
                int beat = (int)(stateT / 0.3f);
                if (beat != danceBeat) {
                    danceBeat = beat; dir = -dir;
                    if (cfg.FootstepSounds && cfg.Volume > 0) steps.Play(rng);
                }
                neckT = beat % 2 == 0 ? -0.2f : 0.6f;
                danceHop = (float)Math.Abs(Math.Sin(stateT * Math.PI / 0.3)) * 14;
                if (!danceEncore && stateT > 1.4f) { danceEncore = true; Honk("happy"); Say("HONK HONK HONK!", 1.2f); }
                if (stateT > 2.8f) { danceHop = 0; Done(-1); }
                break;
            }

            case "tabgo": {
                // stretch up tall and peck the + button
                speed = 220; neckT = 0; aimBeak = true;
                target = new PointF(tabRect.Left + tabRect.Width / 2f, tabRect.Top + tabRect.Height / 2f);
                if (FirefoxForeground() != fox || stateT > 10) { Done(-1); break; }
                PointF b = BeakTip();
                if (peckT == 0 && Dist(b.X, b.Y, target.X, target.Y) < 12) {
                    peckT = 0.3f; Honk("honk"); PressTabButton();
                    if (--tabsLeft > 0) StartTabLookup(0.6f);   // the button slides right after each new tab
                    else if (cfg.TypeGibberish) { SetState("giblook", 0.8f); lookupStarted = false; lookupDone = false; urlbar = null; }
                    else Done(-1);
                }
                break;
            }
        }

        // Steer toward the target (with the beak, when that's what matters)
        float ax = target.X, ay = target.Y;
        if (aimBeak) { PointF bl = BeakLocal(); ax -= bl.X * S * dir; ay -= bl.Y * S; }
        if (aimKnife) { PointF kl = KnifeLocal(); ax -= kl.X * S * dir; ay -= kl.Y * S; }
        float dx = ax - x, dy = ay - y, d = (float)Math.Sqrt(dx * dx + dy * dy);
        float sp = speed * cfg.Speed / 100f;
        sp = d < 6 ? 0 : (d < 40 ? sp * d / 40 : sp);
        float tvx = d > 0 ? dx / d * sp : 0, tvy = d > 0 ? dy / d * sp : 0;
        float k = Math.Min(1, dt * 7);
        vx += (tvx - vx) * k; vy += (tvy - vy) * k;
        Rectangle vs = SystemInformation.VirtualScreen;
        x = Math.Max(vs.Left + 40, Math.Min(vs.Right - 40, x + vx * dt));
        float minY = state == "tabgo" || state == "gibgo" || state == "gibtype" || state == "gogo" ? vs.Top + 60 : vs.Top + 100;   // the tab strip sits at the very top
        y = Math.Max(minY, Math.Min(vs.Bottom - 5, y + vy * dt));
        if (state == "windrag") dir = dragDir;   // walks backwards, beak still on the title bar
        else if (state == "duel") dir = x < m.X ? 1 : -1;   // always face your cursor
        else if (state == "dance") { }                        // the dance sets its own facing
        else { float tx = target.X - x; if (tx > 18) dir = 1; else if (tx < -18) dir = -1; }
        float v = (float)Math.Sqrt(vx * vx + vy * vy);
        phase += v * dt * 0.13f;
        if (peckT > 0) neckT = 0.6f;
        bool fastNeck = state == "stabwind" || state == "stablunge" || state == "stabhold" || windT > 0;
        neck += (neckT - neck) * Math.Min(1, dt * (fastNeck ? 30 : 9));

        if (state == "heist") {
            PointF b = BeakTip();
            GooseNative.SetCursorPos((int)b.X, (int)b.Y);
            if (Dist(x, y, target.X, target.Y) < 20 || stateT > 3) { Honk("happy"); Done(Rand(10, 20)); }
        } else if (state == "windrag") {
            PointF b = BeakTip();
            Rectangle r = GooseNative.RectOf(win);
            int nl = Math.Max(vs.Left - r.Width + 120, Math.Min(vs.Right - 120, (int)b.X - grabOff.X));
            int nt = Math.Max(vs.Top, Math.Min(vs.Bottom - 60, (int)b.Y - grabOff.Y));
            GooseNative.SetWindowPos(win, IntPtr.Zero, nl, nt, 0, 0, 0x1 | 0x4 | 0x10); // NOSIZE | NOZORDER | NOACTIVATE
            if (Dist(x, y, target.X, target.Y) < 15 || stateT > 3.5) {
                Honk("happy");
                if (cfg.Fernrel) Say("Outlander. I don't do windows.", 2.4f);
                Done(-1);
            }
        }
        if (carried != null && !carried.IsDisposed) PlaceNote(carried);

        stepAcc += v * dt;
        if (stepAcc > 20) {
            stepAcc = 0; stepSide = -stepSide;
            if (cfg.FootstepSounds && cfg.Volume > 0 && v > 20) steps.Play(rng);
            if (cfg.Footprints && v > 20) {
                float a = (float)Math.Atan2(vy, vx);
                layer.Add(x + (float)Math.Cos(a + Math.PI / 2) * 5 * stepSide, y + (float)Math.Sin(a + Math.PI / 2) * 5 * stepSide, a);
            }
        }
        Place();
    }

    void BuildSfx() {
        if (cfg.Volume == sfxVolume) return;
        if (steps != null) steps.Dispose();
        if (snores != null) snores.Dispose();
        List<short[]> pats = new List<short[]>(), zs = new List<short[]>();
        for (int i = 0; i < 6; i++) pats.Add(Patter(rng, cfg.Volume));
        for (int i = 0; i < 3; i++) zs.Add(Snore(rng, cfg.Volume));
        steps = new SfxChannel(pats, HonkRate);
        snores = new SfxChannel(zs, HonkRate);
        sfxVolume = cfg.Volume;
    }

    static short[] ToShorts(double[] b, double peakLevel) {
        double peak = 1e-6;
        foreach (double v in b) peak = Math.Max(peak, Math.Abs(v));
        short[] o = new short[b.Length];
        for (int i = 0; i < b.Length; i++) o[i] = (short)(b[i] / peak * peakLevel * 32767);
        return o;
    }

    // One webbed foot: a soft slap and a smaller follow-through, ~45ms, kept quiet
    static short[] Patter(Random rng, int volume) {
        int n = (int)(0.045 * HonkRate);
        double[] b = new double[n];
        Biquad bp = new Biquad(R(rng, 1600, 2600), 1.4);
        for (int i = 0; i < n; i++) {
            double t = (double)i / HonkRate;
            double env = Math.Exp(-t / 0.006) + (t > 0.012 ? 0.35 * Math.Exp(-(t - 0.012) / 0.008) : 0);
            b[i] = bp.Run((rng.NextDouble() * 2 - 1) * env);
        }
        return ToShorts(b, 0.18 * volume / 100.0);
    }

    // A tiny snore: rattly inhale (noise fluttering ~28 times a second), pause, breathy exhale,
    // sometimes with a little whistle. Everything sits above ~400 Hz for small speakers.
    static short[] Snore(Random rng, int volume) {
        double inhale = R(rng, 1.1, 1.4), pause = 0.25, exhale = R(rng, 0.8, 1.0);
        int n = (int)((inhale + pause + exhale) * HonkRate);
        double[] b = new double[n];
        Biquad low = new Biquad(600, 1.0), mid = new Biquad(1200, 2.0), air = new Biquad(2500, 0.8);
        double flutter = R(rng, 24, 32), whistleF = R(rng, 1600, 1900);
        bool whistle = rng.NextDouble() < 0.35;
        for (int i = 0; i < n; i++) {
            double t = (double)i / HonkRate, noise = rng.NextDouble() * 2 - 1;
            if (t < inhale) {
                double p = t / inhale, rattle = 0.5 + 0.5 * Math.Sin(2 * Math.PI * flutter * t);
                b[i] = (low.Run(noise) + mid.Run(noise) * 0.6) * rattle * Math.Sin(Math.PI * p);
            } else if (t > inhale + pause) {
                double te = t - inhale - pause, p = te / exhale, env = Math.Pow(Math.Sin(Math.PI * p), 2);
                b[i] = air.Run(noise) * 0.45 * env;
                if (whistle) b[i] += Math.Sin(2 * Math.PI * (whistleF - 300 * p) * te) * 0.12 * env;
            }
        }
        return ToShorts(b, 0.22 * volume / 100.0);
    }

    void Place() {
        int shake = state == "stabwind" || windT > 0 ? rng.Next(-2, 3) : 0;
        Location = new Point((int)x - FX + shake, (int)y - FY);
        Invalidate();
    }

    // ---------- sound ----------
    const int HonkRate = 22050;

    class Biquad {   // RBJ band-pass, used as a vocal-tract formant
        double b0, b2, a1, a2, x1, x2, y1, y2;
        public Biquad(double f, double q) {
            double w = 2 * Math.PI * f / HonkRate, alpha = Math.Sin(w) / (2 * q), a0 = 1 + alpha;
            b0 = alpha / a0; b2 = -alpha / a0; a1 = -2 * Math.Cos(w) / a0; a2 = (1 - alpha) / a0;
        }
        public double Run(double x) {
            double y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2;
            x2 = x1; x1 = x; y2 = y1; y1 = y;
            return y;
        }
    }

    // One honk: pitch jumps up fast ("HAH"), then droops ("-onk"); rise/fall set the shape.
    // grit mixes in breath noise. Parts are strung together with gaps for double/triple honks.
    class HonkPart { public double F0, Dur, Rise, Fall, Grit, Gap; }

    static byte[] Synth(int volume, List<HonkPart> parts, Random rng) {
        List<double> buf = new List<double>();
        foreach (HonkPart hp in parts) {
            int n = (int)(hp.Dur * HonkRate);
            double ph = 0, jit = 0;
            Biquad f1 = new Biquad(950, 2.5), f2 = new Biquad(2400, 4), body = new Biquad(450, 1.2);
            for (int i = 0; i < n; i++) {
                double p = (double)i / n, t = (double)i / HonkRate;
                double contour = p < 0.18 ? 0.88 + (hp.Rise + 0.12) * (p / 0.18)
                                          : 1 + hp.Rise - (hp.Rise + hp.Fall) * ((p - 0.18) / 0.82);
                jit = jit * 0.995 + (rng.NextDouble() - 0.5) * 0.004;
                double f = hp.F0 * contour * (1 + 0.018 * Math.Sin(2 * Math.PI * 7 * t) + jit);
                ph += f / HonkRate;
                double frac = ph - Math.Floor(ph);
                double src = (2 * frac - 1) * 0.5 + (frac < 0.28 ? 1 : -0.4) * 0.5 + (rng.NextDouble() * 2 - 1) * hp.Grit;
                double v = f1.Run(src) + f2.Run(src) * 0.6 + body.Run(src) * 0.35;
                double env = Math.Min(1, t / 0.012) * (p > 0.65 ? Math.Pow(1 - (p - 0.65) / 0.35, 1.5) : 1);
                buf.Add(v * env);
            }
            for (int i = (int)(hp.Gap * HonkRate); i > 0; i--) buf.Add(0);
        }
        // Level by average loudness (RMS) so every mood sounds equally loud, without clipping
        double peak = 1e-6, sum = 0;
        foreach (double v in buf) { peak = Math.Max(peak, Math.Abs(v)); sum += v * v; }
        double rms = Math.Sqrt(sum / Math.Max(1, buf.Count)) + 1e-9;
        return ToWav(buf, Math.Min(0.22 * volume / 100.0 / rms, 0.95 / peak));
    }

    static byte[] ToWav(List<double> buf, double gain) {
        MemoryStream ms = new MemoryStream();
        BinaryWriter w = new BinaryWriter(ms);
        int bytes = buf.Count * 2;
        w.Write("RIFF".ToCharArray()); w.Write(36 + bytes); w.Write("WAVE".ToCharArray());
        w.Write("fmt ".ToCharArray()); w.Write(16); w.Write((short)1); w.Write((short)1);
        w.Write(HonkRate); w.Write(HonkRate * 2); w.Write((short)2); w.Write((short)16);
        w.Write("data".ToCharArray()); w.Write(bytes);
        foreach (double v in buf) w.Write((short)Math.Max(-32767, Math.Min(32767, v * gain * 32767)));
        return ms.ToArray();
    }

    static double R(Random rng, double a, double b) { return a + rng.NextDouble() * (b - a); }

    static byte[] PeakWav(List<double> buf, int volume) {
        double peak = 1e-6;
        foreach (double v in buf) peak = Math.Max(peak, Math.Abs(v));
        return ToWav(buf, 0.9 * volume / 100.0 / peak);
    }

    // Lays clip b over clip a starting at offset seconds
    static byte[] Mix(byte[] a, byte[] b, double offset) {
        int na = (a.Length - 44) / 2, nb = (b.Length - 44) / 2, off = (int)(offset * HonkRate);
        List<double> buf = new List<double>();
        for (int i = 0; i < Math.Max(na, off + nb); i++) {
            double v = 0; int j = i - off;
            if (i < na) v += BitConverter.ToInt16(a, 44 + i * 2) / 32767.0;
            if (j >= 0 && j < nb) v += BitConverter.ToInt16(b, 44 + j * 2) / 32767.0 * 0.8;
            buf.Add(v);
        }
        return ToWav(buf, 1.0);
    }

    // Blade on blade: a few inharmonic ringing partials over a sharp click
    static List<double> ClashSound(Random rng) {
        List<double> buf = new List<double>();
        double[] fr = { R(rng, 1900, 2300), R(rng, 3000, 3500), R(rng, 4500, 5200), R(rng, 6100, 7200) };
        double[] decay = { 7, 10, 15, 22 };
        for (int i = 0; i < (int)(0.4 * HonkRate); i++) {
            double t = (double)i / HonkRate, v = (rng.NextDouble() * 2 - 1) * Math.Exp(-180 * t) * 0.9;
            for (int k = 0; k < 4; k++) v += Math.Sin(2 * Math.PI * fr[k] * t) * Math.Exp(-decay[k] * t) / (1 + k * 0.5);
            buf.Add(v);
        }
        return buf;
    }

    // Glass: a bright hit, splintering crackles that thin out, and a few tinkles
    static List<double> CrackSound(Random rng) {
        int n = (int)(0.7 * HonkRate);
        double[] b = new double[n];
        for (int i = 0; i < n; i++) b[i] += (rng.NextDouble() * 2 - 1) * Math.Exp(-45.0 * i / HonkRate) * 0.9;
        for (int i = 0; i < n; i++) {
            if (rng.NextDouble() >= 0.012 * Math.Exp(-5.0 * i / HonkRate)) continue;
            double a = R(rng, 0.3, 1) * (rng.Next(2) == 0 ? 1 : -1);
            for (int j = 0; j < 30 && i + j < n; j++) b[i + j] += a * Math.Exp(-j / 4.0) * (j % 2 == 0 ? 1 : -1);
        }
        for (int k = rng.Next(5, 9); k > 0; k--) {
            int start = (int)(R(rng, 0.02, 0.45) * HonkRate);
            double f = R(rng, 2600, 6500), amp = R(rng, 0.15, 0.4);
            for (int j = 0; start + j < n; j++) b[start + j] += Math.Sin(2 * Math.PI * f * j / HonkRate) * Math.Exp(-35.0 * j / HonkRate) * amp;
        }
        List<double> buf = new List<double>(n);
        double prev = 0;
        foreach (double v in b) { buf.Add(v - 0.85 * prev); prev = v; }   // tilt toward the highs: crisp on small speakers
        return buf;
    }

    public static Dictionary<string, List<byte[]>> MakeHonkBank(int volume, Random rng) {
        Dictionary<string, List<byte[]>> bank = new Dictionary<string, List<byte[]>>();
        foreach (string mood in new string[] { "honk", "angry", "happy", "sleepy", "sad" }) {
            List<byte[]> list = new List<byte[]>();
            for (int v = 0; v < 5; v++) {
                List<HonkPart> parts = new List<HonkPart>();
                if (mood == "honk") {
                    double f0 = R(rng, 330, 430);
                    parts.Add(new HonkPart { F0 = f0, Dur = R(rng, 0.18, 0.28), Rise = R(rng, 0.12, 0.3), Fall = R(rng, 0.2, 0.4), Grit = R(rng, 0.08, 0.2), Gap = R(rng, 0.05, 0.09) });
                    if (rng.NextDouble() < 0.3)   // a quizzical second honk, a little higher
                        parts.Add(new HonkPart { F0 = f0 * R(rng, 1.05, 1.15), Dur = R(rng, 0.14, 0.2), Rise = 0.2, Fall = 0.1, Grit = 0.12 });
                } else if (mood == "angry") {
                    double f0 = R(rng, 440, 540);
                    for (int k = rng.Next(2, 4); k > 0; k--, f0 *= 1.04)
                        parts.Add(new HonkPart { F0 = f0, Dur = R(rng, 0.12, 0.17), Rise = R(rng, 0.3, 0.45), Fall = R(rng, 0.1, 0.2), Grit = R(rng, 0.3, 0.45), Gap = R(rng, 0.03, 0.06) });
                } else if (mood == "happy") {
                    double f0 = R(rng, 360, 420);
                    parts.Add(new HonkPart { F0 = f0, Dur = R(rng, 0.12, 0.16), Rise = 0.2, Fall = 0.15, Grit = 0.1, Gap = R(rng, 0.06, 0.09) });
                    parts.Add(new HonkPart { F0 = f0 * R(rng, 1.15, 1.25), Dur = R(rng, 0.16, 0.22), Rise = 0.15, Fall = -0.1, Grit = 0.1 });
                } else if (mood == "sleepy") {
                    // kept above ~280 Hz: small speakers barely play anything lower
                    parts.Add(new HonkPart { F0 = R(rng, 290, 330), Dur = R(rng, 0.45, 0.55), Rise = R(rng, 0.05, 0.1), Fall = R(rng, 0.2, 0.28), Grit = 0.15 });
                } else {   // sad
                    parts.Add(new HonkPart { F0 = R(rng, 310, 350), Dur = R(rng, 0.32, 0.42), Rise = 0.05, Fall = R(rng, 0.4, 0.5), Grit = 0.1 });
                }
                list.Add(Synth(volume, parts, rng));
            }
            bank[mood] = list;
        }
        List<byte[]> clashes = new List<byte[]>(), cracks = new List<byte[]>();
        for (int v = 0; v < 5; v++) clashes.Add(PeakWav(ClashSound(rng), volume));
        for (int v = 0; v < 3; v++) cracks.Add(PeakWav(CrackSound(rng), volume));
        bank["clash"] = clashes; bank["crack"] = cracks;
        return bank;
    }

    // ---------- drawing ----------
    static Pen RoundPen(Color c, float wdt) {
        Pen p = new Pen(c, wdt);
        p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
        return p;
    }

    static Icon MakeIcon() {
        Bitmap bmp = new Bitmap(32, 32);
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen ink = new Pen(Ink, 2)) using (Pen neckO = RoundPen(Ink, 7)) using (Pen neckI = RoundPen(Feather, 4))
            using (SolidBrush white = new SolidBrush(Feather)) using (SolidBrush beak = new SolidBrush(Beak)) using (SolidBrush inkB = new SolidBrush(Ink)) {
                g.DrawLine(neckO, 19, 18, 22, 9); g.DrawLine(neckI, 19, 18, 22, 9);
                g.FillEllipse(white, 3, 15, 22, 13); g.DrawEllipse(ink, 3, 15, 22, 13);
                g.FillEllipse(white, 17, 3, 10, 10); g.DrawEllipse(ink, 17, 3, 10, 10);
                g.FillPolygon(beak, new PointF[] { new PointF(26, 6), new PointF(31, 9), new PointF(26, 11) });
                g.FillEllipse(inkB, 22, 6, 2.5f, 2.5f);
            }
        }
        return Icon.FromHandle(bmp.GetHicon());
    }

    // No antialiasing on purpose: blended edges would pick up the magenta transparency key
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.None;
        g.TextRenderingHint = TextRenderingHint.SingleBitPerPixelGridFit;
        float moving = Math.Min(1f, (float)Math.Sqrt(vx * vx + vy * vy) / 40f);
        float sw = (float)Math.Sin(phase) * 6 * moving;
        float bob = -(float)Math.Abs(Math.Sin(phase)) * 1.6f * moving;
        bool fern = cfg.Fernrel;

        GraphicsState saved = g.Save();
        g.TranslateTransform(FX, FY + bob + (sleeping ? 12 : 0) - (state == "dance" ? danceHop : 0));
        g.ScaleTransform(S * dir, S);
        using (Pen legPen = RoundPen(Beak, 3.5f))
        using (Pen ink = RoundPen(Ink, 2.5f))
        using (Pen thin = RoundPen(Ink, 1.6f))
        using (Pen steel = RoundPen(Steel, 1.8f))
        using (Pen neckOut = RoundPen(Ink, 15))
        using (Pen neckIn = RoundPen(Feather, 10))
        using (SolidBrush beakB = new SolidBrush(Beak))
        using (SolidBrush feather = new SolidBrush(Feather))
        using (SolidBrush wing = new SolidBrush(Wing))
        using (SolidBrush inkB = new SolidBrush(Ink))
        using (SolidBrush hair = new SolidBrush(Hair))
        using (SolidBrush freckle = new SolidBrush(Freckle))
        using (SolidBrush plate = new SolidBrush(Plate))
        using (SolidBrush gem = new SolidBrush(Gem))
        using (SolidBrush eye = new SolidBrush(fern ? (zapT > 0 ? Storm : EyeGreen) : Ink))
        using (SolidBrush storm = new SolidBrush(Storm)) {
            if (!sleeping) {
                float[] hips = { -5, 5 }, feet = { -5 + sw, 5 - sw };
                for (int i = 0; i < 2; i++) {
                    g.DrawLine(legPen, hips[i], -14, feet[i], 0);
                    g.FillPolygon(beakB, new PointF[] { new PointF(feet[i] - 2, 0), new PointF(feet[i] + 8, 0), new PointF(feet[i] + 1, -3) });
                }
            }
            PointF[] tail = { new PointF(-17, -31), new PointF(-33, -37), new PointF(-22, -19) };
            g.FillPolygon(feather, tail); g.DrawPolygon(ink, tail);
            g.FillEllipse(feather, -24, -38, 48, 28); g.DrawEllipse(ink, -24, -38, 48, 28);
            g.FillEllipse(wing, -17, -32, 26, 14); g.DrawEllipse(thin, -17, -32, 26, 14);

            if (fern) {
                // twin rapiers on the hip (Linxa'Kasendalor's Fangs)
                for (int i = 0; i < 2; i++) {
                    float o = i * 4;
                    g.DrawLine(steel, -4 + o, -17 - o, -36 + o, -7 - o);
                    g.DrawLine(thin, -2 + o, -21 - o, -6 + o, -13 - o);
                }
                // white chest plate
                PointF[] chest = { new PointF(5, -35), new PointF(18, -32), new PointF(23, -24), new PointF(18, -15), new PointF(5, -13) };
                g.FillPolygon(plate, chest); g.DrawPolygon(thin, chest);
                // ring on the leg, glowing before the storm
                if (zapT > 0 && !sleeping) g.FillEllipse(storm, -8 + sw * 0.5f, -10, 6, 4);
            }

            PointF h;
            if (sleeping) {
                h = new PointF(10, -38);   // head tucked onto the back
            } else {
                h = HeadLocal(neck);
                PointF p0 = new PointF(14, -29), q = new PointF(16 + neck * 10, -44 + neck * 14);
                PointF c1 = new PointF(p0.X + 2f / 3 * (q.X - p0.X), p0.Y + 2f / 3 * (q.Y - p0.Y));
                PointF c2 = new PointF(h.X + 2f / 3 * (q.X - h.X), h.Y + 2f / 3 * (q.Y - h.Y));
                g.DrawBezier(neckOut, p0, c1, c2, h);
                g.DrawBezier(neckIn, p0, c1, c2, h);
            }
            if (fern) {
                // blue diamond gem at the collar
                PointF[] d = { new PointF(13, -32), new PointF(16.5f, -27), new PointF(13, -22), new PointF(9.5f, -27) };
                g.FillPolygon(gem, d); g.DrawPolygon(thin, d);
                // pointed elf ear, tucked behind the head
                PointF[] ear = { new PointF(h.X - 5, h.Y - 1), new PointF(h.X - 17, h.Y - 9), new PointF(h.X - 4, h.Y + 4) };
                g.FillPolygon(feather, ear); g.DrawPolygon(thin, ear);
            }
            g.FillEllipse(feather, h.X - 8.5f, h.Y - 8.5f, 17, 17); g.DrawEllipse(ink, h.X - 8.5f, h.Y - 8.5f, 17, 17);

            float open = flapT > 0 ? (Math.Sin(flapT * 40) > 0 ? 5 : 1) : 0;
            PointF[] upper = { new PointF(h.X + 5, h.Y - 3), new PointF(h.X + 16, h.Y + 2 - open * 0.3f), new PointF(h.X + 5, h.Y + 3) };
            PointF[] lower = { new PointF(h.X + 5, h.Y + 3), new PointF(h.X + 14, h.Y + 4 + open), new PointF(h.X + 5, h.Y + 6) };
            g.FillPolygon(beakB, upper); g.DrawPolygon(thin, upper);
            g.FillPolygon(beakB, lower); g.DrawPolygon(thin, lower);

            if (cfg.Knife && !sleeping) {
                // handle clamped crosswise in the beak, blade pointing forward
                float L = BladeLen;
                using (SolidBrush handle = new SolidBrush(fern ? Gem : KnifeHandle))
                using (SolidBrush blade = new SolidBrush(Blade))
                using (Pen guard = RoundPen(fern ? Gem : Steel, 2.2f)) {
                    g.FillRectangle(handle, h.X + 6, h.Y + 1.5f, 12, 4); g.DrawRectangle(thin, h.X + 6, h.Y + 1.5f, 12, 4);
                    PointF[] bl = fern
                        ? new PointF[] { new PointF(h.X + 19, h.Y + 2.4f), new PointF(h.X + L, h.Y + 3.5f), new PointF(h.X + 19, h.Y + 4.6f) }
                        : new PointF[] { new PointF(h.X + 19, h.Y + 1), new PointF(h.X + L, h.Y + 3.5f), new PointF(h.X + 19, h.Y + 6) };
                    g.FillPolygon(blade, bl); g.DrawPolygon(thin, bl);
                    g.DrawLine(guard, h.X + 18.5f, h.Y - 1.5f, h.X + 18.5f, h.Y + 8.5f);
                }
            }

            if (sleeping) g.DrawLine(thin, h.X, h.Y - 2, h.X + 4, h.Y - 1);
            else {
                g.FillEllipse(eye, h.X, h.Y - 4.2f, fern ? 4.4f : 3.8f, fern ? 4.4f : 3.8f);
                if (state != "wander" || flapT > 0) g.DrawLine(ink, h.X - 3, h.Y - 8, h.X + 5, h.Y - 5);
            }
            if (fern) {
                // brown hair tuft and freckles
                PointF[] tuft = { new PointF(h.X - 7, h.Y - 5), new PointF(h.X - 4, h.Y - 15), new PointF(h.X - 1, h.Y - 8),
                                  new PointF(h.X + 3, h.Y - 14), new PointF(h.X + 5, h.Y - 6) };
                g.FillPolygon(hair, tuft); g.DrawPolygon(thin, tuft);
                g.FillEllipse(freckle, h.X + 1, h.Y + 2, 1.6f, 1.6f);
                g.FillEllipse(freckle, h.X + 3.5f, h.Y + 3.2f, 1.6f, 1.6f);
                g.FillEllipse(freckle, h.X - 1.5f, h.Y + 3.4f, 1.6f, 1.6f);
            }
        }
        g.Restore(saved);

        float t = (float)clock.Elapsed.TotalSeconds;
        if (state == "dance") {
            // music notes floating up on either side
            using (SolidBrush noteB = new SolidBrush(Spark)) using (Pen inkP = new Pen(Ink, 2)) {
                for (int i = 0; i < 4; i++) {
                    float ph = (t * 0.7f + i * 0.25f) % 1f;
                    float nx = FX + (i % 2 == 0 ? -1 : 1) * (70 + i * 8) + (float)Math.Sin(t * 4 + i) * 6, ny = FY - 60 - ph * 70;
                    g.FillEllipse(noteB, nx, ny, 9, 7); g.DrawEllipse(inkP, nx, ny, 9, 7);
                    g.DrawLine(inkP, nx + 9, ny + 3, nx + 9, ny - 13);
                    g.DrawLine(inkP, nx + 9, ny - 13, nx + 15, ny - 8);
                }
            }
        }
        if (sparkT > 0) {
            PointF kl = KnifeLocal();
            float kx = FX + kl.X * S * dir, ky = FY + kl.Y * S;
            using (Pen spark = new Pen(Spark, 2)) using (Pen white = new Pen(Feather, 1.5f)) {
                for (int i = 0; i < 9; i++) {
                    double a = rng.NextDouble() * Math.PI * 2; float r1 = Rand(3, 6), r2 = Rand(10, 22);
                    g.DrawLine(i % 3 == 0 ? white : spark, kx + (float)Math.Cos(a) * r1, ky + (float)Math.Sin(a) * r1,
                                                           kx + (float)Math.Cos(a) * r2, ky + (float)Math.Sin(a) * r2);
                }
            }
        }
        if (zapT > 0) {
            // purple lightning crackling around the goose
            using (Pen bolt = new Pen(Storm, 2)) {
                for (int i = 0; i < 3; i++) {
                    float bx = FX + Rand(-60, 60), by = FY - 150;
                    PointF[] pts = new PointF[6];
                    for (int j = 0; j < 6; j++) { pts[j] = new PointF(bx, by); bx += Rand(-12, 12); by += 22; }
                    g.DrawLines(bolt, pts);
                }
            }
        }
        if (sparkleT > 0) {
            using (Pen star = new Pen(Gem, 2)) using (Pen star2 = new Pen(Storm, 2)) {
                for (int i = 0; i < 8; i++) {
                    double a = i * Math.PI / 4 + t * 3;
                    float r = 30 + (0.7f - sparkleT) * 80;
                    float sx = FX + (float)Math.Cos(a) * r, sy = FY - 40 + (float)Math.Sin(a) * r * 0.6f;
                    Pen p = i % 2 == 0 ? star : star2;
                    g.DrawLine(p, sx - 4, sy, sx + 4, sy); g.DrawLine(p, sx, sy - 4, sx, sy + 4);
                }
            }
        }
        if (sleeping) {
            using (SolidBrush inkB = new SolidBrush(Ink)) {
                for (int i = 0; i < 3; i++) {
                    float ph = ((t + i * 0.8f) % 2.4f) / 2.4f;
                    using (Font f = new Font("Arial Black", 9 + i * 3)) g.DrawString("z", f, inkB, FX + 20 + ph * 30, FY - 70 - ph * 60);
                }
            }
        }
        if (sayT > 0 && say != null) {
            using (Font f = new Font("Arial Black", say == "HONK!" ? 15 : 10.5f))
            using (SolidBrush inkB = new SolidBrush(Ink))
            using (SolidBrush paper = new SolidBrush(Feather))
            using (Pen border = new Pen(Ink, 2)) {
                SizeF sz = g.MeasureString(say, f);
                float bw = sz.Width + 16, bh = sz.Height + 8;
                PointF b = BeakLocal();
                float cx = FX + (sleeping ? 20 : b.X * S * dir + dir * 30);
                cx = Math.Max(bw / 2 + 4, Math.Min(WW - bw / 2 - 4, cx));
                float top = FY - 150;
                g.FillRectangle(paper, cx - bw / 2, top, bw, bh);
                g.DrawRectangle(border, cx - bw / 2, top, bw, bh);
                g.DrawString(say, f, inkB, cx - sz.Width / 2, top + 4);
            }
        }
    }
}
'@

if ($CheckOnly) { "Goose compiled OK"; return }

[GooseNative]::SetProcessDPIAware() | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode('CatchException')
[System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) [GooseSettings]::Log("Unhandled: " + $e.Exception) })
[System.Windows.Forms.Application]::Run((New-Object GooseForm))
