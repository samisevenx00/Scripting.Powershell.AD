# Import the Active Directory module
Import-Module ActiveDirectory

# Get the current date
$currentDate = Get-Date
$dateString = $currentDate.ToString("yyyy-MM-dd")

# Set the output directory path
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$outputDir = "$scriptRoot\$dateString"

# Create the directory if it doesn't exist
if (-Not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

function Export-ExpiredAccounts {
    param (
        [string]$outputPath
    )
    # Get the date 90 days ago
    $date90DaysAgo = (Get-Date).AddDays(-90)
    # Get users with password expired for more than 90 days
    $expiredUsers = Get-ADUser -Filter {PasswordLastSet -le $date90DaysAgo} -Properties Name, PasswordLastSet, PasswordExpired, LastLogonDate | Where-Object { $_.PasswordExpired -eq $true }
    # Prepare data for export
    $exportData = $expiredUsers | Select-Object Name, PasswordLastSet, PasswordExpired, @{Name="LastLogonDate"; Expression={if ($_.LastLogonDate) { $_.LastLogonDate } else { "Never Logged In" }}}
    # Export to CSV
    $exportData | Export-Csv -Path $outputPath -NoTypeInformation
    Write-Host "Exported expired accounts to $outputPath"
}

function Export-LockedOutAccounts {
    param (
        [string]$outputPath
    )
    # Get users that are locked out
    $lockedOutUsers = Search-ADAccount -LockedOut -UsersOnly | Get-ADUser -Properties LockedOut, LastLogonDate
    # Prepare data for export
    $exportData = $lockedOutUsers | Select-Object Name, LockedOut, @{Name="LastLogonDate"; Expression={if ($_.LastLogonDate) { $_.LastLogonDate } else { "Never Logged In" }}}
    # Export to CSV
    $exportData | Export-Csv -Path $outputPath -NoTypeInformation
    Write-Host "Exported locked out accounts to $outputPath"
}

function Export-NeverExpireAccounts {
    param (
        [string]$outputPath
    )
    # Get users with password that never expires
    $neverExpireUsers = Get-ADUser -Filter {PasswordNeverExpires -eq $true} -Properties Name, PasswordNeverExpires, LastLogonDate
    # Prepare data for export
    $exportData = $neverExpireUsers | Select-Object Name, PasswordNeverExpires, @{Name="LastLogonDate"; Expression={if ($_.LastLogonDate) { $_.LastLogonDate } else { "Never Logged In" }}}
    # Export to CSV
    $exportData | Export-Csv -Path $outputPath -NoTypeInformation
    Write-Host "Exported accounts with password never expire to $outputPath"
}

# Define output file paths
$expiredAccountsPath = "$outputDir\expired_accounts_$dateString.csv"
$lockedOutAccountsPath = "$outputDir\lockedout_accounts_$dateString.csv"
$neverExpireAccountsPath = "$outputDir\never_expire_accounts_$dateString.csv"

# Run the export functions
Export-ExpiredAccounts -outputPath $expiredAccountsPath
Export-LockedOutAccounts -outputPath $lockedOutAccountsPath
Export-NeverExpireAccounts -outputPath $neverExpireAccountsPath

Write-Host "All exports completed. Files are located in $outputDir"
