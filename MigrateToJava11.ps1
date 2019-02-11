<#
	Script for upgrading Soarian Clinicals Runtime (Tomcat 9 and Java 11)
	Algorithm:
		- Stop Soarian Web Instances
		- Upgrade four tomcat instances to version 9.x
		- Make Soarian specific configurations to each tomcat instance
		- Place JDK 11 in soarian tomcat platform (directory in which Tomcat looks for)
		- Add additional Jars specific to soarian
		- Delete Soarian Web Instances (Tomcat 7.x installed as service)
		- Re-Install Soarian Web Instances (Tomcat 9 as Windows Service)
		
	Steps to execute:
		Open package.json file, update parameters value with
			- Set scInstall to soarian installation directory
			- Set stpInstall to soarian tomcat platform directory
			- Set jvmStartFlag 1 to start only single soarian web instance (excluding KDI), 0 otherwise
			- Set scLogDir to application logs directory path
		
		Open PowerShell in administrative mode, navigate to current directory and run .\MigrateToJava11.ps1	
#>

# Validates domain username/password combination is correct
$user_credentials = .\CheckUserCredentials

# Displays the message (error/exception) and terminates execution
function eof(){
	param([string] $message)
	Echo $message
	exit
}

#Ensures the migration script runs if and only if the Soarian's runtime is Tomcat 7.x and Java 8 
function checkBackupFolder(){

	$stp_app_bkup = "$current_location\stp_app_bkp"
	
	if(Test-Path $stp_app_bkup -PathType Container){
	
		$stp_folder_contents = @(Get-ChildItem -Path $stp_app_bkup -Name)
		$jdk_folder = $null
		$app_folder = $null
		$java_folder = $null
		
		for($k=0;$k -lt $stp_folder_contents.length ; $k++){
			if($stp_folder_contents[$k] -match "jdk"){
				$jdk_folder = $stp_folder_contents[$k]
			}ElseIf($stp_folder_contents[$k] -match "app"){
				$app_folder = $stp_folder_contents[$k]
			}ElseIf($stp_folder_contents[$k] -match "Java"){
				$java_folder = $stp_folder_contents[$k]
			}
		}
		if($jdk_folder -ne $null -and $app_folder -ne $null -and $java_folder -ne $null ){
			eof -message "stp_app_bkp folder exists. Please verify RevertToJava8 is executed. Otherwise proceed after manually deleting stp_app_bkp folder in your current directory"
		}Else {
			Echo "Cleaning up stp backup folder"
			Remove-Item $stp_app_bkup -Recurse
		}
	}
}

<#
	Checks user inputs, gives the approriate reason in case of incorrect inputs 
	The checks are 
		- Soarian is running on tomcat 7.x and Java 8
		- Soarian tomcat platform directory exists on file system
		- Valid tomcat platform directory is provided by the user
		- Soarian installation directory exists on file system
