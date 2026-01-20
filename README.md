# Defender Live Response Packet Capture Tool

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-10%2B-blue.svg)](https://www.microsoft.com/windows)

A PowerShell script for capturing network packets during incident response using Microsoft Defender for Endpoint's Live Response capability and Windows native Packet Monitor (Pktmon).

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Parameters](#parameters)
- [Examples](#examples)
- [Output Files](#output-files)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Overview

![](https://github.com/Pr0kythera/LiveResponseScripts/blob/main/Recording%202025-09-15%20212956.gif)

This tool enables security analysts and incident responders to quickly capture network traffic on remote Windows endpoints through Microsoft Defender for Endpoint's Live Response feature. It leverages the built-in Windows Packet Monitor (Pktmon) utility to capture packets and automatically converts them to PCAP format for analysis in Wireshark or other network analysis tools.

### Why This Tool?

During incident response, you often need to:
- Capture network traffic on compromised endpoints without installing additional software
- Quickly gather network evidence during active incidents
- Filter traffic to specific IPs or ports to reduce noise
- Retrieve packet captures remotely without direct endpoint access

This script solves these challenges by providing a simple, parameter-driven interface to Pktmon that works seamlessly with Defender Live Response.

## Features

- ** Flexible Filtering**: Capture all traffic or filter by specific IP addresses and/or ports
- ** Configurable Duration**: Choose between 1, 5, or 15-minute capture windows
- ** Full Packet Capture**: Captures complete packets, not just headers (using `--pkt-size 0`)
- ** Automatic Conversion**: Converts native ETL format to PCAP for Wireshark compatibility
- ** Progress Tracking**: Real-time progress indicators during capture
- ** Auto-cleanup**: Automatically removes filters after capture
- ** Detailed Logging**: Comprehensive status messages for troubleshooting

## Requirements

### Endpoint Requirements
- **Windows Version**: Windows 10 1809+ or Windows Server 2019+
- **Pktmon**: Built into Windows (no installation required)
- **Permissions**: Administrative privileges (automatically handled by Live Response)

### Management Requirements
- **Microsoft Defender for Endpoint**: E5 or standalone license
- **Live Response**: Enabled in Defender settings
- **Permissions**: Security Administrator or Global Administrator role

## Installation

### Step 1: Download the Script
```bash
# Clone this repository
git clone https://github.com/yourusername/defender-live-response-pcap.git

# Or download directly
curl -O https://raw.githubusercontent.com/yourusername/defender-live-response-pcap/main/LiveResponse-PacketCapture.ps1
```

### Step 2: Upload to Defender Live Response Library

1. Sign in to [Microsoft 365 Defender portal](https://security.microsoft.com)
2. Navigate to **Settings** → **Endpoints** → **Response** → **Live response scripts**
3. Click **Upload file**
4. Select `LiveResponse-PacketCapture.ps1`
5. Add a description (optional)
6. Click **Submit**

## Usage

### Basic Syntax

```powershell
run LiveResponse-PacketCapture.ps1 [-TargetIP <string>] [-TargetPort <int>] [-Duration <int>]
```

### Starting a Live Response Session

1. In Microsoft 365 Defender portal, go to **Devices**
2. Select the target device
3. Click **Initiate Live Response Session**
4. Wait for the session to establish
5. Run the packet capture script with desired parameters

##  Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-TargetIP` | String | No | None | Filter capture to traffic to/from this IP address |
| `-TargetPort` | Integer | No | None | Filter capture to traffic on this port |
| `-Duration` | Integer | No | 60 | Capture duration in seconds (60, 300, or 900) |

## Examples

### Example 1: Basic Capture
Capture all network traffic for 60 seconds:
```powershell
run LiveResponse-PacketCapture.ps1
```

### Example 2: IP-Specific Capture
Capture traffic to/from a specific IP for 5 minutes:
```powershell
run LiveResponse-PacketCapture.ps1 -TargetIP "192.168.1.100" -Duration 300
```

### Example 3: Port-Specific Capture
Capture all HTTPS traffic (port 443) for 15 minutes:
```powershell
run LiveResponse-PacketCapture.ps1 -TargetPort 443 -Duration 900
```

### Example 4: Combined Filters
Capture SMB traffic to a specific server:
```powershell
run LiveResponse-PacketCapture.ps1 -TargetIP "10.0.0.5" -TargetPort 445 -Duration 300
```

### Example 5: Incident Response Workflow
```powershell
# 1. Start Live Response session
# 2. Run quick 1-minute capture to identify suspicious connections
run LiveResponse-PacketCapture.ps1 -Duration 60

# 3. Review results, then capture specific suspicious IP
run LiveResponse-PacketCapture.ps1 -TargetIP "185.220.101.45" -Duration 300

# 4. Retrieve the PCAP file
getfile "IR_Capture_20241120_143022.pcap"
```

## Output Files

The script generates two files:

| File | Format | Description |
|------|--------|-------------|
| `IR_Capture_[timestamp].pcap` | PCAP | Wireshark-compatible packet capture |
| `IR_Capture_[timestamp].etl` | ETL | Original Windows Event Trace Log |

**Timestamp Format**: `yyyyMMdd_HHmmss` (e.g., `20241120_143022`)

### Retrieving Files

After the capture completes, use the Live Response `getfile` command:

```powershell
# Retrieve PCAP file for analysis
getfile "IR_Capture_20241120_143022.pcap"

# Optionally retrieve ETL file
getfile "IR_Capture_20241120_143022.etl"
```

## Troubleshooting

### Common Issues

#### Issue: "Failed to start packet capture"
**Solution**: Ensure the Live Response session has administrative privileges (should be automatic).

#### Issue: "Failed to convert to PCAP format"
**Solution**: The ETL file is still available. You can:
1. Retrieve the ETL file and convert locally
2. Use Microsoft Network Monitor to analyze ETL files
3. Convert manually: `pktmon etl2pcap file.etl --out file.pcap`

#### Issue: No packets captured
**Possible Causes**:
- Filters too restrictive
- No network activity during capture
- Network adapter issues

**Solution**: Try capturing without filters first

### Useful Commands

```powershell
# Check if Pktmon is available
pktmon help

# List network adapters
pktmon list

# Check for existing filters (run locally)
pktmon filter list

# Manual cleanup if needed
pktmon stop
pktmon filter remove
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Ideas for Contribution

- Add support for multiple IP addresses
- Implement capture rotation for long-running captures
- Add network statistics summary
- Create complementary analysis scripts
- Add support for additional Pktmon filters

## License

This project is licensed under the MIT License - see below for details:

```
MIT License

Copyright (c) 2024 [Your Name/Organization]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Resources

- [Microsoft Defender for Endpoint Documentation](https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/)
- [Live Response Commands](https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/live-response)
- [Packet Monitor (Pktmon) Documentation](https://docs.microsoft.com/en-us/windows-server/networking/technologies/pktmon/pktmon)
- [Wireshark](https://www.wireshark.org/)

## Authors

- **Prokythera** - *Initial work*

## Acknowledgments

- Microsoft Defender for Endpoint team for Live Response capability
- Windows Networking team for the Pktmon utility
- The incident response community for feedback and testing

---

**Note**: This tool is provided as-is for incident response purposes. Always ensure you have proper authorization before capturing network traffic in your environment.
