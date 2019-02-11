<#
	Script for upgrading Soarin Web Server from Tomcat 7.x to Tomcat 9.x
	Algorithm : 
		- Copy Tomcat 9.x from current dirctory (which is raw tomcat without soarian configurations) to 
			[stp_app_bkp\app\instances\[KDIMaintjvm-1,SCJvm-1,SCJvm-2, SCJvm-3]]
		
		- Iteratively add soarian specific configurations to each tomcat instance	
#>

# Removes Tomcat-7.x and copies Tomcat-9.x to [stp_app_bkp\app\instances\[KDIMaintjvm-1,SCJvm-1,SCJvm-2, SCJvm-3]]

function copyTomcat9ToStp(){

	Echo "Removing tomcat 7 and copy tomcat 9"
	$tc_instance_root = $ctp_home+"\app\instances"

	for($i = 0 ; $i -lt $tc_instances.length ; ++$i){
	
		$tomcat_instance = "$tc_instance_root\"+$tc_instances[$i]
		Remove-Item $tomcat_instance\$tomcat7 -Recurse
		$src = "$current_location\$tomcat9"
		$dest = "$tc_instance_root\"+$tc_instances[$i]+"\$tomcat9"
		
		Copy-Item -Path $src -Destination $dest -Recurse
	}
}

function configureTomcat9Instances(){
	$tomcat7_root = ".\stp_app_bkp\app\instances"
	$tomcat9_root = "$ctp_home\app\instances"
	for($i =0 ; $i -lt $tc_instances.length ; ++$i){
		$tomcat7_path = "$tomcat7_root\"+$tc_instances[$i]+"\$tomcat7"
		$tomcat9_path = "$tomcat9_root\"+$tc_instances[$i]+"\$tomcat9"
	
		configureTomcat9Instance $tomcat7_path $tomcat9_path
	}
}

# Adds sorian specific configuration to Tomcat 9.x 

