<#
.SYNOPSIS
    Crée et configure un compte de service géré de groupe (gMSA) dans Active Directory.

.DESCRIPTION
    Cette fonction crée un compte de service géré de groupe (gMSA) et configure les SPN associés
    pour le service spécifié sur le serveur spécifié. Elle vérifie et importe/installe le module
    Active Directory si nécessaire. Les actions pertinentes sont enregistrées dans un fichier de log.

.PARAMETER ServiceAccountName
    Nom du compte de service géré à créer. (Obligatoire)

.PARAMETER AuthorizedPrincipal
    Nom du groupe ou du serveur autorisé à récupérer le mot de passe du gMSA. (Obligatoire sauf si -UseDomainComputersGroup est utilisé)

.PARAMETER UseDomainComputersGroup
    Switch optionnel pour utiliser le groupe "Ordinateurs du domaine" comme principal autorisé.

.PARAMETER ServiceNames
    Liste des noms de service pour lesquels les SPN doivent être enregistrés, séparés par des virgules. Accepte les valeurs suivantes :
    - "HTTP" : Utilisé pour les serveurs web et les applications web.
    - "HOST" : Utilisé pour les connexions de machine à machine générales.
    - "LDAP" : Utilisé pour les services d'annuaire LDAP.
    - "MSSQLSvc" : Utilisé pour les instances de Microsoft SQL Server.
    - "GC" : Utilisé pour les contrôleurs de domaine Global Catalog.
    - "RPC" : Utilisé pour les services de procédure distante.
    - "WSMAN" : Utilisé pour les services de gestion Web Services-Management (WS-Man). (Obligatoire)

.PARAMETER ServerName
    Nom du serveur pour lequel les SPN doivent être enregistrés. (Obligatoire sauf si -UseDomainComputersGroup est utilisé)

.PARAMETER DomainName
    Nom du domaine. (Obligatoire)

.EXAMPLE
    New-gMSA -ServiceAccountName "MyGmsaAccount" -ServerName "Server1" -UseDomainComputersGroup -ServiceNames "HTTP,HOST" -DomainName "yourdomain.com"

    Crée un gMSA nommé "MyGmsaAccount", autorise tous les ordinateurs du domaine à récupérer le mot de passe, et enregistre les SPN pour les services HTTP et HOST sur le serveur "Server1" dans le domaine "yourdomain.com".

#>

