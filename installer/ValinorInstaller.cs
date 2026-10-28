using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Instalar Valinor Sanctum - Producción")]
[assembly: AssemblyProduct("Valinor Sanctum - Producción")]
[assembly: AssemblyVersion("__VERSION__.0")]

internal static class ValinorInstaller {
    const string Version = "__VERSION__";
    const string AppName = "Valinor Sanctum - Producción";
    const string ExeName = "valinor_sanctum_2.exe";
    const string RegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ValinorSanctum2";
    const string TestBoundary = @"__TEST_BOUNDARY__";
    static bool quiet;

    [STAThread]
    static int Main(string[] args) {
        Application.EnableVisualStyles();
        quiet = args.Contains("--quiet");
        try {
            string target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "ValinorSanctum2");
            int testIndex = Array.IndexOf(args, "--test-root");
            bool test = testIndex >= 0;
            if (test) {
                if (testIndex + 1 >= args.Length) throw new Exception("Falta la carpeta de prueba.");
                target = Path.GetFullPath(args[testIndex + 1]);
                if (!target.StartsWith(TestBoundary.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
                    throw new Exception("La prueba debe permanecer dentro de tmp del proyecto.");
            }
            ValidatePath(target);
            bool uninstall = args.Contains("--uninstall");
#if UNINSTALLER
            uninstall = true;
#endif
            if (uninstall) {
                if (!quiet && MessageBox.Show("¿Desinstalar " + AppName + "?\n\nLa base de datos de Documentos se conservará.", AppName,
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return 0;
                EnsureClosed(target);
                string self = Assembly.GetExecutingAssembly().Location;
                if (self.StartsWith(target + "\\", StringComparison.OrdinalIgnoreCase)) {
                    // Run outside the installation so Windows can remove every installed file.
                    string worker = Path.Combine(test ? Path.GetDirectoryName(target) : Path.GetTempPath(), "ValinorUninstall-" + Guid.NewGuid().ToString("N") + ".exe");
                    File.Copy(self, worker);
                    var start = new ProcessStartInfo(worker, "--uninstall --quiet --worker " + Process.GetCurrentProcess().Id +
                        (test ? " --test-root \"" + target + "\"" : ""));
                    start.UseShellExecute = false;
                    Process.Start(start);
                    return 0;
                }
                int workerIndex = Array.IndexOf(args, "--worker");
                if (workerIndex >= 0) {
                    try { Process.GetProcessById(int.Parse(args[workerIndex + 1])).WaitForExit(15000); }
                    catch (ArgumentException) { }
                }
                EnsureClosed(target);
                if (Directory.Exists(target)) {
                    ValidateTree(target);
                    EnsureNoDatabase(target);
                    Directory.Delete(target, true);
                }
                if (!test) {
                    DeleteShortcut(Environment.SpecialFolder.DesktopDirectory);
                    DeleteShortcut(Environment.SpecialFolder.Programs);
                    Registry.CurrentUser.DeleteSubKeyTree(RegistryPath, false);
                }
                if (!quiet) MessageBox.Show("Desinstalación completada. Tu base de datos se conserva en Documentos.", AppName);
                return 0;
            }

            if (!quiet && MessageBox.Show("Instalar " + AppName + " " + Version + " para este usuario.\n\n" +
                "Se crearán accesos en el escritorio y en Inicio.\n" +
                "La app usará Documentos\\sanctum2.sqlite3 y Documentos\\legacy-treasury.json.\n" +
                "Si falta la base, creará una vacía con Valinor, COP y 0 decimales.\n" +
                "La edición de desarrollo se conserva separada.\n\n¿Continuar?",
                AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return 0;
            EnsureClosed(target);
            string existing = Path.Combine(target, ExeName);
            if (File.Exists(existing) && new System.Version(FileVersionInfo.GetVersionInfo(existing).FileVersion.Split('+')[0]) > new System.Version(Version))
                throw new Exception("Ya está instalada una versión más reciente. No se permite retroceder.");
            if (Directory.Exists(target)) { ValidateTree(target); EnsureNoDatabase(target); }
            string stage = target + ".install-" + Guid.NewGuid().ToString("N");
            string previous = target + ".previous-" + Guid.NewGuid().ToString("N");
            ValidatePath(stage);
            Directory.CreateDirectory(stage);
            bool moved = false;
            try {
                using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("Payload.zip"))
                using (var archive = new ZipArchive(payload, ZipArchiveMode.Read)) {
                    long total = 0;
                    foreach (var entry in archive.Entries) {
                        string name = entry.FullName.Replace('\\', '/');
                        const string prefix = "ValinorSanctum2/";
                        if (!name.StartsWith(prefix, StringComparison.Ordinal)) throw new Exception("Paquete inválido.");
                        string relative = name.Substring(prefix.Length);
                        if (String.IsNullOrEmpty(relative)) continue;
                        string output = Path.GetFullPath(Path.Combine(stage, relative.Replace('/', '\\')));
                        if (!output.StartsWith(stage + "\\", StringComparison.OrdinalIgnoreCase) || relative.Contains(":"))
                            throw new Exception("Ruta de paquete inválida.");
                        total += entry.Length;
                        if (total > 512L * 1024 * 1024) throw new Exception("Paquete demasiado grande.");
                        if (name.EndsWith("/")) { Directory.CreateDirectory(output); continue; }
                        Directory.CreateDirectory(Path.GetDirectoryName(output));
                        entry.ExtractToFile(output);
                    }
                }
                foreach (string required in new[] { ExeName, "flutter_windows.dll", "sqlite3.dll", "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll", @"data\app.so", @"data\icudtl.dat" })
                    if (!File.Exists(Path.Combine(stage, required))) throw new Exception("Paquete incompleto: " + required);
                using (var source = Assembly.GetExecutingAssembly().GetManifestResourceStream("Uninstaller.exe"))
                using (var destination = File.Create(Path.Combine(stage, "Desinstalar.exe"))) source.CopyTo(destination);
                EnsureNoDatabase(stage);
                if (Directory.Exists(target)) { Directory.Move(target, previous); moved = true; }
                Directory.Move(stage, target);
                try {
                    if (!test) {
                        CreateShortcut(Environment.SpecialFolder.DesktopDirectory, target);
                        CreateShortcut(Environment.SpecialFolder.Programs, target);
                        using (var key = Registry.CurrentUser.CreateSubKey(RegistryPath)) {
                            key.SetValue("DisplayName", AppName);
                            key.SetValue("DisplayVersion", Version);
                            key.SetValue("Publisher", "Valinor");
                            key.SetValue("InstallLocation", target);
                            key.SetValue("DisplayIcon", Path.Combine(target, ExeName));
                            key.SetValue("UninstallString", "\"" + Path.Combine(target, "Desinstalar.exe") + "\"");
                            key.SetValue("QuietUninstallString", "\"" + Path.Combine(target, "Desinstalar.exe") + "\" --quiet");
                            key.SetValue("NoModify", 1);
                            key.SetValue("NoRepair", 1);
                        }
                    }
                } catch {
                    // Keep the old complete bundle if registration failed.
                    ValidateTree(target); Directory.Delete(target, true);
                    if (moved) Directory.Move(previous, target);
                    throw;
                }
                if (moved) { ValidateTree(previous); Directory.Delete(previous, true); }
            } catch {
                if (moved && !Directory.Exists(target) && Directory.Exists(previous)) Directory.Move(previous, target);
                throw;
            } finally {
                if (Directory.Exists(stage)) { ValidateTree(stage); Directory.Delete(stage, true); }
            }
            if (!quiet && MessageBox.Show("Instalación completada.\n\n¿Abrir " + AppName + "?", AppName,
                MessageBoxButtons.YesNo, MessageBoxIcon.Information) == DialogResult.Yes)
                Process.Start(new ProcessStartInfo(Path.Combine(target, ExeName)) { WorkingDirectory = target });
            return 0;
        } catch (Exception error) {
            if (!quiet) MessageBox.Show(error.Message, AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            else Console.Error.WriteLine(error);
            return 1;
        }
    }

    static void EnsureClosed(string target) {
        foreach (var process in Process.GetProcessesByName("valinor_sanctum_2")) {
            try {
                string path = process.MainModule.FileName;
                if (path.StartsWith(target + "\\", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Guarda lo pendiente y cierra Valinor Sanctum antes de instalar o desinstalar.");
            } catch (System.ComponentModel.Win32Exception) {
                throw new Exception("No se pudo comprobar si Valinor está abierto. Cierra la app y vuelve a intentar.");
            } finally { process.Dispose(); }
        }
    }
    static void ValidatePath(string path) {
        for (string current = Path.GetFullPath(path); !String.IsNullOrEmpty(current); current = Path.GetDirectoryName(current)) {
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new Exception("No se admiten enlaces en la carpeta de instalación.");
        }
    }
    static void ValidateTree(string path) {
        ValidatePath(path);
        foreach (string entry in Directory.GetFileSystemEntries(path)) {
            ValidatePath(entry);
            if (Directory.Exists(entry)) ValidateTree(entry);
        }
    }
    static void EnsureNoDatabase(string path) {
        foreach (string file in Directory.GetFiles(path, "*", SearchOption.AllDirectories)) {
            string lower = Path.GetFileName(file).ToLowerInvariant();
            if (lower.EndsWith(".db") || lower.Contains(".db-") || lower.Contains(".sqlite") ||
                lower == "active-workspace.json" || lower == "reference-inventory.json" || lower == "legacy-treasury.json")
                throw new Exception("Hay datos en la carpeta del programa. Se conserva para revisión; no se reemplazará ni eliminará.");
        }
    }
    static string ShortcutPath(Environment.SpecialFolder folder) {
        return Path.Combine(Environment.GetFolderPath(folder), AppName + ".lnk");
    }
    static void CreateShortcut(Environment.SpecialFolder folder, string target) {
        dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
        dynamic shortcut = shell.CreateShortcut(ShortcutPath(folder));
        shortcut.TargetPath = Path.Combine(target, ExeName);
        shortcut.WorkingDirectory = target;
        shortcut.IconLocation = Path.Combine(target, ExeName) + ",0";
        shortcut.Description = AppName;
        shortcut.Save();
        // Rename only this installation's old generic shortcut, never a dev launcher.
        string legacyPath = Path.Combine(Environment.GetFolderPath(folder), "Valinor Sanctum 2.0.lnk");
        if (File.Exists(legacyPath)) {
            dynamic legacyShortcut = shell.CreateShortcut(legacyPath);
            string legacyTarget = legacyShortcut.TargetPath;
            if (!String.IsNullOrEmpty(legacyTarget) && String.Equals(Path.GetFullPath(legacyTarget),
                Path.Combine(target, ExeName), StringComparison.OrdinalIgnoreCase)) File.Delete(legacyPath);
        }
    }
    static void DeleteShortcut(Environment.SpecialFolder folder) {
        string path = ShortcutPath(folder);
        if (File.Exists(path)) File.Delete(path);
    }
}
