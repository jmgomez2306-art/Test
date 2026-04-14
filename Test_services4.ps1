# ==============================
# Configuration
# ==============================

# Services to validate
$services = @(
    "cyserver",
    "xdrcollectorsvc",
    "Parity"
)

# Cortex processes
$cortexProcesses = @(
    "cyserver",
    "xdrcollectorsvc",
    "CortexXDR",
    "Traps"
)

# Event IDs last 24 horas
$eventIds = @(3077, 3076, 8003, 8004, 8007)
$eventStartTime = (Get-Date).AddHours(-24)

# Log folders to copy
$logFolders = @(
    "C:\ProgramData\Cyvera\Logs",
    "C:\ProgramData\Bit9\Parity Agent\Logs",
    "C:\ProgramData\XDR Collector\Logs"
)

# Log Groups
$logGroups = @{
    "CortexXDR" = @(
        "C:\ProgramData\Cyvera\Logs"
    )
    "CarbonBlack" = @(
        "C:\ProgramData\Bit9\Parity Agent\Logs"
    )
    "XDR Collectpr" = @(
        "C:\ProgramData\XDR Collector\Logs"
    )
}

# Base Folder
$baseFolder = "C:\Temp"

# ==============================
# Starting
# ==============================

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$computerName = $env:COMPUTERNAME
$outputFolder = Join-Path $baseFolder "EndpointLogs_$computerName`_$timestamp"
$logsRootFolder = Join-Path $outputFolder "Logs"
$outputFile = Join-Path $outputFolder "EndpointLogs.txt"
$eventFile = Join-Path $outputFolder "FilteredEvents_Last24H.txt"
$zipFile = "$outputFolder.zip"

New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
New-Item -ItemType Directory -Path $logsRootFolder -Force | Out-Null

# ==============================
# System information
# ==============================

$os = Get-CimInstance Win32_OperatingSystem
$osVersion = "$($os.Caption) $($os.Version)"
$currentDate = Get-Date

# ==============================
# Header
# ==============================

$header = @"
============================================================
Health Check Report
Date: $currentDate
PC: $computerName
OS: $osVersion
Output folder: $outputFolder
============================================================

"@

$header | Out-File -FilePath $outputFile -Encoding UTF8

# ==============================
# Service status
# ==============================

"===== Service status =====" | Out-File -FilePath $outputFile -Append -Encoding UTF8

foreach ($serviceName in $services) {
    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        $line = "Servicio: $($service.Name) | Estado: $($service.Status)"
    }
    catch {
        $line = "Service: $serviceName | Status: Not found"
    }

    $line | Out-File -FilePath $outputFile -Append -Encoding UTF8
}

# ==============================
# CPU and memory consumption - Cortex
# ==============================

"`r`n===== CORTEX CPU / MEMORY =====" | Out-File -FilePath $outputFile -Append -Encoding UTF8

try {
    foreach ($procName in $cortexProcesses) {
        try {
            $perfData = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process |
                Where-Object { $_.Name -like "$procName*" }

            if ($perfData) {
                foreach ($proc in $perfData) {
                    $cpu = $proc.PercentProcessorTime
                    $memMB = [math]::Round(($proc.WorkingSetPrivate / 1MB), 2)

                    $line = "Proceso: $($proc.Name) | CPU(%): $cpu | Memoria Privada(MB): $memMB"
                    $line | Out-File -FilePath $outputFile -Append -Encoding UTF8
                }
            }
            else {
                "Process: $procName | Status: No encontrado" | Out-File -FilePath $outputFile -Append -Encoding UTF8
            }
        }
        catch {
            "Error querying process $procName | Detalle: $($_.Exception.Message)" | Out-File -FilePath $outputFile -Append -Encoding UTF8
        }
    }
}
catch {
    "General error obtaining Cortex CPU and memory usage: $($_.Exception.Message)" | Out-File -FilePath $outputFile -Append -Encoding UTF8
}

# ==============================
# BitLocker
# ==============================

"`r`n===== BITLOCKER STATUS =====" | Out-File -FilePath $outputFile -Append -Encoding UTF8

