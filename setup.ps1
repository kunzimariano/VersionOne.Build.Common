param(
    [alias("env")]
    $environment = ''
)

function GetModulePath([string]$module){
	$commonPath = @(Get-ChildItem -r -Path packages -filter $module | Sort-Object FullName  -descending)
	return $commonPath[0].FullName
}

function DownloadNuget(){
	new-item (Get-Location).Path -name .nuget -type directory -force
	$destination = (Get-Location).Path + '\.nuget\nuget.exe'	
	Invoke-WebRequest -Uri "http://nuget.org/nuget.exe" -OutFile $destination
}

function DownloadAndImportModules(){
	.nuget\nuget.exe install psake -OutputDirectory packages -NoCache
	.nuget\nuget.exe install VersionOne.Build.Common -Source http://www.myget.org/F/versionone/api/v2/ -OutputDirectory  packages -NoCache	
	$psakePath = GetModulePath "psake.psm1"
	Import-Module $psakePath	
}

function CopyCommonToRoot(){
	$commonPath = GetModulePath "VersionOne.Build.Common.ps1"
	Copy-Item -Path $commonPath -Destination (Get-Location).Path -Force
}

DownloadNuget
DownloadAndImportModules
CopyCommonToRoot
Invoke-psake VersionOne.Build.Common.ps1 $environment
