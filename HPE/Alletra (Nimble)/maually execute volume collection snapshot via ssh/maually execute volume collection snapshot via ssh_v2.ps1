# REQUIRED
# Install-Module -Name HPEAlletra6000andNimbleStoragePowerShellToolkit
# https://www.powershellgallery.com/packages/HPEAlletra6000andNimbleStoragePowerShellToolkit/3.4.1
#
# Install-Module Posh-SSH -Repository PSGallery -Verbose -Force
# https://www.powershellgallery.com/packages/Posh-SSH/3.0.4


# SETTINGS
[string][ValidateNotNullOrEmpty()] $ip_address = "1.2.3.4"  #alletra / nimble IP address

[string][ValidateNotNullOrEmpty()] $username = "MyUsername"  #username to log in to alletra / nimble

[string][ValidateNotNullOrEmpty()] $password = "MyPassword"  #password to log in to alletra / nimble

[string][ValidateNotNullOrEmpty()] $volcoll_name = "MyVolColl"  #volume collection you want to take snapshots of

[int][ValidateNotNullOrEmpty()] $max_snapshots_count = 7  #maximum number of snapshots you want to keep

[string][ValidateNotNullOrEmpty()] $snapshot_name_prefix = "script-"  #DO NOT MODIFY!

[string][ValidateNotNullOrEmpty()] $snapshot_name = $snapshot_name_prefix + $(Get-Date -Format "yyyy-MM-dd-HH-mm-ss")  #DO NOT MODIFY!

[string][ValidateNotNullOrEmpty()] $snapshot_description = "madebyscript"  #DO NOT MODIFY

[bool][ValidateNotNullOrEmpty()] $log_enable = $true  # $true = ON, $false = OFF

[string][ValidateNotNullOrEmpty()] $log_folder = "C:\Users\myUser\Desktop\"  #WITH SLASH! folder that log files are saved in

[string][ValidateNotNullOrEmpty()] $log_filename = "$snapshot_name" + ".log"  #save log to a different file everytime
#OR
#[string][ValidateNotNullOrEmpty()] $log_filename = $snapshot_name_prefix + $volcoll_name + ".log"  #append log to the same file everytime

[string][ValidateNotNullOrEmpty()] $log_path = "$log_folder" + "$log_filename"  #DO NOT MODIFY

[int][ValidateNotNullOrEmpty()] $custom_exit_code = 0  #DO NOT MODIFY

[string][ValidateNotNullOrEmpty()] $command = "volcoll --snap $volcoll_name --snapcoll_name $snapshot_name --description $snapshot_description"  #DO NOT MODIFY





