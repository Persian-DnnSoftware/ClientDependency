param (
	[Parameter(Mandatory=$false)]
	[ValidatePattern("^\d+\.\d+\.(?:\d+\.\d+$|\d+$)")]
	[string]
	$ReleaseVersionNumber,
	[Parameter(Mandatory=$false)]
	[string]
	[AllowEmptyString()]
	$PreReleaseName,
	[Parameter(Mandatory=$false)]
	[int]
	$IsBuildServer = 0
)

if ([string]::IsNullOrEmpty($ReleaseVersionNumber)) {
	$tags = git tag --sort=-creatordate
	$ReleaseVersionNumber = $tags[0].Substring(1);
}

$PSScriptFilePath = (Get-Item $MyInvocation.MyCommand.Path).FullName
$RepoRoot = (get-item $PSScriptFilePath).Directory.FullName;
$SolutionRoot = Join-Path -Path $RepoRoot -ChildPath "src";

# Make sure we don't have a release folder for this version already
$BuildFolder = Join-Path -Path $RepoRoot -ChildPath "build";
$ReleaseFolder = Join-Path -Path $BuildFolder -ChildPath "Release";
if ((Get-Item $ReleaseFolder -ErrorAction SilentlyContinue) -ne $null)
{
	Write-Warning "$ReleaseFolder already exists on your local machine. It will now be deleted."
	Remove-Item $ReleaseFolder -Recurse
}

# Go get nuget.exe if we don't hae it
$NuGet = "$BuildFolder\nuget.exe"
$FileExists = Test-Path $NuGet 
If ($FileExists -eq $False) {
	Write-Host "Retrieving nuget.exe..."
	$SourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
	Invoke-WebRequest $SourceNugetExe -OutFile $NuGet
}

if ($IsBuildServer -eq 1) { 
	$MSBuild = "MSBuild.exe"
}
else {
	# ensure we have vswhere
	New-Item "$BuildFolder\vswhere" -type directory -force
	$vswhere = "$BuildFolder\vswhere.exe"
	if (-not (test-path $vswhere))
	{
	   Write-Host "Download VsWhere..."
	   $path = "$BuildFolder\tmp"
	   &$nuget install vswhere -OutputDirectory $path -Verbosity quiet
	   $dir = ls "$path\vswhere.*" | sort -property Name -descending | select -first 1
	   $file = ls -path "$dir" -name vswhere.exe -recurse
	   mv "$dir\$file" $vswhere   
	 }

	$MSBuild = &$vswhere -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | select-object -first 1
	if (-not (test-path $MSBuild)) {
	    throw "MSBuild not found!"
	}
}

Write-Host "MSBUILD = $MSBuild"

# Set the version number in SolutionInfo.cs
$SolutionInfoPath = Join-Path -Path $SolutionRoot -ChildPath "SolutionInfo.cs"
(gc -Path $SolutionInfoPath) `
	-replace "(?<=Version\(`")[.\d]*(?=`"\))", $ReleaseVersionNumber |
	sc -Path $SolutionInfoPath -Encoding UTF8
(gc -Path $SolutionInfoPath) `
	-replace "(?<=AssemblyInformationalVersion\(`")[.\w-]*(?=`"\))", "$ReleaseVersionNumber$PreReleaseName" |
	sc -Path $SolutionInfoPath -Encoding UTF8
# Set the copyright
(gc -Path $SolutionInfoPath) `
	-replace "(?<=AssemblyCopyright\(`".*?)\d\d\d\d(?=`"\))", (Get-Date).year |
	sc -Path $SolutionInfoPath -Encoding UTF8
	
# Build the solution in release mode (in both 4.0 and 4.5 and for MVC5)
$SolutionPath = Join-Path -Path $SolutionRoot -ChildPath "ClientDependency.dnn.sln"

# clean sln for all deploys
& $MSBuild "$SolutionPath" /p:Configuration=Release-Net45 /maxcpucount /t:Clean
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount /t:Clean
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}
& $MSBuild "$SolutionPath" /p:Configuration=Release-Net45 /maxcpucount /t:Clean
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}
& $MSBuild "$SolutionPath" /p:Configuration=Release-MVC5 /maxcpucount /t:Clean
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}

#restore nuget packages
Write-Host "Restoring nuget packages..."
& $NuGet restore $SolutionPath

#build for all deploys

# for net 3.5
& $MSBuild "$SolutionPath" /p:Configuration=Release-Net45 /maxcpucount
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}
# for net 4.0
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}
# for net 4.5
& $MSBuild "$SolutionPath" /p:Configuration=Release-Net45 /maxcpucount
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}
# for MVC 5
& $MSBuild "$SolutionPath" /p:Configuration=Release-MVC5 /maxcpucount
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}


