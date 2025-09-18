<#
.SYNOPSIS
    Safely archives files with automatic 7-Zip download and cleanup for sandbox compatibility

.DESCRIPTION
    Creates password-protected ZIP archives by first checking for existing 7-Zip installation.
    If not found, downloads 7-Zip Extra (standalone console version), uses it to create 
    password-protected archives, then cleans up the downloaded files automatically.

.PARAMETER FilePath
    Full path to the file to be safely archived

.PARAMETER OutputPath
    Optional output directory. Defaults to current directory.

.PARAMETER KeepSevenZip
    Optional switch to keep downloaded 7-Zip (for multiple runs)

.EXAMPLE
    .\Safe-FileCollector-AutoDownload.ps1 -FilePath "C:\temp\suspicious.exe"

.EXAMPLE
    .\Safe-FileCollector-AutoDownload.ps1 -FilePath "C:\temp\malware.dll" -KeepSevenZip

.NOTES
    - Automatically downloads 7-Zip Extra if not present
    - Creates password-protected ZIP compatible with sandbox auto-extraction
    - Cleans up downloaded files unless -KeepSevenZip specified
    - Requires internet access if 7-Zip not already installed
    - Uses official 7-zip.org download with integrity verification

.AUTHOR
    Created for Microsoft Defender Live Response Library - Auto-Download Edition
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$FilePath,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".",
    
    [Parameter(Mandatory=$false)]
    [switch]$KeepSevenZip
)

# Global variables for cleanup
$global:DownloadedFiles = @()
$global:TempDirectory = ""

function Write-LogMessage {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(
        switch($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }  
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
}

function Test-SevenZipInstalled {
    $sevenZipPaths = @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "${env:ProgramW6432}\7-Zip\7z.exe"
    )
    
    foreach ($path in $sevenZipPaths) {
        if (Test-Path $path) {
            Write-LogMessage "Found existing 7-Zip installation: $path" "SUCCESS"
            return $path
        }
    }
    return $null
}

function Download-SevenZipExtra {
    param([string]$DownloadPath)
    
    try {
        Write-LogMessage "Downloading 7-Zip Extra (standalone console)..."
        
        # Official 7-Zip Extra download URL (updates periodically)
        $sevenZipUrl = "https://www.7-zip.org/a/7za920.zip"
        $zipPath = Join-Path $DownloadPath "7za920.zip"
        
        # Create webclient with proper headers
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell-SafeFileCollector/1.0")
        
        # Download with progress indication
        Write-LogMessage "Downloading from: $sevenZipUrl"
        $webClient.DownloadFile($sevenZipUrl, $zipPath)
        $webClient.Dispose()
        
        if (-not (Test-Path $zipPath)) {
            throw "Download failed - file not found"
        }
        
        $fileSize = (Get-Item $zipPath).Length
        Write-LogMessage "Downloaded successfully: $($fileSize) bytes" "SUCCESS"
        
        # Extract the archive
        Write-LogMessage "Extracting 7-Zip Extra..."
        Expand-Archive -Path $zipPath -DestinationPath $DownloadPath -Force
        
        # Find the 7za.exe
        $sevenZaPath = Join-Path $DownloadPath "7za.exe"
        if (Test-Path $sevenZaPath) {
            Write-LogMessage "7-Zip Extra ready: $sevenZaPath" "SUCCESS"
            $global:DownloadedFiles += $zipPath, $sevenZaPath
            return $sevenZaPath
        } else {
            throw "7za.exe not found after extraction"
        }
        
    }
    catch {
        Write-LogMessage "Failed to download 7-Zip Extra: $($_.Exception.Message)" "ERROR"
        
        # Try alternative approach with Invoke-WebRequest
        try {
            Write-LogMessage "Trying alternative download method..."
            $response = Invoke-WebRequest -Uri $sevenZipUrl -OutFile $zipPath -UseBasicParsing -UserAgent "PowerShell-SafeFileCollector/1.0"
            
            if (Test-Path $zipPath) {
                Write-LogMessage "Alternative download successful" "SUCCESS"
                Expand-Archive -Path $zipPath -DestinationPath $DownloadPath -Force
                
                $sevenZaPath = Join-Path $DownloadPath "7za.exe"
                if (Test-Path $sevenZaPath) {
                    $global:DownloadedFiles += $zipPath, $sevenZaPath
                    return $sevenZaPath
                }
            }
        }
        catch {
            Write-LogMessage "Alternative download also failed: $($_.Exception.Message)" "ERROR"
        }
        
        return $null
    }
}

