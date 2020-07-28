﻿# Verify Running as Admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
If (-not $isAdmin) {
    Write-Host "-- Restarting as Administrator" -ForegroundColor Cyan ; Start-Sleep -Seconds 1

    if($PSVersionTable.PSEdition -eq "Core") {
        Start-Process pwsh.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs 
    } else {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs 
    }

    exit
}

#region Functions
. $PSScriptRoot\0_Shared.ps1 # [!build-include-inline]
#endregion

#region Do some clenaup
    #Start
        $StartDateTime = Get-Date

    #load LabConfig
        . "$PSScriptRoot\LabConfig.ps1"

        if (-not ($LabConfig.Prefix)){
            $labconfig.Prefix="$($PSScriptRoot | Split-Path -Leaf)-"
        }

    #grab all VMs, switches and DC
        $VMs=Get-VM -Name "$($LabConfig.Prefix)*" | Where-Object Name -ne "$($LabConfig.Prefix)DC" -ErrorAction SilentlyContinue | Sort-Object -Property Name
        $vSwitch=Get-VMSwitch "$($labconfig.prefix)$($LabConfig.SwitchName)" -ErrorAction SilentlyContinue
        $extvSwitch=Get-VMSwitch "$($labconfig.prefix)$($LabConfig.SwitchName)-External" -ErrorAction SilentlyContinue
        $DC=Get-VM "$($LabConfig.Prefix)DC" -ErrorAction SilentlyContinue

    #List VMs, Switches and DC
        If ($VMs){
            WriteInfoHighlighted "VMs:"
            $VMS | ForEach-Object {
                WriteInfo "`t $($_.Name)"
            }
        }

        if ($vSwitch){
            WriteInfoHighlighted "vSwitch:"
            WriteInfo "`t $($vSwitch.name)"
        }

        if ($extvSwitch){
            WriteInfoHighlighted "External vSwitch:"
            WriteInfo "`t $($extvSwitch.name)"
        }

        if ($DC){
            WriteInfoHighlighted "DC:"
            WriteInfo "`t $($DC.Name)"
        }

    #just one more space
        WriteInfo ""

    # This is only needed if you kill deployment script in middle when it mounts VHD into mountdir. 
        if ((Get-ChildItem -Path "$PSScriptRoot\temp\mountdir" -ErrorAction SilentlyContinue)){
            Dismount-WindowsImage -Path "$PSScriptRoot\temp\mountdir" -Discard -ErrorAction SilentlyContinue
        }
        if ((Get-ChildItem -Path "$env:Temp\WSLAbMountdir" -ErrorAction SilentlyContinue)){
            Dismount-WindowsImage -Path "$env:Temp\WSLAbMountdir" -Discard -ErrorAction SilentlyContinue
        }

#ask for cleanup and clean all if confirmed.
    if (($extvSwitch) -or ($vSwitch) -or ($VMs) -or ($DC)){
        WriteInfoHighlighted "This script will remove all items listed above. Do you want to remove it?"
        if ((read-host "(type Y or N)") -eq "Y"){
            WriteSuccess "You typed Y .. Cleaning lab"
            if ($DC){
                WriteInfoHighlighted "Removing DC"
                WriteInfo "`t Turning off $($DC.Name)"
                $DC | Stop-VM -TurnOff -Force -WarningAction SilentlyContinue
                WriteInfo "`t Restoring snapshot on $($DC.Name)"
                $DC | Restore-VMsnapshot -Name Initial -Confirm:$False -ErrorAction SilentlyContinue
                Start-Sleep 2
                WriteInfo "`t Removing snapshot from $($DC.Name)"
                $DC | Remove-VMsnapshot -name Initial -Confirm:$False -ErrorAction SilentlyContinue
                WriteInfo "`t Removing DC $($DC.Name)"
                $DC | Remove-VM -Force
            }
            if ($VMs){
                WriteInfoHighlighted "Removing VMs"
                foreach ($VM in $VMs){
                WriteInfo "`t Removing VM $($VM.Name)"
                $VM | Stop-VM -TurnOff -Force -WarningAction SilentlyContinue
                $VM | Remove-VM -Force
                }
            }
            if (($vSwitch)){
                WriteInfoHighlighted "Removing vSwitch"
                WriteInfo "`t Removing vSwitch $($vSwitch.Name)"
                $vSwitch | Remove-VMSwitch -Force
            }
            if (($extvSwitch)){
                WriteInfoHighlighted "Removing vSwitch"
                WriteInfo "`t Removing vSwitch $($extvSwitch.Name)"
                $extvSwitch | Remove-VMSwitch -Force
            }
            #Cleanup folders       
            if ((test-path "$PSScriptRoot\LAB\VMs") -or (test-path "$PSScriptRoot\temp") ){
                WriteInfoHighlighted "Cleaning folders"
                "$PSScriptRoot\LAB\VMs","$PSScriptRoot\temp" | ForEach-Object {
                    if ((test-path -Path $_)){
                        WriteInfo "`t Removing folder $_"
                        remove-item $_ -Confirm:$False -Recurse
                    }    
                }
            }

            #Unzipping configuration files as VM was removed few lines ago-and it deletes vm configuration... 
                $zipfile = "$PSScriptRoot\LAB\DC\Virtual Machines.zip"
                $zipoutput = "$PSScriptRoot\LAB\DC\"
                Microsoft.PowerShell.Archive\Expand-Archive -Path $zipfile -DestinationPath $zipoutput -Force

            # Telemetry
            if((Get-TelemetryLevel) -in $TelemetryEnabledLevels) {
                WriteInfo "Telemetry is set to $(Get-TelemetryLevel) level from $(Get-TelemetryLevelSource)"
                $metrics = @{
                    'script.duration' = ((Get-Date) - $StartDateTime).TotalSeconds
                    'lab.removed.count' = ($VMs | Measure-Object).Count
                }
                Send-TelemetryEvent -Event "Cleanup" -Metrics $metrics -NickName $LabConfig.TelemetryNickName | Out-Null
            }

            #finishing    
                WriteSuccess "Job Done! Press enter to continue ..."
                $exit=Read-Host
        }else {
            WriteErrorAndExit "You did not type Y"
        }
    }else{
        WriteErrorAndExit "No VMs and Switches with prefix $($LabConfig.Prefix) detected. Exitting"
    }
#endregion