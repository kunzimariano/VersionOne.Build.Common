properties {	
	$config = Get-ConfigObject
	$version = $config.version + '.' + (Get-EnvironmentVariableOrDefault "BUILD_NUMBER" $config.buildNumber)
}

#groups of tasks
task default -depends RestoreAndUpdatePackages,Build,runUnitTests
task jenkins -depends default,PushMyget

#tasks
task validateInput {
	#TODO: validate build.properties.json
}

task build -depends clean,generateAssemblyInfo {
	$solution = $config.solution
	$configuration = $config.configuration
	$platform = $config.platform
	exec { msbuild $solution -t:Build -p:Configuration=$configuration "-p:Platform=$platform" }	
}
 
task clean {
	$solution = $config.solution
	$configuration = $config.configuration
	$platform = $config.platform
	exec { msbuild $solution -t:Clean -p:Configuration=$configuration "-p:Platform=$platform" }	
}

task restoreAndUpdatePackages {
	exec { .\\.nuget\nuget.exe restore  $config.solution -Source $config.nugetSources }	
	exec { .\\.nuget\nuget.exe update  $config.solution -Source $config.nugetSources }	
}
 
task generateAssemblyInfo{	
	Write-AssemblyInfo $version $config.organizationName
}

task setUpNuget {
	New-NugetDirectory
	Get-NugetBinary
}

task generateNugetPackage{	
	$project = $config.projectToPackage
	$configuration = $config.configuration
	exec { .\\.nuget\nuget.exe pack $project -Verbosity Detailed -Version $version -prop Configuration=$configuration }
}

task pushMyget -depends GenerateNugetPackage{
	exec { .\\.nuget\nuget.exe push *.nupkg $env:MYGET_API_KEY -Source $env:MYGET_REPO_URL }
}

task installNunitRunners{
	exec { .\\.nuget\nuget.exe install NUnit.Runners -OutputDirectory packages }
}

task runUnitTests{
	$testRunner = Get-NewestFilePath "nunit-console-x86.exe"
	#TODO: extract method
	$dllsToTest = @(gci -ex *packages* | where {$_.Attributes -eq 'Directory'} | foreach {gci $_.FullName -r -fi *.Tests.dll} |?{$_.FullName.Contains("bin")})
	
	foreach($test in $dllsToTest)
	{
		$fullName = $test.FullName		
		exec { iex "$testRunner $fullName" }
	}
}

task publish{
	$project = $config.projectToPublish
	$configuration = $config.configuration
	exec { msbuild $project -t:Publish -p:Configuration=$configuration }	
}

#helpers

function Get-ConfigObject(){
	return Get-Content .\build.properties.json -Raw | ConvertFrom-Json	
}

function Get-EnvironmentVariableOrDefault([string] $variable, [string]$default){		
	if([Environment]::GetEnvironmentVariable($variable))
	{
		return [Environment]::GetEnvironmentVariable($variable)
	}
	else
	{
		return $default
	}
}

function Get-NewestFilePath([string]$file){
	$paths = @(Get-ChildItem -r -Path packages -filter $file | Sort-Object FullName  -descending)
	return $paths[0].FullName
}

function New-NugetDirectory(){
	new-item (Get-Location).Path -name .nuget -type directory -force
}

function Get-NugetBinary (){		
	$destination = (Get-Location).Path + '\.nuget\nuget.exe'	
	Invoke-WebRequest -Uri "http://nuget.org/nuget.exe" -OutFile $destination
}

#TODO: Don't overwrite, make it update
function Write-AssemblyInfo($version,$organizationName){
	$files = Get-ChildItem -r -filter AssemblyInfo.cs
	if($files -ne $null)
	{
		foreach($f in $files) {		
			$componentName = Get-CSharpComponentName $f.fullname
			$template = Get-CSharpAssemblyInfoTemplate $version $organizationName $componentName			
			Set-Content -Path $f.fullname -Value $template
		}
	}
	
	$files = Get-ChildItem -r -filter AssemblyInfo.fs
	if($files -ne $null)
	{
		foreach($f in $files) {		
			$componentName = Get-FSharpComponentName $f.fullname		
			$template = Get-FSharpAssemblyInfoTemplate $version $organizationName $componentName
			Set-Content -Path $f.fullname -Value $template
		}
	}
	
}

function Get-CSharpComponentName($fullPath){	
	$pattern = '([a-zA-Z\.])*?(?=\\Properties\\AssemblyInfo.cs)'
	$result = ($fullPath | Select-String -Pattern $pattern -allmatches).matches		
	return $result.value
}

function Get-FSharpComponentName($fullPath){	
	$pattern = '([a-zA-Z\.])*?(?=\\Properties\\AssemblyInfo.fs)'
	$result = ($fullPath | Select-String -Pattern $pattern -allmatches).matches	
	return $result.value
}

function Get-CSharpAssemblyInfoTemplate(
	[string]$version, 
	[string]$organizationName, 
	[string]$componentName ){
	
return @"
using System;
using System.Reflection;
using System.Resources;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

[assembly: AssemblyVersion("$version")]
[assembly: AssemblyFileVersion("$version")]
[assembly: AssemblyCompany("$organizationName")]
[assembly: AssemblyDescription("$componentName")]

"@
}

function Get-FSharpAssemblyInfoTemplate(
	[string]$version, 
	[string]$organizationName, 
	[string]$componentName ){
	
return @"
module AssemblyInfo

open System.Reflection

[<assembly: AssemblyVersion("$version")>]
[<assembly: AssemblyFileVersion("$version")>]
[<assembly: AssemblyCompany("$organizationName")>]
[<assembly: AssemblyDescription("$componentName")>]

do ()
"@
}