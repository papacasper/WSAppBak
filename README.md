# WSAppBak
 APPX Backupper and Repacker
 
Info:

This was not made by me, i found it somewhere, and decompiled it.

## Requirements

The tool requires the **.NET 8 Windows Desktop runtime** to run. You can install
it from <https://dotnet.microsoft.com/download/dotnet/8.0>.

It also depends on the **Windows SDK tools** (`MakeAppx.exe`, `MakeCert.exe`,
`Pvk2Pfx.exe`, `SignTool.exe`). If they are missing on your machine, install the
Windows SDK from <https://developer.microsoft.com/windows/downloads/windows-10-sdk/>.

## Usage

Run without arguments for interactive mode:

```bash
WSAppBak.exe
```

Specify input and output folders to run non-interactively:

```bash
WSAppBak.exe <appPath> <outputPath>
```
