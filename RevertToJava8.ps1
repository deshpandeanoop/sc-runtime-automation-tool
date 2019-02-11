<#
	Script for reverting Sorian runtime (Tomcat 7.x and Java 8)
	Algorithm:
		- Stop Soarian Web Instances
		- Copy Java 11 logs (which is used for further analysis)
		- Copy stp\app folder which contains all tomcat 7.x instances with soarian specific configuration
		- Copy JDK 8.x to stp intall folder, \Program Files\Cerner\Java
		- Remove the Backup
		- Delete Soarian Web Instances (Tomcat 9.x installed as service)
		- Re-Install Soarian Web Instances (Tomcat 7.x as Windows Service)
		
	Steps to execute:
		Open package.json file, update parameters value with
			- Set scInstall to soarian installation directory
			- Set stpInstall to soarian tomcat platform directory
			- Set jvmStartFlag 1 to start only single soarian web instance (excluding KDI), 0 otherwise
			- Set scLogDir to application logs directory path
		
		Open PowerShell in administrative mode, navigate to current directory and run .\RevertToJava8.ps1	
#>

# Validates domain username/password combination is correct
	$user_credentials = .\CheckUserCredentials


# Displays the message (error/exception) and terminates execution

function eof(){
	param([string] $message)
	
	Echo $message
	
		exit
}

<#
	Checks user inputs, gives the approriate reason in case of incorrect inputs 
	The checks are 
		- Soarian tomcat platform directory exists on file system
		- Soarian installation directory exists on file system
		- Valid Tomcat Folder is provided by the user