$CoreFolder = Join-Path -Path $ReleaseFolder -ChildPath "Core";
$MvcFolder = Join-Path -Path $ReleaseFolder -ChildPath "Mvc";
$Mvc5Folder = Join-Path -Path $ReleaseFolder -ChildPath "Mvc5";
$LessFolder = Join-Path -Path $ReleaseFolder -ChildPath "Less";
$SassFolder = Join-Path -Path $ReleaseFolder -ChildPath "SASS";
$CoffeeFolder = Join-Path -Path $ReleaseFolder -ChildPath "Coffee";
$TypeScriptFolder = Join-Path -Path $ReleaseFolder -ChildPath "TypeScript";

New-Item $CoreFolder -Type directory
New-Item $MvcFolder -Type directory
New-Item $Mvc5Folder -Type directory
New-Item $LessFolder -Type directory
New-Item $SassFolder -Type directory
New-Item $CoffeeFolder -Type directory
New-Item $TypeScriptFolder -Type directory

$include = @('ClientDependency.Core.dll','ClientDependency.Core.pdb')
# Need to build to specific .Net version folders
$CoreBinFolderNet45 = Join-Path -Path $SolutionRoot -ChildPath "ClientDependency.Core\bin\Release-Net45";
$CoreFolderNet45 = Join-Path -Path $CoreFolder -ChildPath "net45";

New-Item $CoreFolderNet45 -Type directory
Copy-Item "$CoreBinFolderNet45\*.*" -Destination $CoreFolderNet45 -Include $include

$include = @('ClientDependency.Core.Mvc.dll','ClientDependency.Core.Mvc.pdb')
# Need to build to specific .Net version folders
$MvcBinFolderNet45 = Join-Path -Path $SolutionRoot -ChildPath "ClientDependency.Mvc\bin\Release-Net45";
$MvcFolderNet45 = Join-Path -Path $MvcFolder -ChildPath "net45";
New-Item $MvcFolderNet45 -Type directory
#Copy-Item "$MvcBinFolderNet45\*.*" -Destination $MvcFolderNet45 -Include $include
#need to build mvc5 separately
$Mvc5BinFolderNet45 = Join-Path -Path $SolutionRoot -ChildPath "ClientDependency.Mvc\bin\Release-MVC5";
$Mvc5FolderNet45 = Join-Path -Path $Mvc5Folder -ChildPath "net45";
New-Item $Mvc5FolderNet45 -Type directory
#Copy-Item "$Mvc5BinFolderNet45\*.*" -Destination $Mvc5FolderNet45 -Include $include

$include = @('ClientDependency.Less.dll','ClientDependency.Less.pdb')
$LessBinFolder = Join-Path -Path $SolutionRoot -ChildPath "ClientDependency.Less\bin\Release";
#Copy-Item "$LessBinFolder\*.*" -Destination $LessFolder -Include $include

$include = @('ClientDependency.SASS.dll','ClientDependency.SASS.pdb')
$SassBinFolder = Join-Path -Path $SolutionRoot -ChildPath "ClientDependency.SASS\bin\Release";
#Copy-Item "$SassBinFolder\*.*" -Destination $SassFolder -Include $include

$include = @('ClientDependency.Coffee.dll','ClientDependency.Coffee.pdb')
$CoffeeBinFolder = Join-Path -Path $SolutionRoot -ChildPath "ClientDependency.Coffee\bin\Release";
#Copy-Item "$CoffeeBinFolder\*.*" -Destination $CoffeeFolder -Include $include

$include = @('ClientDependency.TypeScript.dll','ClientDependency.TypeScript.pdb')
$TypeScriptBinFolder = Join-Path -Path $SolutionRoot -ChildPath "ClientDependency.TypeScript\bin\Release";
#Copy-Item "$TypeScriptBinFolder\*.*" -Destination $TypeScriptFolder -Include $include

# COPY THE TRANSFORMS OVER
Copy-Item "$BuildFolder\nuget-transforms\Core\web.config.*" -Destination (New-Item (Join-Path -Path $CoreFolder -ChildPath "nuget-transforms") -Type directory);
Copy-Item "$BuildFolder\nuget-transforms\Mvc\web.config.transform" -Destination (New-Item (Join-Path -Path $MvcFolder -ChildPath "nuget-transforms") -Type directory);
Copy-Item "$BuildFolder\nuget-transforms\Mvc\web.config.transform" -Destination (New-Item (Join-Path -Path $Mvc5Folder -ChildPath "nuget-transforms") -Type directory);
Copy-Item "$BuildFolder\nuget-transforms\Less\web.config.transform" -Destination (New-Item (Join-Path -Path $LessFolder -ChildPath "nuget-transforms") -Type directory);
Copy-Item "$BuildFolder\nuget-transforms\Coffee\web.config.transform" -Destination (New-Item (Join-Path -Path $CoffeeFolder -ChildPath "nuget-transforms") -Type directory);
Copy-Item "$BuildFolder\nuget-transforms\Sass\web.config.transform" -Destination (New-Item (Join-Path -Path $SassFolder -ChildPath "nuget-transforms") -Type directory);
Copy-Item "$BuildFolder\nuget-transforms\TypeScript\web.config.transform" -Destination (New-Item (Join-Path -Path $TypeScriptFolder -ChildPath "nuget-transforms") -Type directory);