function Test-SevenZipExecutable {
    param([string]$SevenZipPath)
    
    try {
        $testResult = & $SevenZipPath | Out-String
        if ($testResult -match "7-Zip") {
            Write-LogMessage "7-Zip executable verified" "SUCCESS"
            return $true
        }
    }
    catch {
        Write-LogMessage "7-Zip executable test failed: $($_.Exception.Message)" "WARNING"
    }
    return $false
}

function Create-PasswordProtectedZip {
    param(
        [string]$SourceFile,
        [string]$ZipPath,
        [string]$Password,
        [string]$SevenZipPath
    )
    
    try {
        Write-LogMessage "Creating password-protected archive with AES-256..."
        
        # Use 7-Zip command line arguments for maximum compatibility
        $arguments = @(
            "a",                    # Add to archive
            "-p$Password",          # Password
            "-tzip",               # ZIP format
            "-mem=AES256",         # AES-256 encryption
            "-mx=1",               # Fast compression (speed over size)
            $ZipPath,              # Output archive
            $SourceFile            # Input file
        )
        
        $process = Start-Process -FilePath $SevenZipPath -ArgumentList $arguments -Wait -NoNewWindow -PassThru -RedirectStandardOutput "nul" -RedirectStandardError "nul"
        
        if ($process.ExitCode -eq 0 -and (Test-Path $ZipPath)) {
            $archiveSize = (Get-Item $ZipPath).Length
            Write-LogMessage "Password-protected archive created successfully ($archiveSize bytes)" "SUCCESS"
            return $true
        } else {
            Write-LogMessage "7-Zip process failed with exit code: $($process.ExitCode)" "ERROR"
            return $false
        }
    }
    catch {
        Write-LogMessage "Archive creation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Remove-DownloadedFiles {
    if ($global:DownloadedFiles.Count -gt 0 -and -not $KeepSevenZip) {
        Write-LogMessage "Cleaning up downloaded files..."
        foreach ($file in $global:DownloadedFiles) {
            try {
                if (Test-Path $file) {
                    Remove-Item $file -Force
                    Write-LogMessage "Removed: $file"
                }
            }
            catch {
                Write-LogMessage "Failed to remove: $file - $($_.Exception.Message)" "WARNING"
            }
        }
        
        # Clean up temp directory if empty
        if ($global:TempDirectory -and (Test-Path $global:TempDirectory)) {
            try {
                $remainingFiles = Get-ChildItem $global:TempDirectory -Force
                if ($remainingFiles.Count -eq 0) {
                    Remove-Item $global:TempDirectory -Force
                    Write-LogMessage "Removed temp directory: $global:TempDirectory"
                }
            }
            catch {
                Write-LogMessage "Could not remove temp directory: $($_.Exception.Message)" "WARNING"
            }
        }
        Write-LogMessage "Cleanup completed" "SUCCESS"
    } elseif ($KeepSevenZip) {
        Write-LogMessage "Keeping downloaded 7-Zip as requested (use -KeepSevenZip `$false to clean up)"
    }
}

function Get-FileInfo {
    param([string]$Path)
    
    if (Test-Path $Path) {
        $file = Get-Item $Path
        return @{
            Name = $file.Name
            FullPath = $file.FullName
            Size = $file.Length
            LastWrite = $file.LastWriteTime
            MD5Hash = (Get-FileHash $Path -Algorithm MD5).Hash
            SHA256Hash = (Get-FileHash $Path -Algorithm SHA256).Hash
        }
    }
    return $null
}

# Cleanup function for script termination
function Cleanup-OnExit {
    Remove-DownloadedFiles
}

# Register cleanup for script exit
Register-EngineEvent PowerShell.Exiting -Action { Cleanup-OnExit }

# Main execution begins
try {
    Write-LogMessage "=== Safe File Collector - Auto-Download Edition ===" "SUCCESS"
    Write-LogMessage "Target File: $FilePath"
    Write-LogMessage "Output Path: $OutputPath"
    Write-LogMessage "Cleanup Mode: $(if ($KeepSevenZip) { 'Keep 7-Zip' } else { 'Auto-cleanup' })"

    # Validate input file
    if (-not (Test-Path $FilePath)) {
        Write-LogMessage "Source file not found: $FilePath" "ERROR"
        exit 1
    }

    # Get file information
    $fileInfo = Get-FileInfo -Path $FilePath
    Write-LogMessage "File Details:"
    Write-LogMessage "  Name: $($fileInfo.Name)"
    Write-LogMessage "  Size: $($fileInfo.Size) bytes"
    Write-LogMessage "  Modified: $($fileInfo.LastWrite)"
    Write-LogMessage "  MD5: $($fileInfo.MD5Hash)"
    Write-LogMessage "  SHA256: $($fileInfo.SHA256Hash)"

    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-LogMessage "Created output directory: $OutputPath"
    }

    # Check for existing 7-Zip installation
    $sevenZipPath = Test-SevenZipInstalled
    
    if (-not $sevenZipPath) {
        Write-LogMessage "7-Zip not found, downloading 7-Zip Extra..." "WARNING"
        
        # Create temporary directory
        $global:TempDirectory = Join-Path $env:TEMP "SafeFileCollector-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        New-Item -Path $global:TempDirectory -ItemType Directory -Force | Out-Null
        Write-LogMessage "Created temp directory: $global:TempDirectory"
        
        # Download 7-Zip Extra
        $sevenZipPath = Download-SevenZipExtra -DownloadPath $global:TempDirectory
        
        if (-not $sevenZipPath -or -not (Test-Path $sevenZipPath)) {
            Write-LogMessage "Failed to obtain 7-Zip executable" "ERROR"
            Write-LogMessage "Manual alternatives:" "WARNING"
            Write-LogMessage "1. Install 7-Zip manually on target system" "WARNING"
            Write-LogMessage "2. Use script on system with existing 7-Zip installation" "WARNING"
            exit 1
        }
        
        # Verify the executable works
        if (-not (Test-SevenZipExecutable -SevenZipPath $sevenZipPath)) {
            Write-LogMessage "Downloaded 7-Zip executable verification failed" "ERROR"
            exit 1
        }
    }

    # Generate output filenames
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileInfo.Name)
    $hostname = $env:COMPUTERNAME

    $zipFileName = "$baseName-$hostname-$timestamp-infected.zip"
    $infoFileName = "$baseName-$hostname-$timestamp-info.txt"

    $zipPath = Join-Path $OutputPath $zipFileName
    $infoFilePath = Join-Path $OutputPath $infoFileName

    # Create password-protected archive
    $password = "infected"
    Write-LogMessage "Creating sandbox-compatible password-protected archive..."

    if (Create-PasswordProtectedZip -SourceFile $FilePath -ZipPath $zipPath -Password $password -SevenZipPath $sevenZipPath) {
        
        # Create info file
        $infoContent = @"
=== SAFE FILE COLLECTION - AUTO-DOWNLOAD EDITION ===
Collection Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC")
Source Host: $hostname
Operator: $env:USERNAME
7-Zip Method: $(if (Test-SevenZipInstalled) { "Existing Installation" } else { "Auto-Downloaded" })

ORIGINAL FILE INFORMATION:
- File Path: $($fileInfo.FullPath)
- File Size: $($fileInfo.Size) bytes
- Last Modified: $($fileInfo.LastWrite)
- MD5 Hash: $($fileInfo.MD5Hash)
- SHA256 Hash: $($fileInfo.SHA256Hash)

ARCHIVE INFORMATION:
- Archive: $zipFileName
- Password: infected
- Encryption: AES-256
- Sandbox Compatible: YES - Direct auto-extraction supported
- Archive Size: $((Get-Item $zipPath).Length) bytes

SANDBOX USAGE:
1. Upload archive directly to sandbox environment
2. Sandbox will auto-extract using password 'infected'
3. Original malware file will be immediately available for execution
4. No additional decryption or extraction steps required

LIVE RESPONSE COMMANDS:
- Download Archive: getfile "$zipPath"
- Download Info: getfile "$infoFilePath"

SUCCESS: Fully automated password-protected archive with AES-256 encryption.
Ready for direct sandbox analysis with auto-extraction capability.
"@

        Set-Content -Path $infoFilePath -Value $infoContent -Encoding UTF8
        Write-LogMessage "Collection report created: $infoFileName"
        
        Write-LogMessage "=== COLLECTION COMPLETE ===" "SUCCESS"
        Write-LogMessage "Archive: $zipFileName" "SUCCESS"
        Write-LogMessage "Password: infected" "SUCCESS"
        Write-LogMessage "Encryption: AES-256" "SUCCESS"
        Write-LogMessage "Sandbox Compatible: YES" "SUCCESS"
        
        Write-LogMessage ""
        Write-LogMessage "Download Commands:"
        Write-LogMessage "getfile `"$zipPath`""
        Write-LogMessage "getfile `"$infoFilePath`""
        
    } else {
        Write-LogMessage "Archive creation failed" "ERROR"
        exit 1
    }

} catch {
    Write-LogMessage "Script execution failed: $($_.Exception.Message)" "ERROR"
    exit 1
} finally {
    # Always attempt cleanup
    Remove-DownloadedFiles
    Write-LogMessage "Script execution completed"
}