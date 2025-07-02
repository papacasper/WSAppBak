Param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    [Parameter(Mandatory=$false)]
    [string]$ProjectDir = $PSScriptRoot,
    [Parameter(Mandatory=$false)]
    [switch]$SkipGit,
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

Write-Host "🚀 WSAppBak Release Script (Organized Structure)" -ForegroundColor Green
Write-Host "Version: $Version" -ForegroundColor Yellow

# Paths for organized structure (go up one level from scripts/ to repo root)
$repoRoot = Split-Path $ProjectDir -Parent
$csprojPath = Join-Path $repoRoot "src\WSAppBak.csproj"
$publishDir = Join-Path $repoRoot "publish"
$archiveName = "WSAppBak-v$Version-win-x64.zip"

# Validation
if (-Not (Test-Path $csprojPath)) {
    Write-Error "Cannot find WSAppBak.csproj in src/ directory. Are you in the right location?"
    exit 1
}

if ($WhatIf) {
    Write-Host "🔍 DRY RUN MODE - No changes will be made" -ForegroundColor Cyan
}

try {
    # Clean previous builds
    Write-Host "`n🧹 Cleaning previous builds..." -ForegroundColor Yellow
    if (Test-Path $publishDir) { 
        if (-not $WhatIf) {
            Remove-Item $publishDir -Recurse -Force 
        }
        Write-Host "  Cleaned publish directory" -ForegroundColor Gray
    }
    
    $archivePath = Join-Path $repoRoot $archiveName
    if (Test-Path $archivePath) { 
        if (-not $WhatIf) {
            Remove-Item $archivePath -Force 
        }
        Write-Host "  Removed existing archive" -ForegroundColor Gray
    }
    
    if (-not $WhatIf) {
        dotnet clean $csprojPath -c Release --verbosity quiet
        if ($LASTEXITCODE -ne 0) { throw "Clean failed" }
    }
    Write-Host "✅ Cleanup complete" -ForegroundColor Green

    # Update version in project file
    Write-Host "`n📝 Updating version to $Version..." -ForegroundColor Yellow
    if (-not $WhatIf) {
        [xml]$projXml = Get-Content $csprojPath
        $versionNode = $projXml.SelectSingleNode("//Version")
        
        if ($versionNode) {
            $versionNode.InnerText = $Version
            Write-Host "  Updated existing version element" -ForegroundColor Gray
        } else {
            $propertyGroup = $projXml.SelectSingleNode("//PropertyGroup")
            if (-not $propertyGroup) {
                $propertyGroup = $projXml.CreateElement("PropertyGroup")
                $projXml.Project.AppendChild($propertyGroup) | Out-Null
            }
            $newVersionNode = $projXml.CreateElement("Version")
            $newVersionNode.InnerText = $Version
            $propertyGroup.AppendChild($newVersionNode) | Out-Null
            Write-Host "  Created new version element" -ForegroundColor Gray
        }
        
        $projXml.Save($csprojPath)
        Write-Host "✅ Version updated in project file" -ForegroundColor Green
    } else {
        Write-Host "  Would update version in $csprojPath" -ForegroundColor Cyan
    }

    # Build using proven working configuration
    Write-Host "`n🔨 Building using proven working configuration..." -ForegroundColor Yellow
    
    # Same build config that works, just from src/ directory
    $buildArgs = @(
        'publish', $csprojPath
        '-c', 'Release'
        '-f', 'net8.0-windows'
        '-r', 'win-x64'
        '--self-contained', 'false'
        '--output', $publishDir
        '--verbosity', 'minimal'
    )
    
    if (-not $WhatIf) {
        Write-Host "  Running: dotnet $($buildArgs -join ' ')" -ForegroundColor Gray
        & dotnet @buildArgs
        if ($LASTEXITCODE -ne 0) { throw "Build failed" }
        
        # Verify build output
        $publishedFiles = Get-ChildItem $publishDir -File
        if ($publishedFiles.Count -eq 0) {
            throw "No files found in publish directory"
        }
        
        $mainExe = $publishedFiles | Where-Object { $_.Name -eq "WSAppBak.exe" }
        if (-not $mainExe) {
            Write-Warning "WSAppBak.exe not found in publish output"
        } else {
            Write-Host "  ✅ WSAppBak.exe created successfully" -ForegroundColor Green
        }
        
        $totalSize = ($publishedFiles | Measure-Object -Property Length -Sum).Sum
        Write-Host "✅ Build complete: $($publishedFiles.Count) files, $([math]::Round($totalSize/1MB, 2)) MB total" -ForegroundColor Green
    } else {
        Write-Host "  Would run: dotnet $($buildArgs -join ' ')" -ForegroundColor Cyan
    }

    # Create release package
    Write-Host "`n📦 Creating release package..." -ForegroundColor Yellow
    
    if (-not $WhatIf) {
        Compress-Archive -Path "$publishDir\*" -DestinationPath $archivePath -CompressionLevel Optimal
        
        $archiveInfo = Get-Item $archivePath
        Write-Host "✅ Package created: $archiveName ($([math]::Round($archiveInfo.Length/1MB, 2)) MB)" -ForegroundColor Green
    } else {
        Write-Host "  Would create: $archiveName" -ForegroundColor Cyan
    }

    # Git and GitHub operations (if not skipped)
    if (-not $SkipGit) {
        Write-Host "`n📦 Git operations..." -ForegroundColor Yellow
        
        if (-not $WhatIf) {
            Push-Location $repoRoot
            try {
                git add $csprojPath
                git commit -m "chore: bump version to $Version"
                git tag "v$Version"
                git push origin HEAD --tags
                
                # GitHub release
                $standaloneExe = Join-Path $repoRoot "WSAppBak-v$Version.exe"
                $mainExePath = Join-Path $publishDir "WSAppBak.exe"
                if (Test-Path $mainExePath) {
                    Copy-Item $mainExePath $standaloneExe
                }
                
                $releaseNotes = @"
## WSAppBak v$Version

### ⚠️ Important: Output directory must be EMPTY
The application will hang if the output directory contains existing files.

### Download Options
- WSAppBak-v$Version.exe - Standalone executable
- WSAppBak-v$Version-win-x64.zip - Complete package

### Usage
Create a new empty directory for each backup:
``````
mkdir C:\Backups\MyApp-$(Get-Date -Format 'yyyyMMdd-HHmmss')
WSAppBak.exe "C:\Path\To\App" "C:\Backups\MyApp-20250101-143022"
``````

### Requirements
- Windows 10/11 (x64)
- .NET 8.0 Runtime
- Windows SDK tools
"@
                
                $filesToUpload = @($archiveName)
                if (Test-Path $standaloneExe) {
                    $filesToUpload += (Split-Path $standaloneExe -Leaf)
                }
                
                gh release create "v$Version" --title "WSAppBak v$Version" --notes $releaseNotes $filesToUpload
                Write-Host "✅ GitHub release created" -ForegroundColor Green
            } finally {
                Pop-Location
            }
        } else {
            Write-Host "  Would create Git tag and GitHub release" -ForegroundColor Cyan
        }
    } else {
        Write-Host "⏭️  Skipping Git and GitHub operations" -ForegroundColor Yellow
    }

    Write-Host "`n🎉 Release completed!" -ForegroundColor Green
    Write-Host "💡 Remember: Use EMPTY output directories!" -ForegroundColor Yellow

} catch {
    Write-Error "❌ Release failed: $_"
    exit 1
}