function configureTomcat9Instance([string] $tomcat7_path,[string] $tomcat9_path){
	Echo "Configure bin folder"
	
	Copy-Item $tomcat7_path\bin\setenv.bat -Destination $tomcat9_path\bin\setenv.bat
	Copy-Item $tomcat7_path\bin\sqljdbc_auth.dll -Destination $tomcat9_path\bin\sqljdbc_auth.dll
	Copy-Item $tomcat7_path\bin\TCServiceInstall.bat -Destination $tomcat9_path\bin\TCServiceInstall.bat
	
	$file = $tomcat9_path+"\bin\TCServiceInstall.bat"
	(Get-Content $file) -replace('tomcat7','tomcat9') | Set-Content $file
	Echo "Modified TCServiceInstall.bat file"
	
	$file = $tomcat9_path+"\conf\catalina.properties"
	$file_content = Get-Content $file
	$file_content_buffer = ""
	
	foreach($line in $file_content){
		if($file_content_buffer -eq ""){
			$file_content_buffer = $line
		}
		elseif($line -match "common.loader"){
			$file_content_buffer = $file_content_buffer + 'common.loader=${catalina.base}/lib/*.jar,${catalina.home}/lib/*.jar,${STP_HOME}/app/lib/ctp_platform_tc7-1.2.20/conf,${STP_HOME}/app/lib/ctp_platform_tc7-1.2.20/cerner/*.jar,${STP_HOME}/app/lib/ctp_platform_tc7-1.2.20/ext/*.jar,${STP_HOME}/app/lib/sc-ext/*.jar'+"`n"
		}
		elseif($line -match "xom-*"){
			$file_content_buffer = $file_content_buffer + 'xom-*.jar,\serializer*.jar'+"`n"

		}
		else{
			$file_content_buffer = $file_content_buffer + $line+"`n"
		}
	}
	
	$file_content_buffer = $file_content_buffer + "org.apache.catalina.startup.TldConfig.jarsToSkip=tomcat-websocket.jar"+"`n"
	$file_content_buffer = $file_content_buffer + "org.apache.tomcat.util.digester.PROPERTY_SOURCE=com.siemens.cto.infrastructure.properties.StpPropertySource"+"`n"
	$file_content_buffer = $file_content_buffer + "org.apache.jasper.compiler.Generator.STRICT_GET_PROPERTY=false" + "`n"
	Set-Content $file $file_content_buffer
	
	Echo "catalina.properties file modified successfully"
	
	$file = $tomcat9_path+"\conf\context.xml"
	$file_content = Get-Content $file
	$file_content_buffer = ""
	
	foreach($line in $file_content){
		if($file_content_buffer -eq ""){
			$file_content_buffer = $line
		}
		elseif($line -match "WEB-INF/web.xml"){
			$file_content_buffer = $file_content_buffer + $line + "`n"+
									'<Transaction factory="org.springframework.transaction.jta.JtaTransactionManager"/>'+"`n"+
									'<Valve className="com.siemens.cto.security.tomcat.SamlAuthenticationValve" ignoreList=".*KnowledgeBaseServlet.*"/>' + "`n"	
		}
		elseif (($line -match "WEB-INF/tomcat-web.xml") -or ($line -match "${catalina.base}/conf/web.xml")){
			# We no longer needed this configuration, so eliminating the same
		}
		else{
			$file_content_buffer = $file_content_buffer + $line + "`n"
		}
	}
	Set-Content $file $file_content_buffer
	
	Echo "Context.xml modified successfully"
	
		Copy-Item $tomcat7_path\conf\server.xml -Destination $tomcat9_path\conf\server.xml
		$file = $tomcat9_path+"\conf\server.xml"	
		(Get-Content $file) -replace('<Listener className="org.apache.catalina.core.JasperListener"/>','<!-- <Listener className="org.apache.catalina.core.JasperListener"/> -->') |Set-Content $file

	Echo "Server.xml configured successfully"	

		Copy-Item $tomcat7_path\conf\Catalina -Destination $tomcat9_path\conf\Catalina -Recurse
		Copy-Item $tomcat7_path\conf\stp -Destination $tomcat9_path\conf\stp -Recurse

	Echo "Catalina and stp folders are copied successfully"

	$file = $tomcat9_path+"\conf\stp\localhost\manager.xml"
	(Get-Content $file) -replace('antiJARLocking="false"','') | Set-Content $file

	# KDI tomcat node doesn't have Patientapi.xml, so skipping the same
	if(-Not ($tomcat9_path -match "KDIMaintjvm-1")){
		$file = $tomcat9_path+"\conf\Catalina\localhost\Patientapi.xml"
		(Get-Content $file) -replace('com.atomikos.jdbc.nonxa.AtomikosNonXADataSourceBean','javax.sql.DataSource') | Set-Content $file
	}

	# Change the class loader configuration(Virtual Web App loader), since the name of the XML file is indeterministic, scanning through 
	# entire folder. From performance perspective, it is minimal

	Get-ChildItem ("$tomcat9_path\conf\Catalina\localhost\") -Name |
		Foreach-Object {
			
			$file = "$tomcat9_path\conf\Catalina\localhost\$_"
			$file_content = Get-Content $file
			$file_content_buffer = ""
			
			foreach($line in $file_content){
				if($file_content_buffer -eq ""){
					$file_content_buffer = $line+"`n"
				}
				elseif($line -match "VirtualWebappLoader"){
					$file_content_buffer = $file_content_buffer + "`n" +
							"`t"+"<Resources>" +"`n"+
							"`t"+'<PreResources base="${STP_HOME}/app/lib/dst-1.2"'+"`n"+
							"`t"+ 'className="org.apache.catalina.webresources.DirResourceSet" readOnly="true"' + "`n" +
							"`t"+ 'internalPath="/" webAppMount="/WEB-INF/lib" />' + "`n" +
							"`t"+ '</Resources>'+"`n"
				}
				else{
					$file_content_buffer = $file_content_buffer + $line + "`n"
				}
			}
			
			Set-Content $file $file_content_buffer
		}
	Echo "Catlina and stp folders modified successfully"
			
		Remove-Item $tomcat9_path\temp -Recurse
		Copy-Item $tomcat7_path\temp -Destination $tomcat9_path\temp -Recurse

	Echo "Copied temp folder"

}

#Initiate Tomcat 9.x migration
	# Step 1 - Copy raw tomcat 9.x (without any soarian specific configurations) to \stp\app\instances\[KDIMaintjvm-1,SCJvm-1,SCJvm-2,SCJvm-3]
		copyTomcat9ToStp
	# Step 2-  Iteratively add soarian specific configuration to each tomcat instance
		configureTomcat9Instances
