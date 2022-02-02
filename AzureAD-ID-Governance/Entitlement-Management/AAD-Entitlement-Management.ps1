# *****************************************************************************
# *                                                                           *
# *       W H A T    D O E S    T H I S    S C R I P T    D O                 *
# *                                                                           *
# *****************************************************************************
#
#
# Define the script parameters
# This script uses an input file for entitlement management. It is intended to create the Catalog, access packages and resource roles.
# The input file should be in csv format and should have below column names
# Script version = V1
# Script authors -- Mohanan Ambika Rohit Nair
#
#
#
# Script Capability:
# 1. Validates the that Access package catalog is present or not , If not then it will create the access package catalog.
# 2. Validates the that group is Present  or not , If not then it will create the group.
# 3. Validates the that Access package is Present  or not , If not then it will create the access package.
# 4. validates if group is added as resource in catalog of not, if not then it will add the newly created group as resource in catalog.
# 5. Validates if the group is added as a resource in Access package or not, if not it will add the group to access package as resource.
# 6. Validates if the connected organization value is present in input file and if it is present then it validates if the domain's AAD is added as connected or not , If not added it will add the input domain's AAD as connected Organization.
# 7. IT validates if the Policy with the name ( given in input  file) is present with in the given Access package or not, If the policy is not present in the respective Access package it will create the policy.
# 8. Policy creation has few parameters across the Requestor type, the script validates the requestor value and accordingly will proceed with the policy creation.
# RequestorScopeType can have following values:
# 
# AllExistingDirectoryMemberUsers              ------- No Further value required
# AllExistingDirectorySubjects                 ------- No Further Value required
# AllConfiguredConnectedOrganizationSubjects   ------- No Further Value required
# AllExternalSubjects                          ------- No Further Value required
# SpecificDirectorySubjects                    ------- Value required for a single group whose member can be request "RequestorGroup" columns of input file.
# SpecificConnectedOrganizationSubjects        ------- Value required for one of the domain of connected org AAD in "ConnectedORG" columns of input file.
#
#
#


# *****************************************************************************
# *                                                                           *
# *             S C R I P T    P A R A M E T E R S                            *
# *                                                                           *
# *****************************************************************************
#
#
# Variables need to be entered
# $TenantID = Tenant ID of the Azure AD tenant where the entitlement management needs to be configured
# $ClientID = Client ID of the application which is configured as Native Application and enabled for Public Client option.
#  
# CSV File Collumns\Parameter needed for this script
#        
#        APCDisplayName ------------- Access Package Catalog Display Name
#        APCDescription ------------- Access Package Catalog Description
#        HUB Team Names ------------- Organization Team name who is going to use these Groups\Access Packages (Not used in Script)
#        AADGroupDisplayName -------- Display Name of the Azure AD Group which will be the Resource of this Access Pcakage
#        AADGroupDescription -------- Description of the Azure AD Group which will be the Resource of this Access Pcakage
#        AADGroupMailNickName ------- MailNickName of the Azure AD Group which will be the Resource of this Access Pcakage
#        APDisplayName -------------- Access Package Display Name
#        APDescription -------------- Access Package Description
#        PolicyDisplayName ---------- Access Package Policy's Display Name
#        PolicyDescription ---------- Access Package Policy's Description
#        durationInDays ------------- 
#        RequestorScopeType --------- This value represents who can request the access package. Valid values are AllExistingDirectoryMemberUsers, AllExistingDirectorySubjects, AllConfiguredConnectedOrganizationSubjects, AllExternalSubjects, SpecificDirectorySubjects, SpecificConnectedOrganizationSubjects.
#        RequestorGroup ------------- If the "RequestorScopeType" is updated with value SpecificDirectorySubjects, then only update this value with Group Name whoes member you want to be able to request this access package.
#        P1Approver ----------------- Who will be the First Approver of the Access Package. Update the value with UPN of the Approver
#        P2Approver ----------------- Who will be the Second Approver of the Access Package. Update the value with UPN of the Approver
#        ReviewrecurrenceType ------- 
#        ReviewdurationInDays ------- 
#        R1Reviewer ----------------- Who will be the First Reviewer of the Access Package. Update the value with UPN of the Reviewer
#        R2Reviewer ----------------- Who will be the Second Reviewer of the Access Package. Update the value with UPN of the Reviewer
#        ConnectedORG --------------- This Value is only needed if "RequestorScopeType" is updated with value "SpecificConnectedOrganizationSubjects" then mention any verified domain name of the connected organization else leave it BLANK.
#        AppName -------------------- Application Name where you want to assign the Resource Group ( If no assignment required then leave it blank)
#        Approle -------------------- Application app Role which will be assigned to the Group ( If no assignment required then leave it blank)
#


# UPDATE INPUT File
$HUBFile = Import-Csv '.\InputCSV_EntitlementManagement_ALLScopes.csv'

# UPDATE TENANT ID & CLIENT ID of your organization's Azure AD
$tenantid = "---------------------------------"
$ClientID = "---------------------------------"