#scripting begins
try {
    if ($log_enable) {
        Start-Transcript -Append $log_path
    }
    echo ""
    echo ""
    echo "### START OF SCRIPT"
    echo ""
    echo ""

    #connect to alletra or nimble
    echo "###### CONNECTING ######"
    echo ""

    $secure_password = ConvertTo-SecureString -String $password -AsPlainText -Force
    $credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $secure_password
    Connect-NSGroup -group $ip_address -credential $credentials -IgnoreServerCertificate
    echo ""
    echo ""

    #count current snapshots
    $current_snapshots = Get-NSSnapshotCollection -volcoll_name $volcoll_name
    $current_snapshots_count = $($current_snapshots | Where-Object {$_.description -eq $snapshot_description}).Count

    echo "###### SNAPSHOT LIST ######"
    $current_snapshots | Where-Object {$_.description -eq $snapshot_description} | Sort-Object -Property creation_time | Select-Object name,id ; Start-Sleep 1
    echo ""
    echo ""

    if ($current_snapshots_count -ge $max_snapshots_count) {
        #SNAPSHOT DELETION
        #if max snapshots reached then delete oldest 
        echo "###### SNAPSHOT DELETION ######"

        echo ""
        echo "### (before) current snapshots: $current_snapshots_count"
        echo "### (before) max snapshots: $max_snapshots_count"
        echo ""
        echo "### deleting oldest snapshots until there is room for a new snapshot..."
        echo ""
        while ($current_snapshots_count -ge $max_snapshots_count) {        
            #find oldest snapshot created by this script
            $oldest_snapshot =  $($current_snapshots | Where-Object {$_.description -eq $snapshot_description} | Sort-Object -Property creation_time | Select -Index 0)
            $oldest_snapshot_name = $($current_snapshots | Where-Object {$_.description -eq $snapshot_description} | Sort-Object -Property creation_time | Select -Index 0).name
            $oldest_snapshot_id = $($current_snapshots | Where-Object {$_.description -eq $snapshot_description} | Sort-Object -Property creation_time | Select -Index 0).id

            #delete oldest snapshot created by this script
            Remove-NSSnapshotCollection -id $oldest_snapshot_id
            if( $? ) {
                Write-Host "### successfully deleted oldest snapshot" -ForegroundColor GREEN
                echo "### name:`t$oldest_snapshot_name"
                echo "### id:`t`t$oldest_snapshot_id"
            }
            echo ""

            #re-count current snapshots
            $current_snapshots = Get-NSSnapshotCollection -volcoll_name $volcoll_name
            $current_snapshots_count = $($current_snapshots | Where-Object {$_.description -eq $snapshot_description}).Count
        }

        echo "### (after) current snapshots: $current_snapshots_count"
        echo "### (after) max snapshots: $max_snapshots_count"
        echo ""
        echo ""
    }

    #SNAPSHOT CREATION
    echo "###### SNAPSHOT CREATION ######"
    echo ""

    #login to storage via SSH
    $ssh_session = New-SSHSession -ComputerName $ip_address -Credential $credentials #Connect Over SSH

    #execute snapshot command via SSH
    $ssh_output = Invoke-SSHCommand -Index $ssh_session.sessionid -Command $command # Invoke Command Over SSH

    #retry snapshot command when another snapshot is already in progress
    $msg = "### another snapshot creation is already in progress! retrying."
    while ($ssh_output.Error.Trim("`r","`n") -eq "ERROR: Failed to snapshot volume collection. Object is already in requested state.") {
        $custom_exit_code = 8
        Write-Host $msg -ForegroundColor YELLOW
        $msg = $msg + "."
        Start-Sleep 2
        $ssh_output = Invoke-SSHCommand -Index $ssh_session.sessionid -Command $command # Invoke Command Over SSH
    }

    #on succesful snapshot command execution report to user
    if ($ssh_output.Error.Trim("`r","`n") -eq "INFO: Snapshot of specified volume collection is currently in progress") {
            $msg = "### creating new snapshot."
            do {
                echo $msg
                $msg = $msg + "."
                Start-Sleep 2
                $current_snapshots = Get-NSSnapshotCollection -volcoll_name $volcoll_name
            } until ($($current_snapshots | Where-Object {$_.description -eq $snapshot_description} | Sort-Object -Property creation_time -Descending | Select -Index 0).name -eq $snapshot_name) 

            echo ""            
            $current_snapshots_count = $($current_snapshots | Where-Object {$_.description -eq $snapshot_description}).Count
            $newest_snapshot_name = $($current_snapshots | Where-Object {$_.description -eq $snapshot_description} | Sort-Object -Property creation_time -Descending | Select -Index 0).name
            $newest_snapshot_id = $($current_snapshots | Where-Object {$_.description -eq $snapshot_description} | Sort-Object -Property creation_time -Descending | Select -Index 0).id            
            Write-Host "### successfully created new snapshot" -ForegroundColor GREEN
            echo "### name:`t$newest_snapshot_name"
            echo "### id:`t`t$newest_snapshot_id"
            echo ""
            echo "### (final) current snapshots: $current_snapshots_count"
            echo "### (final) max snapshots: $max_snapshots_count"
            echo ""
            echo ""
            echo "### END OF SCRIPT"
            echo ""
            echo ""
            if ($log_enable) {
                Stop-Transcript
            }
            exit $custom_exit_code
    } else {
        echo $ssh_output.Error
        throw "### ERROR: Unexpected output from SSH command!"
    }
}
catch {
    Write-Host "### ERROR: An unknown error occured!" -ForegroundColor RED
    Write-Host $_
    if ($log_enable) {
        Stop-Transcript
    }
    exit 1
}

finally {
    $Error.Clear()
}