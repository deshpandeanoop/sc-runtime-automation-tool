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

 $ctp_home =$null
 $tc_instances = 'KDIMaintjvm-1','SCjvm-1','SCjvm-2','SCjvm-3'
 $stp_json = Get-Content package.json | ConvertFrom-Json
 $tomcat_folder = $stp_json.parameters.stpInstall
 $ctp_home = $tomcat_folder+"\stp"	
 $sc_logdir = $stp_json.parameters.scLogDir+"\$Env:COMPUTERNAME"
 $currentLogBkupFolderName = "Logs_"+$Env:COMPUTERNAME
 $current_location = Get-Location
 
 copyLogs