$Username = "svc-EM@contoso.com"
$PWd = ConvertTo-SecureString -String "**********" -AsPlainText -Force
$creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($Username, $PWd)


#
#Acquire AAD token 
function AcquireToken($clientID, $tenantID, $mfa)
{
    if($mfa)
    {
        $authResult = Get-MSALToken -UserCredential $creds -ClientId $clientID -tenantID $tenantID -ExtraQueryParameters @{claims='{"access_token" : {"amr": { "values": ["mfa"] }}}'}
        Set-Variable -Name mfaDone -Value $true -Scope Global
    }
    else
    {
        $authResult = Get-MSALToken -UserCredential $creds -ClientId $clientID -tenantID $tenantID
    }
    

    if($null -ne $authResult)
    {
        Write-Host "User logged in successfully ..." -ForegroundColor Green
    }
    Set-Variable -Name headerParams -Value @{'Authorization'="$($authResult.AccessTokenType) $($authResult.AccessToken)"} -Scope Global
    Return  $authResult
}

Write-Host "Starting run at $starttime"
#
#
#if($null -like (Get-Module -Name AzureADPreview)) { Install-Module AzureADPreview -Force }
#
# Install PowerShellGet and msal.ps modules if the do not exist -- Requires admin rights to install modules
Import-Module PowerShellGet
if(!(Get-Module | Where-Object {$_.Name -eq 'PowerShellGet' -and $_.Version -ge '2.2.4.1'})) { Install-Module PowerShellGet -Force }
Import-Module MSAL.PS
if(!(Get-Module msal.ps)) { Install-Package msal.ps }
#
if ($create -eq $false) {Write-Host "Running in Audit Mode"}
else {Write-Host "Running in ELM Create Mode"}
#
# Authenticate to AzureAD
#if ($AzureAdCred -like $null)
#{
#    $AzureAdCred = Get-Credential  
#    Connect-AzureAD -Credential $AzureAdCred
#}
#
# Get and Azure AD authentication token
$Authed = AcquireToken $clientID $tenantID $false
if ($Authed -eq $false)
{
    return
}
#

$graphBase = 'https://graph.microsoft.com/beta'
$graphV1Base = 'https://graph.microsoft.com/v1.0'
$fi='$filter'
$top='$top'
$ex='&$expand'
$endpoints = @{
    accessPackageCatalogs = "{0}/identityGovernance/entitlementManagement/accessPackageCatalogs" -f $graphBase
    accessPackages = "{0}/identityGovernance/entitlementManagement/accessPackages" -f $graphBase
    users = "{0}/users" -f $graphBase
    groups = "{0}/groups" -f $graphBase
    accessPackageAssignmentPolicies = "{0}/identityGovernance/entitlementManagement/accessPackageAssignmentPolicies?$($top)=1000" -f $graphBase
    me = "{0}/me" -f $graphBase
    accessPackageResourceRequests = "{0}/identityGovernance/entitlementManagement/accessPackageResourceRequests" -f $graphBase
    accessPackagecatalogResource ="{0}/identityGovernance/entitlementManagement/accessPackageCatalogs/$($accessPackageCatalog.id)/accessPackageResources" -f $graphBase
    accessPackageAPResourceRoleScope ="{0}/identityGovernance/entitlementManagement/accessPackages/$($NewAccessPackages.id)/accessPackageResourceRoleScopes" -f $graphBase
    accessPackageAPResourceRole="{0}/identityGovernance/entitlementManagement/accessPackageCatalogs/$($accessPackageCatalog.id)/accessPackageResourceRoles?$($fi)=(originSystem eq '$($Catalogresource.originSystem)' and accessPackageResource/id eq '$($Catalogresource.id)' and displayName eq 'Member')$($ex)=accessPackageResource" -f $graphBase
    connectedOrganization = "{0}/identityGovernance/entitlementManagement/connectedOrganizations/" -f $graphBase
    appRoleAssignments = "{0}/groups/$($AADGroup.id)/appRoleAssignments" -f $graphV1Base
    servicePrincipals = "{0}/servicePrincipals?$($fi)=startswith(displayName, '$($HUBcsv.AppName)')" -f $graphV1Base
}