#>
function validateInputs(){	

	if($flag -ne 1){
		$flag = 0 # start all soarian web instances
	}
	
	$tomcat_folder = $tomcat_folder.Trim()
	
	if(-Not (Test-Path -Path $tomcat_folder)){
		eof -message "Folder $tomcat_folder doesn't not exists. Please give a correct path in package.json"
	}
	
	$sc_install = $sc_install.Trim()
	if(-Not (Test-Path -Path $sc_install)){
		eof -message "Folder $stpInstall doesn't not exists.Please give a correct path in package.json"
	}
	
	# Extract the build number from the Soarian tomcat directory name
	
	Try{
			$tokens = $tomcat_folder.split('\')
			$tokens = $tokens[$tokens.length-1].split('_')	
			$build_number = $tokens[1]
	}
	Catch{
		eof -message "Invalid tomcat folder $tomcat_folder. Please give give a correct path in package.json"
	}
	
	# Forming names of tomcat services , the format is 'Soarian_Clinicals_<build_version>_<tomcat instance>'
	
	for($i=0;$i -lt $tc_instances.length;++$i){
		$sc_web_instances[$i] = "Soarian_Clinicals_"+$build_number+"_"+$tc_instances[$i]
	}
	
	#Granting Service Log on right for the new user, which enables to start the installed soarian web instances 
	
		$privilege = "SeServiceLogonRight"
		$CarbonDllPath = "$current_location\Utility\Carbon\bin\Carbon.dll"
		[Reflection.Assembly]::LoadFile($CarbonDllPath)
		[Carbon.Lsa]::GrantPrivileges( $user_credentials[0] , $privilege)
}

# Stops all Sorian web instances

function stopTCServices(){

	Echo "Stop Soarian Web Instances"
	
	for ($i = 0; $i -le ($sc_web_instances.length - 1); $i += 1) {
		
		Stop-Service $sc_web_instances[$i]
		
	}
}

# Re-Installs soarian web instances (tomcat as service) with given user name/password

function createScWebInstances(){

	Echo "Deleting Soarian Web Instances"
	
	for ($i = 0; $i -lt $sc_web_instances.length; $i += 1) {
		sc.exe delete $sc_web_instances[$i]
	}
	
	Echo "Creating Soarian Web Instances"
	
	$jmx_ports = 29804,29504,29604,29704
	for($k=0; $k -lt $tc_instances.length ; $k++){
		 $path = "$ctp_home\app\instances\"+$tc_instances[$k]+"\apache-tomcat-7.0.55\bin\"
		 Set-Location -Path $path
		 
		 .\TCServiceInstall.bat $user_credentials[0] $user_credentials[1] $jmx_ports[$k]
	}
	
	Set-Location $current_location
	
	Echo "Starting Soarian Web Instances"
	
	# If jvmStartFlag is set to 1, start only one soarian tomcat instance (excluding KDI), else start all instances	
		
	$cnt  = 0
	if($flag -eq 0){
		$cnt = 4
	}	
	else{
		$cnt = 2
	}
	for ($i = 0; $i -lt $cnt; $i += 1) {
		set-service $sc_web_instances[$i] -startuptype automatic
		sc.exe Start $sc_web_instances[$i]
	}
}

# Copies Java 11 logs, which is used for further analysis
function copyLogs(){
	
	Echo "Copying SC UI logs"
	$dest = "$current_location\$currentLogBkupFolderName\App"
	robocopy $sc_logdir $dest /MIR
	
	Echo "Copying Tomcat logs"
	for($k=0; $k -lt $tc_instances.length ; $k++){
		$src = "$ctp_home\app\instances\"+$tc_instances[$k]+"\apache-tomcat-9.0.14\logs"
		$dest = "$current_location\$currentLogBkupFolderName\Tomcat\"+$tc_instances[$k]+"\apache-tomcat-9.0.14\logs\"
		robocopy $src $dest /MIR
	}
}

# Copies backed up folders, here is the list
# stp\app - Has all tomcat-7.x instances with soarian specific configuration
# JDK 8.x - version which soarian is using user stp folder and under \Program Files\Cerner\Java

function restoreFromBackup(){

	copyLogs
	
	Echo "Remove app folder under tomcat"
	Remove-Item $ctp_home\app -Recurse -Force
	
	Echo "Restore app folder"
	Copy-Item $current_location\stp_app_bkp\app -Destination $ctp_home\app -Recurse
	
	Echo "Restore jdk folder"	
	Get-ChildItem $ctp_home\ | Where-Object {$_ -match "jdk"} | Remove-Item -Recurse -Force
	Get-ChildItem $current_location\stp_app_bkp\ | Where-Object {$_ -match "jdk"} | Copy-Item -Destination $ctp_home\ -Recurse
	
	Echo "Restore SC Install"
	Remove-Item $sc_install\Java -Recurse -Force
	Copy-Item $current_location\stp_app_bkp\Java -Destination $sc_install\Java -Recurse
	
	Echo "Removing stp backup"
	Remove-Item $current_location\stp_app_bkp -Recurse -Force
}

# Declare Soarian specific constants
	
 #$ctp_home =$null
 $tc_instances = 'KDIMaintjvm-1','SCjvm-1','SCjvm-2','SCjvm-3'
 $sc_web_instances = new-object string[] 4
 
 #Read input parameters from JSON file
 
 
 $stp_json = Get-Content package.json | ConvertFrom-Json
 $tomcat_folder = $stp_json.parameters.stpInstall
 $sc_install = $stp_json.parameters.scInstall
 $sc_logdir = $stp_json.parameters.scLogDir+"\$Env:COMPUTERNAME"
 
 $flag = $stp_json.parameters.jvmStartFlag
 $ctp_home = $tomcat_folder+"\stp"
 $currentLogBkupFolderName = "Logs_"+$Env:COMPUTERNAME
 $current_location = Get-Location
 
 # Initiate Revert Process
 
	#Step 1 - validate user inputs, terminate the execution, if fails 
			validateInputs
	#Step 2 - Stop Soarian web instances (Soarian_Clinicals_12345_KDIMaintJVM-1,Soarian_Clinicals_12345_SC-JVM-1,Soarian_Clinicals_12345_SC-JVM-2,Soarian_Clinicals_12345_SC-JVM-3)
			stopTCServices
	#Step 3 - Copy JDK 8.x, stp\app (which contains all tomcat 7.x specific instances with soarian specific configuration)
			restoreFromBackup
	#Step 4 - Create new tomcat services in windows registry with given user name/password, and start the same		
			createScWebInstances
 
 
 Echo "Successfully Reverted back from backup"