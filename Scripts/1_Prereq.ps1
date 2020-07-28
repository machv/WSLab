# Verify Running as Admin
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

# Skipping 10 lines because if running when all prereqs met, statusbar covers powershell output
1..10 | ForEach-Object { Write-Host "" }

#region Functions
. $PSScriptRoot\0_Shared.ps1 # [!build-include-inline]

function  Get-WindowsBuildNumber { 
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    return [int]($os.BuildNumber) 
} 
#endregion

#region Initialization


# grab Time and start Transcript
    Start-Transcript -Path "$ScriptRoot\Prereq.log"
    $StartDateTime = Get-Date
    WriteInfo "Script started at $StartDateTime"
    WriteInfo "`nWSLab Version $wslabVersion"

#Load LabConfig....
    . "$ScriptRoot\LabConfig.ps1"

# Telemetry Event
    if((Get-TelemetryLevel) -in $TelemetryEnabledLevels) {
        WriteInfo "Telemetry is set to $(Get-TelemetryLevel) level from $(Get-TelemetryLevelSource)"
        Send-TelemetryEvent -Event "Prereq.Start" -NickName $LabConfig.TelemetryNickName | Out-Null
    }

#define some variables if it does not exist in labconfig
    If (!$LabConfig.DomainNetbiosName){
        $LabConfig.DomainNetbiosName="Corp"
    }

    If (!$LabConfig.DomainName){
        $LabConfig.DomainName="Corp.contoso.com"
    }

#set TLS 1.2 for github downloads
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#endregion

#region OS checks and folder build
# Checking for Compatible OS
    WriteInfoHighlighted "Checking if OS is Windows 10 1511 (10586)/Server 2016 or newer"

    $BuildNumber=Get-WindowsBuildNumber
    if ($BuildNumber -ge 10586){
        WriteSuccess "`t OS is Windows 10 1511 (10586)/Server 2016 or newer"
    }else{
        WriteErrorAndExit "`t Windows version  $BuildNumber detected. Version 10586 and newer is needed. Exiting"
    }

# Checking Folder Structure
    "ParentDisks","Temp","Temp\DSC","Temp\ToolsVHD\DiskSpd","Temp\ToolsVHD\SCVMM\ADK","Temp\ToolsVHD\SCVMM\ADKWinPE","Temp\ToolsVHD\SCVMM\SQL","Temp\ToolsVHD\SCVMM\SCVMM","Temp\ToolsVHD\SCVMM\UpdateRollup","Temp\ToolsVHD\VMFleet" | ForEach-Object {
        if (!( Test-Path "$PSScriptRoot\$_" )) { New-Item -Type Directory -Path "$PSScriptRoot\$_" } }

    "Temp\ToolsVHD\SCVMM\ADK\Copy_ADK_with_adksetup.exe_here.txt","Temp\ToolsVHD\SCVMM\ADKWinPE\Copy_ADKWinPE_with_adkwinpesetup.exe_here.txt","Temp\ToolsVHD\SCVMM\SQL\Copy_SQL2017_or_SQL2019_with_setup.exe_here.txt","Temp\ToolsVHD\SCVMM\SCVMM\Copy_SCVMM_with_setup.exe_here.txt","Temp\ToolsVHD\SCVMM\UpdateRollup\Copy_SCVMM_Update_Rollup_MSPs_here.txt" | ForEach-Object {
        if (!( Test-Path "$PSScriptRoot\$_" )) { New-Item -Type File -Path "$PSScriptRoot\$_" } }
#endregion

#region Download Scripts