foreach($HUBcsv in $HUBFile){

#
# STEP 1 - Ensure access package catalog is created
#
Write-Verbose "*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-" -Verbose
Write-Verbose "STEP 1 - Ensure access package catalog is created" -Verbose

    $accessPackageCatalog = Invoke-RestMethod -uri $endpoints.accessPackageCatalogs -Headers $HeaderParams | 
        Select-Object -ExpandProperty Value | 
        Where-Object displayName -eq $HUBcsv.APCDisplayName

    if(!$accessPackageCatalog) {
        Write-Verbose "Creating access package catalog '$($HUBcsv.APCDisplayName)'" -Verbose
        $body = @{
            displayName = $HUBcsv.APCDisplayName
            description = $HUBcsv.APCDescription
            isExternallyVisible = $true
        }
        $accessPackageCatalog = Invoke-RestMethod $endpoints.accessPackageCatalogs -Headers $HeaderParams -Method Post -Body $body
    } else {
       write-host -ForegroundColor Yellow "VERBOSE: Access package catalog '$($HUBcsv.APCDisplayName)' already created" -Verbose
    }

#
#step 2 - Creating Group and adding it to the catalog
#

write-Verbose "STEP 2 - Ensure AAD Group are created and added to the Catalog" -Verbose

    #  Validating if Group already exists
           
        $AADGroup = Invoke-RestMethod -uri $endpoints.groups -Headers $HeaderParams | 
            Select-Object -ExpandProperty Value | 
            Where-Object displayName -eq $HUBcsv.AADGroupDisplayName

    #  Creating group if not already present in Azure AD

        if(!$AADGroup) {
            Write-Verbose "Creating Group '$($HUBcsv.AADGroupDisplayName)' in Azure AD" -Verbose
            $gpbody = @{
                displayName = $HUBcsv.AADGroupDisplayName
                description = $HUBcsv.AADGroupDescription
                SecurityEnabled = $true
                mailEnabled = $false
                mailNickname = $HUBcsv.AADGroupMailNickName
                isAssignableToRole = $true
            }
            $AADGroup = Invoke-RestMethod $endpoints.groups -Headers $HeaderParams -Method Post -ContentType application/json -Body ($gpbody|ConvertTo-Json)

              Write-host -ForegroundColor White "VERBOSE: Waiting for 60 seconds for group creation update in Azure AD" -Verbose
              Start-Sleep -s 60
        } else {
           write-host -ForegroundColor Yellow "VERBOSE: Group '$($HUBcsv.AADGroupDisplayName)' already created" -Verbose
        }

    # Adding group to catalog

     # updating the Endpoints with the variable

        $graphBase = 'https://graph.microsoft.com/beta'
        $endpoints = @{
        accessPackageCatalogs = "{0}/identityGovernance/entitlementManagement/accessPackageCatalogs" -f $graphBase
        accessPackages = "{0}/identityGovernance/entitlementManagement/accessPackages" -f $graphBase
        users = "{0}/users" -f $graphBase
        groups = "{0}/groups" -f $graphBase
        accessPackageAssignmentPolicies = "{0}/identityGovernance/entitlementManagement/accessPackageAssignmentPolicies" -f $graphBase
        me = "{0}/me" -f $graphBase
        accessPackageResourceRequests = "{0}/identityGovernance/entitlementManagement/accessPackageResourceRequests" -f $graphBase
        accessPackagecatalogResource ="{0}/identityGovernance/entitlementManagement/accessPackageCatalogs/$($accessPackageCatalog.id)/accessPackageResources" -f $graphBase
        accessPackageAPResourceRoleScope ="{0}/identityGovernance/entitlementManagement/accessPackages/$($NewAccessPackages.id)/accessPackageResourceRoleScopes" -f $graphBase
        accessPackageAPResourceRole="{0}/identityGovernance/entitlementManagement/accessPackageCatalogs/$($accessPackageCatalog.id)/accessPackageResourceRoles?$($fi)=(originSystem eq '$($Catalogresource.originSystem)' and accessPackageResource/id eq '$($Catalogresource.id)' and displayName eq 'Member')$($ex)=accessPackageResource" -f $graphBase
        connectedOrganization = "{0}/identityGovernance/entitlementManagement/connectedOrganizations/" -f $graphBase
        appRoleAssignments = "{0}/groups/$($AADGroup.id)/appRoleAssignments" -f $graphV1Base
        servicePrincipals = "{0}/servicePrincipals?$($fi)=startswith(displayName, '$($HUBcsv.AppName)')" -f $graphV1Base
        }

    #  Validating if Group already exists as resource in catalog.

    $Catalogresource = Invoke-RestMethod $endpoints.accessPackagecatalogResource -Headers $HeaderParams | 
            Select-Object -ExpandProperty Value | 
            Where-Object displayName -eq $AADGroup.displayName

    #  Adding group as resource in catalog if not already present.

     if(!$Catalogresource) {
            Write-Verbose "Adding '$($AADGroup.displayName)' group in Access Catalog '$($accessPackageCatalog.displayName)' " -Verbose
        $G2cbody = @{
        catalogId = $accessPackageCatalog.id
        requestType = "AdminAdd"
        justification = "Admin add for production"
        accessPackageResource = @{
        displayName = $AADGroup.displayname
        description = $AADGroup.description
        resourceType = "AadGroup"
        originId = $AADGroup.id
        originSystem = "AadGroup"
        } }
        $Group2Catalog = Invoke-RestMethod $endpoints.accessPackageResourceRequests -Headers $HeaderParams -Method Post -ContentType application/json -Body ($G2cbody|ConvertTo-Json)
        } else {
           write-host -ForegroundColor Yellow "VERBOSE: Group '$($AADGroup.displayName)' already present in '$($accessPackageCatalog.displayName)' catalog as resource" -Verbose
        }


#
#STEP 3 - Ensure access packages are created
#
        write-Verbose "STEP 3 - Ensure access packages are created" -Verbose

    # Get all access packages in this catalog

        $currentAccessPackages = Invoke-RestMethod $endpoints.accessPackages -Headers $HeaderParams | 
            Select-Object -ExpandProperty Value | 
            Where-Object catalogId -eq $accessPackageCatalog.id

    # Ensure if access package is created or else create the access package

        if($HUBcsv.APDisplayName -notin $currentAccessPackages.displayName) {
                    Write-Verbose "Creating access package '$($HUBcsv.APDisplayName)'" -Verbose
                   $APbody = @{
                      catalogId = $accessPackageCatalog.id
                      displayName = $HUBcsv.APDisplayName
                      description = $HUBcsv.APDescription
                              }

            $NewAccessPackages =  Invoke-RestMethod $endpoints.accessPackages -Headers $HeaderParams -Method Post -Body $APbody
                } else {
                 write-host -ForegroundColor Yellow "VERBOSE: Access package '$($HUBcsv.APDisplayName)' already created" -Verbose
                }

            $NewAccessPackages = Invoke-RestMethod $endpoints.accessPackages -Headers $HeaderParams | 
            Select-Object -ExpandProperty Value | 
            Where-Object {($_.catalogId -le $accessPackageCatalog.id) -and ($_.displayName -eq $HUBcsv.APDisplayName)}


#
# STEP 4 - Adding Resource - Groups to the Access Package as member role
#
    write-Verbose "STEP 4 - Adding Resource (Groups) to the Access Package as member role" -Verbose

    # updating the Endpoints with the variable

    $endpoints = @{
    accessPackageCatalogs = "{0}/identityGovernance/entitlementManagement/accessPackageCatalogs" -f $graphBase
    accessPackages = "{0}/identityGovernance/entitlementManagement/accessPackages" -f $graphBase
    users = "{0}/users" -f $graphBase
    groups = "{0}/groups" -f $graphBase
    accessPackageAssignmentPolicies = "{0}/identityGovernance/entitlementManagement/accessPackageAssignmentPolicies" -f $graphBase
    me = "{0}/me" -f $graphBase
    accessPackageResourceRequests = "{0}/identityGovernance/entitlementManagement/accessPackageResourceRequests" -f $graphBase
    accessPackagecatalogResource ="{0}/identityGovernance/entitlementManagement/accessPackageCatalogs/$($accessPackageCatalog.id)/accessPackageResources" -f $graphBase
    accessPackageAPResourceRoleScope ="{0}/identityGovernance/entitlementManagement/accessPackages/$($NewAccessPackages.id)/accessPackageResourceRoleScopes" -f $graphBase
    accessPackageAPResourceRole="{0}/identityGovernance/entitlementManagement/accessPackageCatalogs/$($accessPackageCatalog.id)/accessPackageResourceRoles?$($fi)=(originSystem eq '$($Catalogresource.originSystem)' and accessPackageResource/id eq '$($Catalogresource.id)' and displayName eq 'Member')$($ex)=accessPackageResource" -f $graphBase
    connectedOrganization = "{0}/identityGovernance/entitlementManagement/connectedOrganizations/" -f $graphBase
    appRoleAssignments = "{0}/groups/$($AADGroup.id)/appRoleAssignments" -f $graphV1Base
    servicePrincipals = "{0}/servicePrincipals?$($fi)=startswith(displayName, '$($HUBcsv.AppName)')" -f $graphV1Base    
        }


    # Get the Resource Group information of the catalog.

     $Catalogresource = Invoke-RestMethod $endpoints.accessPackagecatalogResource -Headers $HeaderParams | 
            Select-Object -ExpandProperty Value | 
            Where-Object displayName -eq $AADGroup.displayName
    

    # Updating endpoint with new variables

    $endpoints = @{
    accessPackageCatalogs = "{0}/identityGovernance/entitlementManagement/accessPackageCatalogs" -f $graphBase
    accessPackages = "{0}/identityGovernance/entitlementManagement/accessPackages" -f $graphBase
    users = "{0}/users" -f $graphBase
    groups = "{0}/groups" -f $graphBase
    accessPackageAssignmentPolicies = "{0}/identityGovernance/entitlementManagement/accessPackageAssignmentPolicies" -f $graphBase
    me = "{0}/me" -f $graphBase
    accessPackageResourceRequests = "{0}/identityGovernance/entitlementManagement/accessPackageResourceRequests" -f $graphBase
    accessPackagecatalogResource ="{0}/identityGovernance/entitlementManagement/accessPackageCatalogs/$($accessPackageCatalog.id)/accessPackageResources" -f $graphBase
    accessPackageAPResourceRoleScope ="{0}/identityGovernance/entitlementManagement/accessPackages/$($NewAccessPackages.id)/accessPackageResourceRoleScopes" -f $graphBase
    accessPackageAPResourceRole="{0}/identityGovernance/entitlementManagement/accessPackageCatalogs/$($accessPackageCatalog.id)/accessPackageResourceRoles?$($fi)=(originSystem eq '$($Catalogresource.originSystem)' and accessPackageResource/id eq '$($Catalogresource.id)' and displayName eq 'Member')$($ex)=accessPackageResource" -f $graphBase
    connectedOrganization = "{0}/identityGovernance/entitlementManagement/connectedOrganizations/" -f $graphBase
    SpecificaccessPackages = "{0}/identityGovernance/entitlementManagement/accessPackages?$($fi)=(displayName eq '$($NewAccessPackages.displayName)')$($ex)=accessPackageAssignmentPolicies" -f $graphBase
    appRoleAssignments = "{0}/groups/$($AADGroup.id)/appRoleAssignments" -f $graphV1Base
    servicePrincipals = "{0}/servicePrincipals?$($fi)=startswith(displayName, '$($HUBcsv.AppName)')" -f $graphV1Base
        }

    # Get resources Group roles

    $CatalogresourceRole = Invoke-RestMethod $endpoints.accessPackageAPResourceRole -headers $HeaderParams |
    Select-Object -ExpandProperty value

    # Adding Resource group to the Access Package

    $G2APbody = @{
        accessPackageResourceRole = @{
        originId = $CatalogresourceRole.originId
        displayName = $CatalogresourceRole.displayName
        originSystem = $CatalogresourceRole.originSystem
        accessPackageResource = @{
            id =   $Catalogresource.id
            resourceType =   $Catalogresource.resourceType
            originId =   $Catalogresource.originId
            originSystem =   $Catalogresource.originSystem
            }
        }
        accessPackageResourceScope = @{
            originId = $Catalogresource.originId
            originSystem = $Catalogresource.originSystem
        }
            }

     $cs =  Invoke-RestMethod $endpoints.accessPackageAPResourceRoleScope -Headers $HeaderParams -Method Post -ContentType application/json -Body ($G2APbody|ConvertTo-Json)


#
# STEP 5 - Pulling User\Group information for Primary Approvals
#

Write-Verbose "STEP 5 - Pulling User\Group information involved in the Policy Configuration" -Verbose

    $P1User = Invoke-RestMethod $endpoints.users -Headers $HeaderParams | Select-Object -ExpandProperty value | Where-Object userPrincipalName -eq $HUBcsv.P1Approver
    $P2User = Invoke-RestMethod $endpoints.users -Headers $HeaderParams | Select-Object -ExpandProperty value | Where-Object userPrincipalName -eq $HUBcsv.P2Approver
    $R1User = Invoke-RestMethod $endpoints.users -Headers $HeaderParams | Select-Object -ExpandProperty value | Where-Object userPrincipalName -eq $HUBcsv.R1Reviewer
    $R2User = Invoke-RestMethod $endpoints.users -Headers $HeaderParams | Select-Object -ExpandProperty value | Where-Object userPrincipalName -eq $HUBcsv.R2Reviewer
    $ReqGRP = Invoke-RestMethod $endpoints.groups -Headers $HeaderParams | Select-Object -ExpandProperty value | Where-Object DisplayName -eq $HUBcsv.RequestorGroup
    $ApproverGRP = Invoke-RestMethod $endpoints.groups -Headers $HeaderParams | Select-Object -ExpandProperty value | Where-Object DisplayName -eq $HUBcsv.GRPApprover
    $ReviewerGRP = Invoke-RestMethod $endpoints.groups -Headers $HeaderParams | Select-Object -ExpandProperty value | Where-Object DisplayName -eq $HUBcsv.GRPREVIEWER

#
# STEP 6 - Pulling Connected Org information
#
Write-Verbose "STEP 6 - Pulling Connected Org information for setting requestor configuration in Policy" -Verbose

       # Checking if Connected Organization exists or not
       If ($HUBcsv.ConnectedORG) {
       $ConnectedORG = Invoke-RestMethod $endpoints.connectedOrganization -Headers $HeaderParams | Select-Object -ExpandProperty value | Where-Object displayName -eq $HUBcsv.ConnectedORG


       # Adding Connected Organization if it does not exists

       if(!$ConnectedORG) {
        Write-Verbose "Adding '$($HUBcsv.ConnectedORG)' Connected Organization" -Verbose
        $CObody = @{
            displayName = $HUBcsv.ConnectedORG
            description = "Connected Organization for '$($HUBcsv.ConnectedORG)'"
            identitySources = @(
                    @{
                        "@odata.type" = "#microsoft.graph.domainIdentitySource"
                        domainName = $HUBcsv.ConnectedORG
                        displayName = $HUBcsv.ConnectedORG
                                        }
                )
            state = "configured"
        }
        $ConnectedORG = Invoke-RestMethod $endpoints.connectedOrganization -Headers $HeaderParams -Method Post -ContentType application/json -Body ($CObody|ConvertTo-Json)
    } else {
        write-host -ForegroundColor Yellow "VERBOSE: '$($HUBcsv.ConnectedORG)' is already present as Connected Organization in HUB's Azure AD" -Verbose
    }
    } else {
   write-host -ForegroundColor Yellow "VERBOSE: Skipping this step 6 as Requestor Scope Does not contain Specific Connected Organizations" -Verbose
    }


#
# STEP 7 - Ensure access package request policies exist
#
Write-Verbose "STEP 7 - Ensure access package request policies exist" -Verbose

        # Checking if Policy of Access Package exists or not
        $policies = Invoke-RestMethod $endpoints.accessPackageAssignmentPolicies -headers $HeaderParams |
            Select-Object -ExpandProperty value | Where-Object {($_.accessPackageId -le $NewAccessPackages.id) -and ($_.displayName -eq $HUBcsv.PolicyDisplayName)}


             # Bulding Approvers List using input from input file
  
              if($HUBcsv.GRPApprover -and (!$HUBcsv.P1Approver -or !$HUBcsv.P2Approver)) {
        
                    write-host -ForegroundColor Yellow "VERBOSE: Group '$($ApproverGRP.displayName)' is getting added as Approver"

                    $primaryApprovers = @(
                                            @{
                                               "@odata.type" = "#microsoft.graph.groupMembers"
                                                id = $ApproverGRP.id
                                                description = $ApproverGRP.displayName
                                                isBackup = $false
                                             }
                                          )
        
                } elseif(!$HUBcsv.GRPApprover -and ($HUBcsv.P1Approver -and $HUBcsv.P2Approver)) {
        
                    write-host -ForegroundColor Yellow "VERBOSE: Users '$($HUBcsv.P1Approver)' & '$($HUBcsv.P2Approver)' will be added as the two Approvers" -Verbose
        
                    $primaryApprovers= @(
                                            @{
                                                "@odata.type" = "#microsoft.graph.singleUser"
                                                id = $P1User.id
                                                description = $P1User.displayName
                                                isBackup = $false
                                            }
                                             @{
                                                "@odata.type" = "#microsoft.graph.singleUser"
                                                id = $P2User.id
                                                description = $P2User.displayName
                                                isBackup = $false
                                            }
                                       )


                } elseif ($HUBcsv.GRPApprover -and $HUBcsv.P1Approver -and $HUBcsv.P2Approver) {
        
                    write-host -ForegroundColor Yellow "VERBOSE: Group '$($ApproverGRP.displayName)' & Users '$($HUBcsv.P1Approver)' , '$($HUBcsv.P2Approver)' will be added as the Approvers" -Verbose
           
                    $primaryApprovers= @(
                                            @{
                                                "@odata.type" = "#microsoft.graph.groupMembers"
                                                id = $ApproverGRP.id
                                                description = $ApproverGRP.displayName
                                                isBackup = $false
                                              }
                                            @{
                                                "@odata.type" = "#microsoft.graph.singleUser"
                                                id = $P1User.id
                                                description = $P1User.displayName
                                                isBackup = $false
                                            }
                                             @{
                                                "@odata.type" = "#microsoft.graph.singleUser"
                                                id = $P2User.id
                                                description = $P2User.displayName
                                                isBackup = $false
                                            }
                                        )
                } else {

                write-host -ForegroundColor Yellow "VERBOSE: No valid approvers were find in the input file"
                $primaryApprovers= $null
    
                }



                # Bulding Reviewers List using input from input file
  
              if($HUBcsv.GRPREVIEWER -and (!$HUBcsv.R1Reviewer -or !$HUBcsv.R2Reviewer)) {
        
                    write-host -ForegroundColor Yellow "VERBOSE: Group '$($ReviewerGRP.displayName)' is getting added as Reviewer"

                    $primaryReviewers = @(
                                            @{
                                               "@odata.type" = "#microsoft.graph.groupMembers"
                                                id = $ReviewerGRP.id
                                                description = $ReviewerGRP.displayName
                                                isBackup = $false
                                             }
                                          )
        
                } elseif(!$HUBcsv.GRPREVIEWER -and ($HUBcsv.R1Reviewer -and $HUBcsv.R2Reviewer)) {
        
                    write-host -ForegroundColor Yellow "VERBOSE: Users '$($R1User.displayName)' & '$($R2User.displayName)' will be added as the two Reviewers" -Verbose
        
                    $primaryReviewers= @(
                                            @{
                                                "@odata.type" = "#microsoft.graph.singleUser"
                                                id = $R1User.id
                                                description = $R1User.displayName
                                                isBackup = $false
                                            }
                                             @{
                                                "@odata.type" = "#microsoft.graph.singleUser"
                                                id = $R2User.id
                                                description = $R2User.displayName
                                                isBackup = $false
                                            }
                                       )


                } elseif ($HUBcsv.GRPREVIEWER -and $HUBcsv.R1Reviewer -and $HUBcsv.R2Reviewer) {
        
                    write-host -ForegroundColor Yellow "VERBOSE: Group '$($ApproverGRP.displayName)' & Users '$($R1User.displayName)' , '$($R2User.displayName)' will be added as the Reviewers" -Verbose
           
                    $primaryReviewers= @(
                                            @{
                                                "@odata.type" = "#microsoft.graph.groupMembers"
                                                id = $ReviewerGRP.id
                                                description = $ReviewerGRP.displayName
                                                isBackup = $false
                                              }
                                            @{
                                                "@odata.type" = "#microsoft.graph.singleUser"
                                                id = $R1User.id
                                                description = $R1User.displayName
                                                isBackup = $false
                                            }
                                             @{
                                                "@odata.type" = "#microsoft.graph.singleUser"
                                                id = $R2User.id
                                                description = $R2User.displayName
                                                isBackup = $false
                                            }
                                        )
                } else {

                write-host -ForegroundColor Yellow "VERBOSE: No valid Reviwers were find in the input file"
                $primaryReviewers= $null
    
                }





        # Adding Policy of Access Package if it does not exists
        if(!$policies) {
 
          if( @(“AllExistingDirectoryMemberUsers”,”AllExistingDirectorySubjects”,”AllConfiguredConnectedOrganizationSubjects”,”AllExternalSubjects”) -eq $HUBcsv.RequestorScopeType)
             {Write-Verbose "Creating policy '$($HUBcsv.PolicyDisplayName)' for access package '$($NewAccessPackages.DisplayName)'" -Verbose
                $body = @{
                accessPackageId =  $NewAccessPackages.Id
                displayName = $HUBcsv.PolicyDisplayName
                description = $HUBcsv.PolicyDescription
                durationInDays = $HUBcsv.durationInDays
                canExtend = $true
                requestorSettings = @{
                    acceptRequests = $true
                    scopeType = $HUBcsv.RequestorScopeType
                    allowedRequestors = @()
                                       }
                accessReviewSettings =  @{
                             isEnabled = $true
                             recurrenceType = $HUBcsv.ReviewrecurrenceType
                             reviewerType = "Reviewers"
                             durationInDays = $HUBcsv.ReviewdurationInDays
                             accessReviewTimeoutBehavior = "keepAccess"
                             isAccessRecommendationEnabled = $true 
                             isApprovalJustificationRequired = $true 
                             reviewers= $primaryReviewers
                                        }
                     
                requestApprovalSettings = @{
                    isApprovalRequired = $true
                    isApprovalRequiredForExtension = $true
                    isRequestorJustificationRequired = $true
                    approvalMode = "SingleStage"
                    approvalStages = @(
                        @{
                            approvalStageTimeOutInDays = 14
                            isApproverJustificationRequired = $true
                            isEscalationEnabled = $false
                            escalationTimeInMinutes = 0
                            escalationApprovers = @()
                           primaryApprovers = $primaryApprovers
                         }
                        
                    )
                }
            }
            Invoke-RestMethod $endpoints.accessPackageAssignmentPolicies -Headers $HeaderParams -Method Post -Body ($body | ConvertTo-Json -Depth 10) -ContentType "application/json" | Out-Null
   
        } elseif ($HUBcsv.RequestorScopeType -eq "SpecificConnectedOrganizationSubjects" ) { Write-Verbose "Creating policy '$($HUBcsv.PolicyDisplayName)' for access package '$($NewAccessPackages.DisplayName)'" -Verbose
            $body = @{
                accessPackageId =  $NewAccessPackages.Id
                displayName = $HUBcsv.PolicyDisplayName
                description = $HUBcsv.PolicyDescription
                durationInDays = $HUBcsv.durationInDays
                canExtend = $true
                requestorSettings = @{
                    acceptRequests = $true
                    scopeType = $HUBcsv.RequestorScopeType
                    allowedRequestors = @(
                        @{
                            "@odata.type" = "#microsoft.graph.connectedOrganizationMembers"
                            isBackup = $false
                            description = $ConnectedORG.displayName
                            id = $ConnectedORG.id
                        }
                    )
                }
                accessReviewSettings =  @{
                             isEnabled = $true
                             recurrenceType = $HUBcsv.ReviewrecurrenceType
                             reviewerType = "Reviewers"
                             durationInDays = $HUBcsv.ReviewdurationInDays
                             accessReviewTimeoutBehavior = "keepAccess"
                             isAccessRecommendationEnabled = $true 
                             isApprovalJustificationRequired = $true 
                             reviewers= $primaryReviewers
                                        
                                        }
                     
                requestApprovalSettings = @{
                    isApprovalRequired = $true
                    isApprovalRequiredForExtension = $true
                    isRequestorJustificationRequired = $true
                    approvalMode = "SingleStage"
                    approvalStages = @(
                        @{
                            approvalStageTimeOutInDays = 14
                            isApproverJustificationRequired = $true
                            isEscalationEnabled = $false
                            escalationTimeInMinutes = 0
                            escalationApprovers = @()
                           primaryApprovers = $primaryApprovers
                        }
                    )
                }
            }
            Invoke-RestMethod $endpoints.accessPackageAssignmentPolicies -Headers $HeaderParams -Method Post -Body ($body | ConvertTo-Json -Depth 10) -ContentType "application/json" | Out-Null

        } elseIf ($HUBcsv.RequestorScopeType -eq "SpecificDirectorySubjects" ) { Write-Verbose "Creating policy '$($HUBcsv.PolicyDisplayName)' for access package '$($NewAccessPackages.DisplayName)'" -Verbose
            $body = @{
                accessPackageId =  $NewAccessPackages.Id
                displayName = $HUBcsv.PolicyDisplayName
                description = $HUBcsv.PolicyDescription
                durationInDays = $HUBcsv.durationInDays
                canExtend = $true
                requestorSettings = @{
                    acceptRequests = $true
                    scopeType = $HUBcsv.RequestorScopeType
                    allowedRequestors = @(
                        @{
                           "@odata.type" = "#microsoft.graph.groupMembers"
                            isBackup = $false
                            description = $ReqGRP.displayName
                            id = $ReqGRP.id
                        }
                    )
                }
                accessReviewSettings =  @{
                             isEnabled = $true
                             recurrenceType = $HUBcsv.ReviewrecurrenceType
                             reviewerType = "Reviewers"
                             durationInDays = $HUBcsv.ReviewdurationInDays
                             accessReviewTimeoutBehavior = "keepAccess"
                             isAccessRecommendationEnabled = $true 
                             isApprovalJustificationRequired = $true 
                             reviewers= $primaryReviewers
                                        }
                     
                requestApprovalSettings = @{
                    isApprovalRequired = $true
                    isApprovalRequiredForExtension = $true
                    isRequestorJustificationRequired = $true
                    approvalMode = "SingleStage"
                    approvalStages = @(
                        @{
                            approvalStageTimeOutInDays = 14
                            isApproverJustificationRequired = $true
                            isEscalationEnabled = $false
                            escalationTimeInMinutes = 0
                            escalationApprovers = @()
                           primaryApprovers = $primaryApprovers
                        }
                    )
                }
            }
            Invoke-RestMethod $endpoints.accessPackageAssignmentPolicies -Headers $HeaderParams -Method Post -Body ($body | ConvertTo-Json -Depth 10) -ContentType "application/json" | Out-Null
        } Else {
                write-host -ForegroundColor Red "VERBOSE: Error creating Policy because the mentioned RequestorScopeType in the Excel sheet is wrong. Only Below mentioned values are allowed:
                1. AllExistingDirectoryMemberUsers	
                2. AllExistingDirectorySubjects
                3. AllConfiguredConnectedOrganizationSubjects
                4. AllExternalSubjects
                5. SpecificDirectorySubjects
                6. SpecificConnectedOrganizationSubjects " -Verbose
                }
        } else {

        write-host -ForegroundColor Yellow "VERBOSE: Policy '$($HUBcsv.PolicyDisplayName)' for access package '$($NewAccessPackages.DisplayName)' already created" -Verbose
        }

#
# STEP 8 - Ensure newly Created Group if needed to be added to the certain application or not.
#
Write-Verbose "STEP 8 - Adding\Assigning the Groups to the Applications" -Verbose

        if($HUBcsv.AppName -and $HUBcsv.AppRole) {
    
            # Get Application's Service Prinicpal Information.
            $App = Invoke-RestMethod $endpoints.servicePrincipals -Headers $HeaderParams  |  Select-Object -ExpandProperty Value
    
            # Get Application's App Role information.
            $AppRoles = Invoke-RestMethod $endpoints.servicePrincipals -Headers $HeaderParams  |  Select-Object -ExpandProperty Value | Select-object -ExpandProperty approles | Where-Object displayName -eq $HUBcsv.Approle


            # Validating if Group is already assigned to Application or not, IF not then assign this group to Application with Input file mentione app Role.
            $GroupAppRoleAssignment = Invoke-RestMethod  $endpoints.appRoleAssignments -Headers $HeaderParams | Select-Object -ExpandProperty Value | Where-Object resourceId -eq $app.id
    
              if(!$GroupAppRoleAssignment) {
                    Write-Verbose "Adding Group '$($AADGroup.DisplayName)' to Application '$($App.DisplayName)'" -Verbose
                    $AppRolebody = @{
                                  principalId = $AADGroup.id
                                  resourceId = $app.id
                                  appRoleId = $AppRoles.id
                                }
                   $GroupAppRoleAssignment = Invoke-RestMethod $endpoints.appRoleAssignments -Headers $HeaderParams -Method Post -ContentType "application/json" -Body ($AppRolebody|ConvertTo-Json)
                } else {
                   write-host -ForegroundColor Yellow "VERBOSE: Group '$($AADGroup.DisplayName)' is already added to Application '$($App.DisplayName)'" -Verbose
                }
                } else {
            
                  write-host -ForegroundColor Yellow "VERBOSE: Skipping step to Add\Assign group to Application as no AppName And Approle value detected" -Verbose
         
                }
}
