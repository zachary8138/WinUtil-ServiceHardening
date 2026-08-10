# WinUtil Service Hardening

WinUtil (and other Windows 11 utilities that remove unncccessary services)  disables the main telemetry service, but related diagnostic and convenience services are often left as **Manual**. This script finishes that cleanup, then verifies critical Windows services were **not** broken.

## What it does

1. Stops and sets recommended leftover services to **Disabled**
2. Verifies Connected User Experiences and Telemetry (`DiagTrack`) is Disabled
3. Checks protected services and **never modifies them**
4. Prints a clear before / after report

## Requirements

- Windows 10 / 11
- Windows PowerShell 5.1 or later (or PowerShell 7+)
- Run as **Administrator**

## Quick start

```powershell
# Preview first (recommended)
.\WinUtil-ServiceHardening.ps1 -WhatIf

# Apply
.\WinUtil-ServiceHardening.ps1
```

If execution policy blocks the script for a one-off run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WinUtil-ServiceHardening.ps1 -WhatIf
```

## Services disabled

| Service | Display name | Notes |
| --- | --- | --- |
| `DiagTrack` | Connected User Experiences and TelemetXbox Live Services (XblAuthManager, XblGameSave, XboxNetApiSvc)ry | Usually disabled by WinUtil; this script verifies |
| `dmwappushservice` | WAP Push Message Routing Service | Often left Manual; safe if you do not use WAP push |
| `DPS` | Diagnostic Policy Service | Needed for Windows Troubleshooters; optional skip |
| `PcaSvc` | Program Compatibility Assistant Service | Safe to disable on modern systems |
| `RemoteRegistry` | Remote Registry | Recommended disable for security |
| `lmhosts` | TCP/IP NetBIOS Helper | Safe on modern home networks without legacy NetBIOS sharing |
| `MapsBroker` | Downloaded Maps Manager | Safe if you do not use offline Windows Maps |
| `XblAuthManager` | Xbox Live Auth Manager | Safe if you do not use Xbox / Microsoft Store gaming |
| `XblGameSave` | Xbox Live Game Save | Same as above |
| `XboxNetApiSvc` | Xbox Live Networking Service | Same as above |

Missing services (not installed on the SKU) are skipped cleanly.

## Services never touched

These are verified only. The script will not stop, start, or change their startup type:

| Service | Display name | Why it is protected |
| --- | --- | --- |
| `wuauserv` | Windows Update | Required for security patches |
| `WinDefend` | Windows Defender Antivirus Service | Disabling leaves the system unprotected unless replaced |
| `Dhcp` | DHCP Client | Required for normal network connectivity |
| `PlugPlay` | Plug and Play | Required for hardware detection |
| `CryptSvc` | Cryptographic Services | Required for updates and secure browsing |

If a required protected service is already **Disabled** or missing, the script aborts before making hardening changes (except in `-WhatIf` mode).  
`WinDefend` missing is treated as a warning, since some SKUs do not ship it.

## Options

| Parameter | Effect |
| --- | --- |
| `-WhatIf` | Show what would change; make no modifications |
| `-SkipDPS` | Leave Diagnostic Policy Service alone (keep Troubleshooters) |
| `-SkipXbox` | Leave Xbox Live services alone |

Examples:

```powershell
.\WinUtil-ServiceHardening.ps1 -SkipXbox
.\WinUtil-ServiceHardening.ps1 -SkipDPS
.\WinUtil-ServiceHardening.ps1 -SkipXbox -SkipDPS
```

## Exit codes

| Code | Meaning |
| --- | ---: |
| `0` | Success |
| `1` | Completed with verification failures |
| `2` | Aborted because a protected service was already Disabled / missing |

## Safety notes

- This is intended for a typical modern **home** PC after WinUtil debloat.
- Disabling `DPS` removes Windows Troubleshooter support.
- Disabling Xbox services breaks Xbox / some Store game features.
- Disabling `lmhosts` can affect legacy NetBIOS name resolution / older LAN sharing setups.
- Always run `-WhatIf` first on a machine you care about.
- A reboot is usually not required for service start-type changes, but one can help if something still looks sticky in `services.msc`.

## Related

- WinUtil: `irm https://christitus.com/win | iex`
- Script file: [`WinUtil-ServiceHardening.ps1`](./WinUtil-ServiceHardening.ps1)

## License

[GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html)

Use at your own risk. Review the script before running it on production systems.

## References

After [Chris Titus Tech WinUtil](https://christitus.com/win) (`irm https://christitus.com/win | iex`), You can run this script as a safe follow-up.

I also recommend [https://github.com/raphire/win11debloat] as well.  