#>
function validateInputs(){	
	
	# If the back up folder exists, it implies that user is re-running the script
	
	checkBackupFolder
	
	if($flag -ne 1){
		$flag = 0 # start all soarian web instances
	}
	
	$tomcat_folder = $tomcat_folder.Trim()
		if(-Not (Test-Path -Path $tomcat_folder)){
		
			eof -message "Folder $tomcat_folder doesn't not exists. Please give a correct path in package.json"
		}
	
	$sc_install = $sc_install.Trim()
		if(-Not (Test-Path -Path $sc_install)){
		
			eof -message "Folder $sc_install doesn't not exists.Please give a correct path in package.json"
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

# Makes Soarian specific configurations to Tomcat

function modifyTcBatch([string] $tc_instance){
	echo "Modifying $tc_instance....."
	
	echo "Modifying catalina batch"
	$batch_file="$ctp_home\app\instances\$tc_instance\$tomcat9\bin\catalina.bat"
	(Get-Content $batch_file) -replace('-Djava.endorsed.dirs="%JAVA_ENDORSED_DIRS%"', '') | Set-Content $batch_file
	echo "Catalina batch file modified successfully......"
	
	echo "Modifying service batch file"
	$batch_file = "$ctp_home\app\instances\$tc_instance\$tomcat9\bin\service.bat"
	$content = Get-Content $batch_file
	$content=$content.replace('%JAVA_HOME%\jre\bin','%JAVA_HOME%\bin') 
	$content=$content.replace('JRE_HOME=%JAVA_HOME%\jre','JRE_HOME=%JAVA_HOME%')
	$content = $content.replace('-Djava.endorsed.dirs=%CATALINA_HOME%\endorsed;','')
	Set-Content $batch_file $content
	echo "Service batch file modified successfully"
	
	echo "Modifying setenv batch file"
	$batch_file = "$ctp_home\app\instances\$tc_instance\$tomcat9\bin\setenv.bat"
	$content= Get-Content $batch_file
	$modifiedContent = "";
	foreach($line in $content){
		if($modifiedContent -eq ""){
			$modifiedContent = $line
		}
		elseif($line -match "SET JRE_HOME"){
			$modifiedContent = $modifiedContent+"`n"+"SET JRE_HOME=%JAVA_HOME%"
		}
		elseif(($line -match "PrintGCApplicationConcurrentTime")){
			$modifiedContent = $modifiedContent+"`n"
		}
		elseif($line -match "PrintGCDateStamps"){
			$modifiedContent = $modifiedContent+"`n"+"SET GC_OPTS=-verbose:gc -XX:+PrintGC -Xloggc:%CATALINA_BASE%\logs\verbosegc.log"
		}
		
		else{
			$modifiedContent = $modifiedContent+"`n"+$line
		}
	}
	Set-Content $batch_file $modifiedContent
	echo "SetEnv Batch modified sucessfully"
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
		 $path = "$ctp_home\app\instances\"+$tc_instances[$k]+"\$tomcat9\bin\"
		 
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

# Removes Tomcat 7.x logs, application logs before taking the backup. 

function removeLogs(){
	Echo "Removing SC UI logs"
	Remove-Item $sc_logdir\* -Recurse -force
	
	Echo "Removing Tomcat logs"
	for($k=0; $k -lt $tc_instances.length ; $k++){
		$src = "$ctp_home\app\instances\"+$tc_instances[$k]+"\$tomcat7\logs\*"
		Remove-Item $src -Recurse -force
	}
}


# Takes set of folders as backup, which are used by the revert script to bring back the system to Java 8 and Tomcat 7.x

function takeBackUp(){

	Echo "Taking jdk backup"

	$stp_folder_contents = Get-ChildItem -Path $ctp_home -Name
	$jdk_counter = 0;
	$jdk_folder = $null;
	
	for($k=0;$k -lt $stp_folder_contents.length ; $k++){

	if($stp_folder_contents[$k] -match "jdk"){
		$jdk_folder = $stp_folder_contents[$k]
		$jdk_counter ++;
		}

	}
	
	# Terminate the execution if there exists more than one JDK under stp
	# In case of multiple JDK folders, it will be indeterministic for tomcat in finding a JDK to point
	
	if($jdk_counter -eq 0 -or $jdk_counter -gt 1){
		eof -message 'there should be single jdk folder under stp '
	}
	
	Copy-Item $ctp_home\$jdk_folder -Destination $current_location\stp_app_bkp\$jdk_folder -Recurse
	
	Remove-Item $ctp_home\$jdk_folder -Recurse
	
	# Remove application logs, Tomcat logs, we are doing this to reduce backup size and also helpful in getting approriate Java 11 logs
	
		removeLogs
	
	Echo "Taking app folder backup"
	
		Copy-Item $ctp_home\app -Destination $current_location\stp_app_bkp\app -Recurse
	
	Echo "app folder backup sucessful"
}

function deleteJars(){
	for($k=0 ; $k -lt $stp_json.delete.length ; $k++){
		for($p =0 ; $p -lt $stp_json.delete[$k].files.length ; $p++){
			$path = $ctp_home+$stp_json.delete[$k].root+$stp_json.delete[$k].files[$p]
			Remove-Item -Path $path
		}
	}
}


function addJarsAndJDK(){
	Echo "Placing JDK 11 in stp folder"
	
	$jdk11_path = "$current_location\"+$stp_json.java.stp
	$tokens = $stp_json.java.stp.split('\')
	$jdk_folder = $tokens[$tokens.length-1]
	
	Copy-Item $jdk11_path -Destination $ctp_home\$jdk_folder -Recurse
	
	Echo "Placing additional jars in tomcat ext folder"
	for($k=0 ; $k -lt $stp_json.insert.length ; $k++){
			
		$dest = $ctp_home+$stp_json.insert[$k].root
		$src = ".\"+$stp_json.insert[$k].current+"\*"
		
		If (-not (Test-Path $dest)) {
			New-Item -ItemType directory -Path $dest -Force
		}	
		Copy-Item $src $dest -Recurse
		
	}
}

function removeAndReplaceJre(){

	Copy-Item $sc_install\Java\ -Destination $current_location\stp_app_bkp\Java -Recurse
	Remove-Item $sc_install\Java\x64\jre\* -Recurse
	Remove-Item $sc_install\Java\x86\jre\* -Recurse
	
	$src_jre_path = "$current_location\"+$stp_json.java.x64+"\*"
	Copy-Item $src_jre_path -Destination $sc_install\Java\x64\jre\ -Recurse
	
	$src_jre_path = "$current_location\"+$stp_json.java.x86+"\*"
	Copy-Item $src_jre_path -Destination $sc_install\Java\x86\jre\ -Recurse
}


 # Declare Soarian specific constants
 
 #$ctp_home =$null
 $tc_instances = 'KDIMaintjvm-1','SCjvm-1','SCjvm-2','SCjvm-3'
 $sc_web_instances = new-object string[] 4 

 #Read input parameters from JSON file
 
 $stp_json = Get-Content package.json | ConvertFrom-Json
 $tomcat_folder = $stp_json.parameters.stpInstall
 $sc_install = $stp_json.parameters.scInstall
 $flag = $stp_json.parameters.jvmStartFlag
 $sc_logdir = $stp_json.parameters.scLogDir+"\$Env:COMPUTERNAME"
		
 $ctp_home = $tomcat_folder+"\stp"	
 $current_location = Get-Location

 # Compute Tomcat 7.x, Tomcat 9.x folder names
 
 $tomcat9 = Get-ChildItem .\ -Name | Where-Object {$_ -match "apache-tomcat"}
 $tomcat7 = Get-ChildItem -Path "$ctp_home\app\instances\SCjvm-1\" -Name | Where-Object{$_ -match "apache-tomcat"}
 
 # Initiate Migration Process
	#Step 1 : validate user inputs, terminate the execution, if fails 
		 validateInputs
	#Step 2 : Stop Soarian web instances (Soarian_Clinicals_12345_KDIMaintJVM-1,Soarian_Clinicals_12345_SC-JVM-1,Soarian_Clinicals_12345_SC-JVM-2,Soarian_Clinicals_12345_SC-JVM-3)
		 stopTCServices
	#Step 3 : Take necessary folders backup for reverting the system
		 takeBackUp
	#Step 4 : remove and place raw tomcat-9.x (without any soarian configurations) inside (stp\app\instances\[KDIMaintjvm-1,SCjvm-1,SCjvm-2,SCjvm-3])
		 .\MigrateToTomcat9.ps1
	#Step 5 : Delete jars specified in package.json
		 deleteJars
	#Step 6 : Add required jars specified in package.json and JDK 11.x under stp 
		 addJarsAndJDK
	#Step 7 : Remove and replace java 8 with java 11 under \Program Files\Java\jre\ directory
		removeAndReplaceJre
	
	#Step 8 : Iteratively modify tomcat 9.x batch to add soarian specific configurations
		 for ($j = 0; $j -le ($tc_instances.length - 1); $j += 1) {
				modifyTcBatch $tc_instances[$j]
			}
	#Step 9	: Create new tomcat services in windows registry with given user name/password, and start the same
		createScWebInstances
		
	Echo "Migration Successful"	