function New-gMSA {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ServiceAccountName,

        [Parameter(Mandatory=$false)]
        [string]$AuthorizedPrincipal,

        [Parameter(Mandatory=$false)]
        [string]$ServerName,  # Nom du serveur

        [Parameter()]
        [switch]$UseDomainComputersGroup,

        [Parameter(Mandatory=$true)]
        [string]$ServiceNames,  # Liste des services acceptés pour le SPN

        [Parameter(Mandatory=$true)]
        [string]$DomainName  # Nom du domaine
    )

    # Validation des paramètres
    if ($UseDomainComputersGroup -and $AuthorizedPrincipal) {
        Write-Host "Erreur : Les paramètres -AuthorizedPrincipal et -UseDomainComputersGroup ne peuvent pas être utilisés conjointement." -ForegroundColor Red
        exit 1
    }

    if (-not $UseDomainComputersGroup -and -not $AuthorizedPrincipal) {
        Write-Host "Erreur : Le paramètre -AuthorizedPrincipal est requis sauf si -UseDomainComputersGroup est utilisé." -ForegroundColor Red
        exit 1
    }

    # Définir le chemin du fichier de log
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $logDir = Join-Path -Path $scriptDir -ChildPath "Logs"
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory
    }
    $logFile = Join-Path -Path $logDir -ChildPath "New-gMSA.log"
    $transcribing = $false
    try {
        Start-Transcript -Path $logFile -Append -NoClobber
        $transcribing = $true
    } catch {
        Write-Host "Failed to start transcript." -ForegroundColor Red
    }

    # Fonction pour vérifier et installer/importer le module Active Directory
    function Ensure-Module {
        param (
            [string]$ModuleName
        )

        if (Get-Module -ListAvailable -Name $ModuleName) {
            if (-not (Get-Module -Name $ModuleName)) {
                Import-Module $ModuleName
                if ($?) {
                    Write-Host "Module $ModuleName imported successfully."
                } else {
                    Write-Host "Failed to import module $ModuleName."
                    if ($transcribing) { Stop-Transcript }
                    exit 1
                }
            } else {
                Write-Host "Module $ModuleName is already imported."
            }
        } else {
            Write-Host "Module $ModuleName is not installed. Installing now..."
            Install-WindowsFeature RSAT-AD-PowerShell
            Import-Module $ModuleName
            if ($?) {
                Write-Host "Module $ModuleName installed and imported successfully."
            } else {
                Write-Host "Failed to install and import module $ModuleName."
                if ($transcribing) { Stop-Transcript }
                exit 1
            }
        }
    }

    # Vérifier et importer le module Active Directory
    Ensure-Module -ModuleName "ActiveDirectory"

    # Déterminer le principal autorisé
    if ($UseDomainComputersGroup) {
        $principal = Get-ADGroup -Filter { Name -eq "Ordinateurs du domaine" }
        if (-not $principal) {
            Write-Host "Erreur : Le groupe 'Ordinateurs du domaine' n'a pas été trouvé." -ForegroundColor Red
            if ($transcribing) { Stop-Transcript }
            exit 1
        }
        $principal = $principal.DistinguishedName
    } else {
        $principal = $AuthorizedPrincipal
    }

    # Valider les noms de service
    $validServices = @("HTTP", "HOST", "LDAP", "MSSQLSvc", "GC", "RPC", "WSMAN")
    $ServiceNameList = $ServiceNames -split ","
    foreach ($ServiceName in $ServiceNameList) {
        $ServiceName = $ServiceName.Trim()
        if ($validServices -notcontains $ServiceName) {
            Write-Host "Erreur : Le service $ServiceName n'est pas valide. Les services valides sont: HTTP, HOST, LDAP, MSSQLSvc, GC, RPC, WSMAN." -ForegroundColor Red
            if ($transcribing) { Stop-Transcript }
            exit 1
        }
    }

    # Créer un nouveau gMSA
    Write-Host "Creating gMSA $ServiceAccountName with DNSHostName $ServiceAccountName.$DomainName and PrincipalsAllowedToRetrieveManagedPassword $principal."
    New-ADServiceAccount -Name $ServiceAccountName -DNSHostName "$ServiceAccountName.$DomainName" -PrincipalsAllowedToRetrieveManagedPassword $principal

    # Ajouter le serveur au gMSA si le principal autorisé n'est pas "Ordinateurs du domaine"
    if (-not $UseDomainComputersGroup) {
        Write-Host "Adding $AuthorizedPrincipal to the gMSA $ServiceAccountName."
        Add-ADComputerServiceAccount -Identity $AuthorizedPrincipal -ServiceAccount $ServiceAccountName
    }

    # Enregistrer les SPN pour le gMSA
    foreach ($ServiceName in $ServiceNameList) {
        $ServiceName = $ServiceName.Trim()
        if (-not $UseDomainComputersGroup) {
            $gmsaSPN1 = "$ServiceName/$ServerName.$DomainName"
            $gmsaSPN2 = "$ServiceName/$ServerName"
            Write-Host "Registering SPN $gmsaSPN1 for $ServiceAccountName."
            setspn -A $gmsaSPN1 "$DomainName\$ServiceAccountName$"
            Write-Host "Registering SPN $gmsaSPN2 for $ServiceAccountName."
            setspn -A $gmsaSPN2 "$DomainName\$ServiceAccountName$"
        }
    }

    Write-Host "gMSA $ServiceAccountName created and configured successfully."
    
    if ($transcribing) { Stop-Transcript }
}

# Vérifie que la fonction est appelée avec les paramètres requis
if ($PSCmdlet.MyInvocation.BoundParameters.Count -eq 0) {
    # Demande des valeurs de paramètres à l'utilisateur
    $ServiceAccountName = Read-Host "Enter the Service Account Name"
    $UseDomainComputersGroup = Read-Host "Use Ordinateurs du domaine Group? (yes/no)"
    
    if ($UseDomainComputersGroup -eq "yes") {
        $UseDomainComputersGroup = $true
        $AuthorizedPrincipal = $null
        $ServerName = $null
    } else {
        $UseDomainComputersGroup = $false
        $AuthorizedPrincipal = Read-Host "Enter the Authorized Principal"
        $ServerName = Read-Host "Enter the Server Name"
    }
    
    $ServiceNames = Read-Host "Enter the Service Names (HTTP, HOST, LDAP, MSSQLSvc, GC, RPC, WSMAN) separated by commas"
    $DomainName = Read-Host "Enter the Domain Name"
    
    # Appelle la fonction avec les valeurs saisies
    New-gMSA -ServiceAccountName $ServiceAccountName -AuthorizedPrincipal $AuthorizedPrincipal -UseDomainComputersGroup:$UseDomainComputersGroup -ServiceNames $ServiceNames -ServerName $ServerName -DomainName $DomainName
}