$CopyrightYear = (Get-Date).year;

# COPY OVER THE CORE NUSPEC AND BUILD THE NUGET PACKAGE
$CoreNuSpecSource = Join-Path -Path $BuildFolder -ChildPath "ClientDependency.nuspec";
Copy-Item $CoreNuSpecSource -Destination $CoreFolder
$CoreNuSpec = Join-Path -Path $CoreFolder -ChildPath "ClientDependency.nuspec";
Write-Output "DEBUGGING: " $CoreNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName
& $NuGet pack $CoreNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName -Properties copyrightyear=$CopyrightYear

# COPY OVER THE MVC NUSPEC AND BUILD THE NUGET PACKAGE
$MvcNuSpecSource = Join-Path -Path $BuildFolder -ChildPath "ClientDependency-Mvc.nuspec";
Copy-Item $MvcNuSpecSource -Destination $MvcFolder
$MvcNuSpec = Join-Path -Path $MvcFolder -ChildPath "ClientDependency-Mvc.nuspec"
& $NuGet pack $MvcNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName -Properties copyrightyear=$CopyrightYear

# COPY OVER THE MVC5 NUSPEC AND BUILD THE NUGET PACKAGE
$Mvc5NuSpecSource = Join-Path -Path $BuildFolder -ChildPath "ClientDependency-Mvc5.nuspec";
Copy-Item $Mvc5NuSpecSource -Destination $Mvc5Folder
$Mvc5NuSpec = Join-Path -Path $Mvc5Folder -ChildPath "ClientDependency-Mvc5.nuspec"
& $NuGet pack $Mvc5NuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName -Properties copyrightyear=$CopyrightYear

# COPY OVER THE LESS NUSPEC AND BUILD THE NUGET PACKAGE
$LessNuSpecSource = Join-Path -Path $BuildFolder -ChildPath "ClientDependency-Less.nuspec";
Copy-Item $LessNuSpecSource -Destination $LessFolder
$LessNuSpec = Join-Path -Path $LessFolder -ChildPath "ClientDependency-Less.nuspec"
& $NuGet pack $LessNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName -Properties copyrightyear=$CopyrightYear

# COPY OVER THE SASS NUSPEC AND BUILD THE NUGET PACKAGE
$SassNuSpecSource = Join-Path -Path $BuildFolder -ChildPath "ClientDependency-SASS.nuspec";
Copy-Item $SassNuSpecSource -Destination $SassFolder
$SassNuSpec = Join-Path -Path $SassFolder -ChildPath "ClientDependency-SASS.nuspec"
& $NuGet pack $SassNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName -Properties copyrightyear=$CopyrightYear

# COPY OVER THE COFFEE NUSPEC AND BUILD THE NUGET PACKAGE
$CoffeeNuSpecSource = Join-Path -Path $BuildFolder -ChildPath "ClientDependency-Coffee.nuspec";
Copy-Item $CoffeeNuSpecSource -Destination $CoffeeFolder
$CoffeeNuSpec = Join-Path -Path $CoffeeFolder -ChildPath "ClientDependency-Coffee.nuspec"
& $NuGet pack $CoffeeNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName -Properties copyrightyear=$CopyrightYear

# COPY OVER THE TypeScript NUSPEC AND BUILD THE NUGET PACKAGE
$TypeScriptNuSpecSource = Join-Path -Path $BuildFolder -ChildPath "ClientDependency-TypeScript.nuspec";
Copy-Item $TypeScriptNuSpecSource -Destination $TypeScriptFolder
$TypeScriptNuSpec = Join-Path -Path $TypeScriptFolder -ChildPath "ClientDependency-TypeScript.nuspec"
& $NuGet pack $TypeScriptNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName -Properties copyrightyear=$CopyrightYear

""
"Build $ReleaseVersionNumber$PreReleaseName is done!"
"NuGet packages also created, so if you want to push them just run:"
"  nuget push $CoreNuSpec"
"  nuget push $MvcNuSpec"