<#
.SYNOPSIS
    Defender Live Response packet capture script using Pktmon for incident response
    
.DESCRIPTION
    Captures network packets using Windows native Pktmon tool and converts to PCAP format
    for analysis in Wireshark. Designed for Microsoft Defender Live Response scenarios.
    
.PARAMETER TargetIP
    Optional IP address to filter capture (captures traffic to/from this IP)
    
.PARAMETER TargetPort
    Optional port number to filter capture (captures traffic on this port)
    
.PARAMETER Duration
    Capture duration in seconds. Valid values: 60, 300, 900 (1min, 5min, 15min)
    Default: 60 seconds
    
.EXAMPLE
    .\LiveResponse-PacketCapture.ps1
    Captures all traffic for 60 seconds
    
.EXAMPLE
    .\LiveResponse-PacketCapture.ps1 -TargetIP "192.168.1.100" -Duration 300
    Captures traffic to/from 192.168.1.100 for 5 minutes
    
.EXAMPLE
    .\LiveResponse-PacketCapture.ps1 -TargetPort 443 -Duration 900
    Captures traffic on port 443 for 15 minutes
    
.NOTES
    Version:        1.0.0
    Author:         Security Operations Team
    Creation Date:  2024
    License:        MIT License (https://opensource.org/licenses/MIT)
    
    After execution, use Defender Live Response "getfile" command to retrieve:
    - IR_Capture_[timestamp].pcap (Wireshark-compatible file)
    - IR_Capture_[timestamp].etl (Original ETL file)
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TargetIP = "",
    
    [Parameter(Mandatory=$false)]
    [int]$TargetPort = 0,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet(60, 300, 900)]
    [int]$Duration = 60
)

# Function to write status messages
function Write-Status {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor Cyan
}

# Main execution
try {
    Write-Status "Starting Incident Response packet capture..."
    
    # Generate unique filename with timestamp
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $etlFile = "IR_Capture_$timestamp.etl"
    $pcapFile = "IR_Capture_$timestamp.pcap"
    
    # Clean up any existing filters
    Write-Status "Clearing existing packet filters..."
    $null = pktmon filter remove 2>$null
    
    # Add filters if specified
    $filterCount = 0
    
    if ($TargetIP -ne "") {
        Write-Status "Adding filter for IP: $TargetIP"
        $null = pktmon filter add IRFilter_IP -i $TargetIP
        $filterCount++
    }
    
    if ($TargetPort -gt 0) {
        Write-Status "Adding filter for Port: $TargetPort"
        $null = pktmon filter add IRFilter_Port -p $TargetPort
        $filterCount++
    }
    
    # Display active filters
    if ($filterCount -gt 0) {
        Write-Status "Active filters:"
        pktmon filter list
    } else {
        Write-Status "No filters applied - capturing all traffic"
    }
    
    # Calculate duration display
    $durationDisplay = switch ($Duration) {
        60  { "1 minute" }
        300 { "5 minutes" }
        900 { "15 minutes" }
    }
    
    # Start packet capture
    Write-Status "Starting packet capture for $durationDisplay..."
    Write-Status "Capture parameters: --capture --pkt-size 0 (full packet capture)"
    
    # Start pktmon with full packet capture
    $startResult = pktmon start --capture --pkt-size 0 --file-name $etlFile 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start packet capture. Ensure running with administrative privileges."
    }
    
    Write-Status "Packet capture is running..."
    Write-Status "Collecting packets for $Duration seconds..."
    
    # Show progress during capture
    $endTime = (Get-Date).AddSeconds($Duration)
    $progressInterval = [Math]::Min(10, $Duration/10)
    
    while ((Get-Date) -lt $endTime) {
        $remaining = [Math]::Round(($endTime - (Get-Date)).TotalSeconds)
        Write-Progress -Activity "Capturing packets" -Status "Time remaining: $remaining seconds" -PercentComplete ((($Duration - $remaining) / $Duration) * 100)
        Start-Sleep -Seconds $progressInterval
    }
    
    Write-Progress -Activity "Capturing packets" -Completed
    
    # Stop capture
    Write-Status "Stopping packet capture..."
    $stopResult = pktmon stop 2>&1
    
    # Check if ETL file was created
    if (!(Test-Path $etlFile)) {
        throw "ETL capture file was not created. Check pktmon status."
    }
    
    $etlSize = (Get-Item $etlFile).Length / 1MB
    Write-Status "Capture complete. ETL file size: $([Math]::Round($etlSize, 2)) MB"
    
    # Convert to PCAP format
    Write-Status "Converting to PCAP format for Wireshark analysis..."
    $convertResult = pktmon etl2pcap $etlFile --out $pcapFile 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to convert to PCAP format. ETL file is still available."
    } else {
        if (Test-Path $pcapFile) {
            $pcapSize = (Get-Item $pcapFile).Length / 1MB
            Write-Status "PCAP conversion complete. File size: $([Math]::Round($pcapSize, 2)) MB"
        }
    }
    
    # Clean up filters
    Write-Status "Cleaning up packet filters..."
    $null = pktmon filter remove 2>$null
    
    # Summary
    Write-Host "`n========== CAPTURE SUMMARY ==========" -ForegroundColor Green
    Write-Host "Capture Duration: $durationDisplay" -ForegroundColor Green
    
    if ($TargetIP -ne "") {
        Write-Host "Filtered IP: $TargetIP" -ForegroundColor Green
    }
    if ($TargetPort -gt 0) {
        Write-Host "Filtered Port: $TargetPort" -ForegroundColor Green
    }
    
    Write-Host "`nFiles created:" -ForegroundColor Green
    
    if (Test-Path $pcapFile) {
        Write-Host "  - $pcapFile (Wireshark compatible)" -ForegroundColor Yellow
    }
    if (Test-Path $etlFile) {
        Write-Host "  - $etlFile (Original capture)" -ForegroundColor Yellow
    }
    
    Write-Host "`nUse Defender Live Response 'getfile' command to retrieve files" -ForegroundColor Cyan
    Write-Host "====================================`n" -ForegroundColor Green
    
    # Return file paths for Live Response
    return @{
        Success = $true
        PcapFile = $pcapFile
        EtlFile = $etlFile
        Duration = $Duration
        FilteredIP = $TargetIP
        FilteredPort = $TargetPort
    }
    
} catch {
    Write-Error "Packet capture failed: $_"
    
    # Cleanup on error
    try {
        $null = pktmon stop 2>$null
        $null = pktmon filter remove 2>$null
    } catch {
        # Ignore cleanup errors
    }
    
    return @{
        Success = $false
        Error = $_.ToString()
    }
}