######################################################################################################################################
#                                                                                                                                    #
# Diagnostic data collector script for AZHCI registration related issues.                                                            #
# This script collects cluster registration, event log, and Azure Arc agent data without changing installed modules.                 #
#                                                                                                                                    #
######################################################################################################################################

Function Collect-HCIRegistrationInfo
      <#
        .SYNOPSIS
        Collect Azure Stack HCI registration related logs and Azure Arc setup related logs.

        .DESCRIPTION
        This script collects cluster registration and Arc agent related data without installing or updating NuGet providers or PowerShell modules.
        The HCI Debug event log is enabled on all nodes before a transcripted PowerShell window is opened for reproducing the registration issue.
        It can run remotely or directly on the cluster.

        .PARAMETER ClusterName
        Name of the cluster

        .PARAMETER WorkFolder
        Working path where the data will be collected (current location by default)

        .PARAMETER ConnectionCheck
        Run Invoke-AzStackHciConnectivityValidation when the AzStackHci.EnvironmentChecker module is already installed.
        The check is enabled by default and can be disabled with $false.

        .EXAMPLE
        PS> Collect-HCIRegistrationInfo -ClusterName Cluster -ConnectionCheck $false

    #>
{
    Param
    (
    $ClusterName = (Get-Cluster), #Name of the cluster
    $WorkFolder = (Get-Location), #Working folder location, default is where you run the cmdlet
    $ConnectionCheck = $true #Check connection
    )

$nodes = get-clusternode -Cluster $clustername
$path = New-Item -ItemType Directory -Path (Get-Item -Path $WorkFolder).FullName -Name $clustername"_RegistrationInfo" -Force
$path.fullname

Write-Host "Enabling Microsoft-AzureStack-HCI/Debug on all cluster nodes" -ForegroundColor Cyan
foreach ($node in $nodes)
    {
        try
            {
                Invoke-Command -ComputerName $node.Name -ErrorAction Stop -ScriptBlock {
                    Wevtutil.exe sl /q /e:true Microsoft-AzureStack-HCI/Debug
                    (New-Object System.Diagnostics.Eventing.Reader.EventLogConfiguration "Microsoft-AzureStack-HCI/Debug").IsEnabled
                } | Out-Null
                Write-Host "$($node.Name) - Debug log enabled" -ForegroundColor Green
            }
        catch
            {
                throw "Failed to enable Microsoft-AzureStack-HCI/Debug on $($node.Name): $($_.Exception.Message)"
            }
    }

$TranscriptPath = Join-Path $path.FullName ("RegistrationRepro-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$EscapedTranscriptPath = $TranscriptPath.Replace("'", "''")
$ReproScript = @"
`$ErrorActionPreference = 'Continue'
Start-Transcript -Path '$EscapedTranscriptPath' -Force
function Complete-HCIRegistrationRepro {
    Stop-Transcript
    exit
}
Write-Host ''
Write-Host 'HCI registration reproduction capture is active.' -ForegroundColor Cyan
Write-Host 'Run the registration or repair-registration command in this window.' -ForegroundColor Yellow
Write-Host 'When the attempt finishes, run Complete-HCIRegistrationRepro.' -ForegroundColor Yellow
Write-Host 'The transcript and RegisterHCI logs created in this folder will be included in the data bundle.' -ForegroundColor Cyan
Write-Host ''
"@
$EncodedReproScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ReproScript))
$WindowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$ReproProcess = Start-Process -FilePath $WindowsPowerShell -ArgumentList "-NoLogo -NoExit -EncodedCommand $EncodedReproScript" -WorkingDirectory $path.FullName -PassThru

Write-Host "Waiting for registration reproduction in PowerShell process $($ReproProcess.Id)." -ForegroundColor Cyan
Write-Host "Complete the attempt and run Complete-HCIRegistrationRepro in the opened window." -ForegroundColor Yellow
Wait-Process -Id $ReproProcess.Id

if (-not (Test-Path -LiteralPath $TranscriptPath))
    {
        Write-Warning "The reproduction PowerShell window closed without creating the expected transcript: $TranscriptPath"
    }

foreach ($node in $nodes)
    {
        Write-Host "Checking node $node" -ForegroundColor Cyan
        $session = New-PSSession -ComputerName $Node.Name
        Invoke-Command -session $session -scriptblock {

        # Creating working folder
        New-Item -ItemType Directory -Path c:\ -Name $using:node -ErrorAction SilentlyContinue
        $ExportPath =  (Get-Item "C:\$using:node").FullName

        # Cmdlets to drop in TXT and XML forms
                #
                # cmd is of the form "cmd arbitraryConstantArgs -argForComputerOrSessionSpecification"
                # will be trimmed to "cmd" for logging
                # _A_ token will be replaced with the chosen cluster access node
                # _C_ token will be replaced with node fqdn for cimsession/computername callouts
                # _N_ token will be replaced with node non-fqdn

        Write-Host "Collect registration related data" -NoNewLine
        $cmdlist =
            @{C = 'Get-AzureStackHci'; F = $null},
            @{C = 'Get-AzureStackHCIArcIntegration'; F = $null},
            @{C = 'Get-ClusteredScheduledTask | fl *'; F = $null},
            @{C = 'Get-AzureStackHCIAttestation'; F = $null},
            @{C = 'Get-AzStackHCIVMAttestation'; F = $null}

        Foreach ($cmd in $cmdlist)
                {

                    $cmdstr = $cmd.C
                    $file = $cmd.F

                    # Default rule: base cmdlet name no dash
                    if ($null -eq $file) {
                        $LocalFile = (Join-Path ($ExportPath+"\")((($cmdstr.split(' '))[0] -replace "-","")))
                    } else {
                        $LocalFile = (Join-Path ($ExportPath+"\")$file)
                    }

                    try {

                        $cmdex = $cmdstr #-replace '_C_',$using:Node -replace '_N_',$using:Node -replace '_A_',$using:Node
                        $out = Invoke-Expression $cmdex
                        # capture as txt and xml for quick analysis according to taste
                        $out | Format-Table -AutoSize | Out-File -Width 9999 -Encoding ascii -FilePath "$LocalFile.txt" -Confirm:$false
                        $out | Export-Clixml -Path "$LocalFile.xml" -confirm:$false
                        }
                    catch {
                        Write-host "'$cmdex' failed for node $Node ($($_.Exception.Message))"
                    }
                }
        Write-host " - " -NoNewLine; Write-Host "OK" -ForegroundColor Green
        If ($using:connectioncheck -eq $true)
            {
            If (Get-Module -ListAvailable AzStackHci.EnvironmentChecker -ErrorAction SilentlyContinue)
                {
                Invoke-AzStackHciConnectivityValidation -outputpath $ExportPath
                }
            Else
                {
                $message = "AzStackHci.EnvironmentChecker is not installed. Connectivity validation was skipped; the collector does not install or update modules."
                Write-Warning $message
                $message | Out-File $ExportPath"\"$using:node'-ConnectivityValidation-Skipped.txt'
                }
            }
        Else
            {
                Write-host "Connection check skipped"
            }

        # Collecting event logs
            Write-host `n
            Write-host "Collecting system related logs" -NoNewLine
            $logPath = $ExportPath+"\"+$using:node+"-System.csv" ; Get-WinEvent -ComputerName $using:node -LogName System -Oldest | Export-Csv -Path $logPath
            $logPath = $ExportPath+"\"+$using:node+'-Application.csv' ; Get-WinEvent -ComputerName $using:node -LogName Application -Oldest | Export-Csv -Path $logPath
            $logPath = $ExportPath+"\"+$using:node+'-Admin.csv' ; Get-WinEvent -ComputerName $using:node -LogName Microsoft-AzureStack-HCI/Admin -Oldest | select TimeCreated, Id, LevelDisplayName,Message | Export-Csv -Path $logPath
            $logPath = $ExportPath+"\"+$using:node+'-Debug.csv' ; Get-WinEvent -ComputerName $using:node -LogName Microsoft-AzureStack-HCI/Debug -Oldest | select TimeCreated, Id, LevelDisplayName,Message | Export-Csv -Path $logPath
            $logPath = $ExportPath+"\"+$using:node+'-BootOp.csv' ; Get-WinEvent -ComputerName $using:node -LogName Microsoft-Windows-Kernel-Boot/Operational -Oldest | select TimeCreated, Id, LevelDisplayName,Message | Export-Csv -Path $logPath
            $logPath = $ExportPath+"\"+$using:node+'-IOOp.csv' ; Get-WinEvent -ComputerName $using:node -LogName Microsoft-Windows-Kernel-IO/Operational -Oldest | select TimeCreated, Id, LevelDisplayName,Message | Export-Csv -Path $logPath
            $logPath = $ExportPath+"\"+$using:node+'-systeminfo.txt' ; systeminfo.exe | out-file $logPath

        #ARC diagnostic
            Write-host " - " -NoNewLine; Write-Host "OK" -ForegroundColor Green
            Write-host "Collecting Arc agent related logs" -NoNewLine
            Azcmagent show | Out-File $ExportPath"\"$using:node'-Azcmagent.txt'
            Get-ChildItem -Path HKLM:\Cluster\ArcForServers | Out-File $ExportPath"\"$using:node'-ArcForServers_registry.txt'
            Copy-Item -Path "C:\Windows\Tasks\ArcforServers\*" -Destination $ExportPath"\"
            Copy-Item -Path "C:\ProgramData\AzureConnectedMachineAgent\Log\*" -Destination $ExportPath"\"
            Write-host " - " -NoNewLine; Write-Host "OK" -ForegroundColor Green

        }
        # Copy and compress data
        Write-Host "Copy data" -NoNewLine
        Copy-Item -Path "c:\$node" -Recurse -Destination "$path\" -FromSession $session -force
        Remove-PSSession $session -Confirm:$false
        Write-host " - " -NoNewLine; Write-Host "OK" -ForegroundColor Green
    }

    #save output
    $date = (Get-Date -Format yyyyMMdd_HHMM).tostring()
    Compress-Archive -Path $path -DestinationPath $WorkFolder"\"$ClusterName"_RegistrationInfo_"$date".zip"
    Write-host "Diagnostics finished. Check for the zip file: " (Get-ChildItem $WorkFolder"\"$ClusterName"_RegistrationInfo_"$date".zip").fullname
}
