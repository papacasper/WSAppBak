using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Xml;

namespace WSAppBak
{
    internal class WSAppBak
    {
        private readonly string AppName      = "Windows Store App Backup";
        private readonly string AppCreator   = "Kiran Murmu";
        private readonly string WSAppXmlFile = "AppxManifest.xml";
        private const string WindowsSdkUrl   = "https://developer.microsoft.com/windows/downloads/windows-10-sdk/";
        private bool Checking                = true;

        private string WSAppPath;
        private string WSAppOutputPath;
        private string WSAppFileName;
        private string WSAppPublisher;

        public void Run()
        {
            ReadArg();
        }

        private void ReadArg()
        {
            while (Checking)
            {
                Console.Clear();
                Console.WriteLine($"\t\t'{AppName}' by {AppCreator}");
                Console.WriteLine(new string('=', 80));
                Console.Write("Enter the App path: ");
                WSAppPath = Console.ReadLine()?.Trim('"') ?? "";

                if (!File.Exists(Path.Combine(WSAppPath, WSAppXmlFile)))
                {
                    Console.WriteLine($"\nInvalid App Path; '{WSAppXmlFile}' not found!");
                    Pause();
                    continue;
                }

                Console.Write("\nEnter the Output path: ");
                WSAppOutputPath = Console.ReadLine()?.Trim('"') ?? "";

                if (!Directory.Exists(WSAppOutputPath))
                {
                    Console.WriteLine("\nInvalid Output Path; directory not found!");
                    Pause();
                    continue;
                }

                WSAppFileName = Path.GetFileName(WSAppPath);
                ExtractPublisherFromManifest();
                MakeAppx();
            }
        }

        private void ExtractPublisherFromManifest()
        {
            using var xml = XmlReader.Create(Path.Combine(WSAppPath, WSAppXmlFile));
            while (xml.Read())
            {
                if (xml.IsStartElement() && xml.Name == "Identity")
                {
                    WSAppPublisher = xml["Publisher"] ?? throw new Exception("Publisher missing");
                    break;
                }
            }
        }

        private void MakeAppx()
        {
            // Locate SDK
            string kitsRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                "Windows Kits", "10", "bin");
            var versioned = Directory.GetDirectories(kitsRoot)
                .Select(d => new { Dir = d, Ver = Version.TryParse(Path.GetFileName(d), out var v) ? v : null })
                .Where(x => x.Ver != null)
                .OrderByDescending(x => x.Ver)
                .FirstOrDefault();
            if (versioned == null)
                throw new DirectoryNotFoundException(
                    $"Windows Kits 10 not found. Install the Windows SDK from {WindowsSdkUrl}");

            string toolDir  = Path.Combine(versioned.Dir!, "x64");
            string makeAppx = Path.Combine(toolDir, "MakeAppx.exe");
            if (!File.Exists(makeAppx))
                throw new FileNotFoundException(
                    $"MakeAppx.exe missing. Install the Windows SDK from {WindowsSdkUrl}",
                    makeAppx);

            string args = $"pack -d \"{WSAppPath}\" -p \"{WSAppOutputPath}\\{WSAppFileName}.appx\" -l";
            if (RunProcess(makeAppx, args, toolDir) != 0)
            {
                Console.WriteLine("\nMakeAppx.exe failed.");
                Pause();
                return;
            }

            Console.WriteLine($"\nPackage '{WSAppFileName}.appx' created successfully.");
            MakeCert(toolDir);
        }

        private void MakeCert(string toolDir)
        {
            string exe = Path.Combine(toolDir, "MakeCert.exe");
            if (!File.Exists(exe))
                throw new FileNotFoundException(
                    $"MakeCert.exe missing. Install the Windows SDK from {WindowsSdkUrl}",
                    exe);

            string pvk = Path.Combine(WSAppOutputPath, WSAppFileName + ".pvk");
            string cer = Path.Combine(WSAppOutputPath, WSAppFileName + ".cer");

            if (File.Exists(pvk)) File.Delete(pvk);
            if (File.Exists(cer)) File.Delete(cer);

            string args =
                $"-n \"{WSAppPublisher}\" -r -a sha256 -len 2048 -cy end -h 0 " +
                $"-eku 1.3.6.1.5.5.7.3.3 -b 01/01/2000 -sv \"{pvk}\" \"{cer}\"";

            if (RunProcess(exe, args, toolDir) != 0)
            {
                Console.WriteLine("\nMakeCert.exe failed.");
                Pause();
                return;
            }

            Pvk2Pfx(toolDir);
        }

        private void Pvk2Pfx(string toolDir)
        {
            string exe = Path.Combine(toolDir, "Pvk2Pfx.exe");
            if (!File.Exists(exe))
                throw new FileNotFoundException(
                    $"Pvk2Pfx.exe missing. Install the Windows SDK from {WindowsSdkUrl}",
                    exe);

            string pvk = Path.Combine(WSAppOutputPath, WSAppFileName + ".pvk");
            string cer = Path.Combine(WSAppOutputPath, WSAppFileName + ".cer");
            string pfx = Path.Combine(WSAppOutputPath, WSAppFileName + ".pfx");

            if (File.Exists(pfx)) File.Delete(pfx);

            string args = $"-pvk \"{pvk}\" -spc \"{cer}\" -pfx \"{pfx}\"";

            if (RunProcess(exe, args, toolDir) != 0)
            {
                Console.WriteLine("\nPvk2Pfx.exe failed.");
                Pause();
                return;
            }

            SignApp(toolDir);
        }

        private void SignApp(string toolDir)
        {
            string exe = Path.Combine(toolDir, "SignTool.exe");
            if (!File.Exists(exe))
                throw new FileNotFoundException(
                    $"SignTool.exe missing. Install the Windows SDK from {WindowsSdkUrl}",
                    exe);

            string pfx  = Path.Combine(WSAppOutputPath, WSAppFileName + ".pfx");
            string appx = Path.Combine(WSAppOutputPath, WSAppFileName + ".appx");
            string args = $"sign -fd SHA256 -a -f \"{pfx}\" \"{appx}\"";

            if (RunProcess(exe, args, toolDir) != 0)
            {
                Console.WriteLine("\nSignTool.exe failed.");
                Pause();
                return;
            }

            Console.WriteLine("\nPackage signing succeeded!");
            Console.Write("\nPress any key to exit...");
            Console.ReadKey();
            Checking = false;
        }

        private int RunProcess(string exePath, string args, string workingDirectory)
        {
            var psi = new ProcessStartInfo(exePath, args)
            {
                WorkingDirectory       = workingDirectory,
                UseShellExecute        = false,
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
                CreateNoWindow         = true
            };

            using var proc = Process.Start(psi)!;
            proc.OutputDataReceived += (_, e) => { if (e.Data != null) Console.WriteLine(e.Data); };
            proc.ErrorDataReceived  += (_, e) => { if (e.Data != null) Console.Error.WriteLine(e.Data); };
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
            proc.WaitForExit();
            return proc.ExitCode;
        }

        private void Pause()
        {
            Console.Write("\nPress any key to retry...");
            Console.ReadKey();
        }
    }
}