try {
    $bitlockerStatus = manage-bde -status 2>&1
    $bitlockerStatus | Out-File -FilePath $outputFile -Append -Encoding UTF8
}
catch {
    "Error running manage-bde -status: $($_.Exception.Message)" | Out-File -FilePath $outputFile -Append -Encoding UTF8
}

# ==============================
# Events filtered
# ==============================

"`r`n===== EVENTS FILTERED =====" | Out-File -FilePath $outputFile -Append -Encoding UTF8
"Events file: $eventFile" | Out-File -FilePath $outputFile -Append -Encoding UTF8

$eventHeader = @"
============================================================
Filtered Events Report
Date: $currentDate
PC: $computerName
OS: $osVersion
Since: $eventStartTime
IDs: $($eventIds -join ', ')
============================================================

"@

$eventHeader | Out-File -FilePath $eventFile -Encoding UTF8

try {
    $events = Get-WinEvent -FilterHashtable @{
        StartTime = $eventStartTime
        Id        = $eventIds
    } -ErrorAction SilentlyContinue | Sort-Object TimeCreated

    if ($events) {
        foreach ($event in $events) {
            @"
------------------------------------------------------------
TimeCreated : $($event.TimeCreated)
LogName     : $($event.LogName)
Provider    : $($event.ProviderName)
Id          : $($event.Id)
Level       : $($event.LevelDisplayName)
MachineName : $($event.MachineName)
Message     :
$($event.Message)
"@ | Out-File -FilePath $eventFile -Append -Encoding UTF8
        }

        "Found $($events.Count) events and were saved in: $eventFile" | Out-File -FilePath $outputFile -Append -Encoding UTF8
    }
    else {
        "No events with the requested IDs were found in the last 24 hours." | Out-File -FilePath $eventFile -Append -Encoding UTF8
        "No events with the requested IDs were found in the last 24 hours." | Out-File -FilePath $outputFile -Append -Encoding UTF8
    }
}
catch {
    "Error consultando eventos: $($_.Exception.Message)" | Out-File -FilePath $eventFile -Append -Encoding UTF8
    "Error consultando eventos: $($_.Exception.Message)" | Out-File -FilePath $outputFile -Append -Encoding UTF8
}

# ==============================
# Log copy
# ==============================

"`r`n===== LOG COPY =====" | Out-File -FilePath $outputFile -Append -Encoding UTF8

foreach ($groupName in $logGroups.Keys) {
    $groupFolder = Join-Path $logsRootFolder $groupName
    New-Item -ItemType Directory -Path $groupFolder -Force | Out-Null

    "`r`n[Grupo: $groupName]" | Out-File -FilePath $outputFile -Append -Encoding UTF8

    foreach ($path in $logGroups[$groupName]) {
        if (Test-Path $path) {
            try {
                $sourceName = Split-Path $path -Leaf

                if ([string]::IsNullOrWhiteSpace($sourceName)) {
                    $sourceName = ($path -replace "[:\\]", "_").Trim("_")
                }

                $destination = Join-Path $groupFolder $sourceName
                New-Item -ItemType Directory -Path $destination -Force | Out-Null

               
                Copy-Item -Path (Join-Path $path '*') -Destination $destination -Recurse -Force -ErrorAction Stop

                "Success: $path -> $destination" | Out-File -FilePath $outputFile -Append -Encoding UTF8
            }
            catch {
                "Error copying: $path | Detalle: $($_.Exception.Message)" | Out-File -FilePath $outputFile -Append -Encoding UTF8
            }
        }
        else {
            "Not found: $path" | Out-File -FilePath $outputFile -Append -Encoding UTF8
        }
    }
}

# ==============================
# Compresion
# ==============================

"`r`n===== COMPRESION =====" | Out-File -FilePath $outputFile -Append -Encoding UTF8

try {
    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force
    }

    Compress-Archive -Path $outputFolder -DestinationPath $zipFile -Force
    "ZIP generated correctly: $zipFile" | Out-File -FilePath $outputFile -Append -Encoding UTF8
}
catch {
    "Error generating ZIP: $($_.Exception.Message)" | Out-File -FilePath $outputFile -Append -Encoding UTF8
}

# ==============================
# Output
# ==============================

Write-Output "Reporte generated in: $outputFile"
Write-Output "Log folder: $logsRootFolder"
Write-Output "ZIP generated in: $zipFile"