#add scripts for VMM
    $Filenames="1_SQL_Install","2_ADK_Install","3_SCVMM_Install"
    foreach ($Filename in $filenames){
        $Path="$PSScriptRoot\Temp\ToolsVHD\SCVMM\$Filename.ps1"
        If (Test-Path -Path $Path){
            WriteSuccess "`t $Filename is present, skipping download"
        }else{
            $FileContent=$null
            $FileContent = (Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/Microsoft/WSLab/master/Tools/$Filename.ps1").Content
            if ($FileContent){
                $script = New-Item $Path -type File -Force
                $FileContent=$FileContent -replace "PasswordGoesHere",$LabConfig.AdminPassword #only applies to 1_SQL_Install and 3_SCVMM_Install.ps1
                $FileContent=$FileContent -replace "DomainNameGoesHere",$LabConfig.DomainNetbiosName #only applies to 1_SQL_Install and 3_SCVMM_Install.ps1
                Set-Content -path $script -value $FileContent
            }else{
                WriteErrorAndExit "Unable to download $Filename."
            }
        }
    }

#Download SetupVMFleet script
    $Filename="SetupVMFleet"
    $Path="$PSScriptRoot\Temp\ToolsVHD\$FileName.ps1"
    If (Test-Path -Path $Path){
        WriteSuccess "`t $Filename is present, skipping download"
    }else{
        $FileContent = $null
        $FileContent = (Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/Microsoft/WSLab/master/Tools/$Filename.ps1").Content
        if ($FileContent){
            $script = New-Item $Path -type File -Force
            $FileContent=$FileContent -replace "PasswordGoesHere",$LabConfig.AdminPassword
            $FileContent=$FileContent -replace "DomainNameGoesHere",$LabConfig.DomainNetbiosName
            Set-Content -path $script -value $FileContent
        }else{
            WriteErrorAndExit "Unable to download $Filename."
        }
    }

# add createparentdisks and DownloadLatestCU scripts to Parent Disks folder
    $FileNames="CreateParentDisk","DownloadLatestCUs"
    foreach ($filename in $filenames){
        $Path="$PSScriptRoot\ParentDisks\$FileName.ps1"
        If (Test-Path -Path $Path){
            WriteSuccess "`t $Filename is present, skipping download"
        }else{
            $FileContent = $null
            $FileContent = (Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/Microsoft/WSLab/master/Tools/$FileName.ps1").Content
            if ($FileContent){
                $script = New-Item "$PSScriptRoot\ParentDisks\$FileName.ps1" -type File -Force
                Set-Content -path $script -value $FileContent
            }else{
                WriteErrorAndExit "Unable to download $Filename."
            }
        }
    }

# Download convert-windowsimage into Temp
WriteInfoHighlighted "Testing Convert-windowsimage presence"
If ( Test-Path -Path "$PSScriptRoot\Temp\Convert-WindowsImage.ps1" ) {
    WriteSuccess "`t Convert-windowsimage.ps1 is present, skipping download"
}else{ 
    WriteInfo "`t Downloading Convert-WindowsImage"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/microsoft/WSLab/master/Tools/Convert-WindowsImage.ps1" -OutFile "$PSScriptRoot\Temp\Convert-WindowsImage.ps1"
    } catch {
        WriteError "`t Failed to download Convert-WindowsImage.ps1!"
    }
}
#endregion

#region some tools to download
# Downloading diskspd if its not in ToolsVHD folder
    WriteInfoHighlighted "Testing diskspd presence"
    If ( Test-Path -Path "$PSScriptRoot\Temp\ToolsVHD\DiskSpd\diskspd.exe" ) {
        WriteSuccess "`t Diskspd is present, skipping download"
    }else{ 
        WriteInfo "`t Diskspd not there - Downloading diskspd"
        try {
            <# aka.ms/diskspd changed. Commented
            $webcontent  = Invoke-WebRequest -Uri "https://aka.ms/diskspd" -UseBasicParsing
            if($PSVersionTable.PSEdition -eq "Core") {
                $link = $webcontent.Links | Where-Object data-url -Match "/Diskspd.*zip$"
                $downloadUrl = "{0}://{1}{2}" -f $webcontent.BaseResponse.RequestMessage.RequestUri.Scheme, $webcontent.BaseResponse.RequestMessage.RequestUri.Host, $link.'data-url'
            } else {
                $downloadurl = $webcontent.BaseResponse.ResponseUri.AbsoluteUri.Substring(0,$webcontent.BaseResponse.ResponseUri.AbsoluteUri.LastIndexOf('/'))+($webcontent.Links | where-object { $_.'data-url' -match '/Diskspd.*zip$' }|Select-Object -ExpandProperty "data-url")
            }
            #>
            $downloadurl="https://github.com/microsoft/diskspd/releases/download/v2.0.21a/DiskSpd-2.0.21a.zip"
            Invoke-WebRequest -Uri $downloadurl -OutFile "$PSScriptRoot\Temp\ToolsVHD\DiskSpd\diskspd.zip"
        }catch{
            WriteError "`t Failed to download Diskspd!"
        }
        # Unnzipping and extracting just diskspd.exe x64
            Microsoft.PowerShell.Archive\Expand-Archive "$PSScriptRoot\Temp\ToolsVHD\DiskSpd\diskspd.zip" -DestinationPath "$PSScriptRoot\Temp\ToolsVHD\DiskSpd\Unzip"
            Copy-Item -Path (Get-ChildItem -Path "$PSScriptRoot\Temp\ToolsVHD\diskspd\" -Recurse | Where-Object {$_.Directory -like '*amd64*' -and $_.name -eq 'diskspd.exe' }).fullname -Destination "$PSScriptRoot\Temp\ToolsVHD\DiskSpd\"
            Remove-Item -Path "$PSScriptRoot\Temp\ToolsVHD\DiskSpd\diskspd.zip"
            Remove-Item -Path "$PSScriptRoot\Temp\ToolsVHD\DiskSpd\Unzip" -Recurse -Force
    }

#Download VMFleet
    WriteInfoHighlighted "Testing VMFleet presence"
    If ( Test-Path -Path "$PSScriptRoot\Temp\ToolsVHD\VMFleet\install-vmfleet.ps1" ) {
        WriteSuccess "`t VMFleet is present, skipping download"
    }else{ 
        WriteInfo "`t VMFleet not there - Downloading VMFleet"
        try {
            $downloadurl = "https://github.com/Microsoft/diskspd/archive/master.zip"
            Invoke-WebRequest -Uri $downloadurl -OutFile "$PSScriptRoot\Temp\ToolsVHD\VMFleet\VMFleet.zip"
        }catch{
            WriteError "`t Failed to download VMFleet!"
        }
        # Unnzipping and extracting just VMFleet
            Microsoft.PowerShell.Archive\Expand-Archive "$PSScriptRoot\Temp\ToolsVHD\VMFleet\VMFleet.zip" -DestinationPath "$PSScriptRoot\Temp\ToolsVHD\VMFleet\Unzip"
            Copy-Item -Path "$PSScriptRoot\Temp\ToolsVHD\VMFleet\Unzip\diskspd-master\Frameworks\VMFleet\*" -Destination "$PSScriptRoot\Temp\ToolsVHD\VMFleet\"
            Remove-Item -Path "$PSScriptRoot\Temp\ToolsVHD\VMFleet\VMFleet.zip"
            Remove-Item -Path "$PSScriptRoot\Temp\ToolsVHD\VMFleet\Unzip" -Recurse -Force
    }
#endregion

#region Downloading required Posh Modules
# Downloading modules into Temp folder if needed.

    $modules=("xActiveDirectory","3.0.0.0"),("xDHCpServer","2.0.0.0"),("xDNSServer","1.15.0.0"),("NetworkingDSC","7.4.0.0"),("xPSDesiredStateConfiguration","8.10.0.0")
    foreach ($module in $modules){
        WriteInfoHighlighted "Testing if modules are present" 
        $modulename=$module[0]
        $moduleversion=$module[1]
        if (!(Test-Path "$PSScriptRoot\Temp\DSC\$modulename\$Moduleversion")){
            WriteInfo "`t Module $module not found... Downloading"
            #Install NuGET package provider   
            if ((Get-PackageProvider -Name NuGet) -eq $null){   
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Confirm:$false -Force
            }
            Find-DscResource -moduleName $modulename -RequiredVersion $moduleversion | Save-Module -Path "$PSScriptRoot\Temp\DSC"
        }else{
            WriteSuccess "`t Module $modulename version found... skipping download"
        }
    }

# Installing DSC modules if needed
    foreach ($module in $modules) {
        WriteInfoHighlighted "Testing DSC Module $module Presence"
        # Check if Module is installed
        if ((Get-DscResource -Module $Module[0] | where-object {$_.version -eq $module[1]}) -eq $Null) {
            # module is not installed - install it
            WriteInfo "`t Module $module will be installed"
            $modulename=$module[0]
            $moduleversion=$module[1]
            Copy-item -Path "$PSScriptRoot\Temp\DSC\$modulename" -Destination "C:\Program Files\WindowsPowerShell\Modules" -Recurse -Force
            WriteSuccess "`t Module was installed."
            Get-DscResource -Module $modulename
        } else {
            # module is already installed
            WriteSuccess "`t Module $Module is already installed"
        }
    }

#endregion

# Telemetry Event
if((Get-TelemetryLevel) -in $TelemetryEnabledLevels) {
    $metrics = @{
        'script.duration' = ((Get-Date) - $StartDateTime).TotalSeconds
    }
 
    Send-TelemetryEvent -Event "Prereq.End" -Metrics $metrics -NickName $LabConfig.TelemetryNickName | Out-Null
}

# finishing 
WriteInfo "Script finished at $(Get-date) and took $(((get-date) - $StartDateTime).TotalMinutes) Minutes"
Stop-Transcript
WriteSuccess "Press enter to continue..."
Read-Host | Out-Null
