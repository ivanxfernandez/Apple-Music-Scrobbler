using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// One-click updates: downloads the new exe next to the running one, checks it against the
    /// SHA-256 GitHub publishes, swaps it in and restarts. Windows lets a running exe be renamed
    /// (not deleted), so the old one becomes AppleMusicScrobbler.exe.old and is deleted by the new
    /// version once this process has exited. When anything doesn't check out, nothing changes and the
    /// release page opens instead.
    /// </summary>
    static class Updater
    {
        static string ExePath => Application.ExecutablePath;
        static string NewPath => ExePath + ".new";
        static string OldPath => ExePath + ".old";

        /// <summary>Null if the app can replace itself, otherwise why not.</summary>
        public static string CannotInstallReason()
        {
            try
            {
                // Probe the folder for write access (e.g. not under Program Files).
                string probe = Path.Combine(Path.GetDirectoryName(ExePath), ".write-test-" + Guid.NewGuid().ToString("N"));
                File.WriteAllText(probe, "");
                File.Delete(probe);
                return null;
            }
            catch (Exception)
            {
                return "it doesn't have permission to replace its exe in " + Path.GetDirectoryName(ExePath);
            }
        }

        /// <summary>Downloads, checks and swaps in the release, then starts it and exits. Throws if anything fails (nothing is changed then).</summary>
        public static async Task InstallAsync(ReleaseInfo release)
        {
            if (string.IsNullOrEmpty(release.DownloadUrl) || string.IsNullOrEmpty(release.Sha256))
                throw new InvalidOperationException("this release has no checked download for Windows");

            Log.Write($"Downloading {release.Tag}...");
            TryDelete(NewPath);
            using (var response = await Http.Client.GetAsync(release.DownloadUrl, System.Net.Http.HttpCompletionOption.ResponseHeadersRead))
            {
                response.EnsureSuccessStatusCode();
                using (var file = File.Create(NewPath))
                    await response.Content.CopyToAsync(file);
            }

            try
            {
                string hash;
                using (var sha = SHA256.Create())
                using (var file = File.OpenRead(NewPath))
                    hash = string.Concat(sha.ComputeHash(file).Select(b => b.ToString("x2")));
                if (hash != release.Sha256) throw new InvalidOperationException("the download doesn't match the published SHA-256");

                var name = AssemblyName.GetAssemblyName(NewPath);
                if (name.Name != Assembly.GetExecutingAssembly().GetName().Name || !UpdateChecker.TryParseVersion(name.Version.ToString(3), out var version) ||
                    UpdateChecker.IsNewer(version, release.Version) || UpdateChecker.IsNewer(release.Version, version))
                    throw new InvalidOperationException("the download isn't the expected app");

                // Swap: the running exe can be renamed but not overwritten.
                TryDelete(OldPath);
                File.Move(ExePath, OldPath);
                try
                {
                    File.Move(NewPath, ExePath);
                }
                catch
                {
                    File.Move(OldPath, ExePath);
                    throw;
                }
            }
            catch
            {
                TryDelete(NewPath);
                throw;
            }

            Log.Write($"Installed {release.Tag}, restarting");
            Process.Start(new ProcessStartInfo(ExePath, "--after-update " + Process.GetCurrentProcess().Id) { UseShellExecute = false });
        }

        /// <summary>
        /// Run at startup. With --after-update PID, waits for the previous version to exit (it holds the
        /// single-instance lock). Then removes the old exe left by an update.
        /// </summary>
        public static void FinishUpdate(string[] args)
        {
            int i = Array.FindIndex(args, a => a.Equals("--after-update", StringComparison.OrdinalIgnoreCase));
            if (i >= 0 && i + 1 < args.Length && int.TryParse(args[i + 1], out int pid))
            {
                try
                {
                    using (var previous = Process.GetProcessById(pid))
                        previous.WaitForExit(15000);
                }
                catch (ArgumentException)
                {
                    // Already gone.
                }
            }

            for (int attempt = 0; attempt < 10 && File.Exists(OldPath); attempt++)
            {
                if (TryDelete(OldPath)) break;
                Thread.Sleep(300);
            }
        }

        static bool TryDelete(string path)
        {
            try
            {
                if (File.Exists(path)) File.Delete(path);
                return true;
            }
            catch
            {
                return false;
            }
        }
    }
}
