<#
.NOTES
Spodi's Powershell Game Library Module v24.04.05
    Copyright (C) 2022-2023  Spodi

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
#>

enum AppType {
	Unknown
	Game
	Demo
	Application
	AddOn
	Music
	Tool
}
enum PlatformName {
	Unknown
	Steam
	EGS
	GOG
	XBOX
	itch
	SKIF
}
enum OSType {
	Unknown
	Windows
	Linux
	MacOS
}
enum Architecture {
	Unknown = 0x0000
	ALPHA = 0x0184
	AM33 = 0x01d3
	AMD64 = 0x8664 # aka x64
	ARM = 0x01c0
	ARMNT = 0x01c4 # aka ARMV7
	ARM64 = 0xaa64 # aka ARMV8
	EBC = 0x0ebc
	I386 = 0x014c # aka x86
	I860 = 0x014d
	IA64 = 0x0200
	M68K = 0x0268
	M32R = 0x9041
	MIPS16 = 0x0266
	MIPSFPU = 0x0366
	MIPSFPU16 = 0x0466
	POWERPC = 0x01f0
	POWERPCFP = 0x01f1
	POWERPCBE = 0x01f2
	R3000 = 0x0162
	R4000 = 0x0166
	R10000 = 0x0168
	SH3 = 0x01a2
	SH3DSP = 0x01a3
	SH4 = 0x01a6
	SH5 = 0x01a8
	TRICORE = 0x0520
	THUMB = 0x01c2
	WCEMIPSV2 = 0x0169
	ALPHA64 = 0x0284
	Invalid = 0xffff
}

class Platform {
	[PlatformName]$Name
	[String]$ID
}

class LaunchParamSet {
	[String]$Executable
	[String]$WorkingDir
	[String]$Arguments
	[OSType]$OS
	[Architecture]$Arch
	[String]$Description

	[String]ToString() {
		if ($this.Arguments) {
			return "$($this.Executable) $($this.Arguments)"
		}
		else {
			return $this.Executable
		}
	}
}

class App {
	[String]$Name
	[AppType]$Type
	[Platform[]]$Platform
	[String]$Path
	[LaunchParamSet[]]$Launch
}

$PSObjectToHashtable = {
	function Convert-PSObjectToHashtable {
		param (
			[Parameter(ValueFromPipeline)]
			$InputObject
		)

		process {
			if ($null -eq $InputObject) { return $null }
			if ($InputObject -is [Hashtable] -or $InputObject.GetType().Name -eq 'OrderedDictionary') { return $InputObject }

			if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
				$collection = @(
					foreach ($object in $InputObject) { $object }
				)

				Write-Output -NoEnumerate $collection
			}
			elseif ($InputObject -is [psobject]) {
				$hash = @{}

				foreach ($property in $InputObject.PSObject.Properties) {
					$hash[$property.Name] = $property.Value
				}

				$hash
			}
			else {
				$InputObject
			}
		}
	}
}
. $PSObjectToHashtable
function Convert-VDFTokens {
	[CmdletBinding()]
	param (
		[Parameter()][String[]]$Tokens,
		[Parameter()][int]$pos = 0
	)
	$out = @{}
	for ($iVDFToken = $pos; $iVDFToken -lt $Tokens.count; $iVDFToken++) {
		if ($Tokens[$iVDFToken + 1] -ne '{' -and $Tokens[$iVDFToken] -ne '}') {
			$out.add($Tokens[$iVDFToken], $Tokens[$iVDFToken + 1])
			$iVDFToken++
		}
		elseif ($Tokens[$iVDFToken + 1] -eq '{') {
			$iVDFToken += 2
			$out.add($Tokens[$iVDFToken - 2], (Convert-VDFTokens $Tokens ($iVDFToken)))

		}
		elseif ($Tokens[$iVDFToken] -eq '}') {
			break
		}
	}
	$out
}
Set-Variable iVDFToken -Option AllScope
$inputRegex = [regex]::new('".*?"|[^{\s}]+|{|}', 'Compiled, IgnoreCase, CultureInvariant')
Function ConvertFrom-VDF {
	param
	(
		[Parameter(Position = 0, Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[String[]]$InputObject
	)
	process {
		$InputObject = $InputObject -replace '\/\/.*(\r\n|\r|\n|$)', ''
		Convert-VDFTokens ($inputRegex.Matches($InputObject).Value -replace '^""$', $null -replace '^"(.+)"$', '$1')
	}
    
}
function Add-SteamAppIDText {
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline)]$Games
	)
	process {
		if ($Games.Path) {
			if ($Games.Launch.Executable) {
				
				$path = $Games.Launch.Executable | & { Process {
						Join-Path (Split-Path (Join-Path $games.path $_)) steam_appid.txt
					} }
			}
			else {
				$path = Join-Path $Games.Path steam_appid.txt
			}
		}
		if ($path) {
			$path | & { Process {
					if (Test-Path $_) {
						$id = Get-Content -TotalCount 1 -LiteralPath $_
						if ($id) { 
							if (($Games.Platform | & { Process {
								($_.Name -ne 'Steam' -or $_.ID -ne $id)
										} }) ) {
								[Array]$Games.Platform += [Platform]@{Name = 'Steam'; ID = $id }
							}
						}
					}
				} }
		}
		Write-Output $Games
	}
}

function Get-LibrarySteam {
	$Registry	=	'Registry::HKEY_CURRENT_USER\Software\Valve\Steam\'
	#get Steam games
	if (Test-Path $registry) {
		Write-Verbose 'Steam install found!'

		$storePath = "$((Get-ItemProperty $registry).SteamPath)".Replace('/', '\')

		# Old: \steamapps\libraryfolders.vdf
		# New:    \config\libraryfolders.vdf

		If (Test-Path "$($storePath)\config\libraryfolders.vdf") {
			$steamVdf = ConvertFrom-VDF (Get-Content "$($storePath)\config\libraryfolders.vdf" -Encoding UTF8)
		}
		else {
			$steamVdf = ConvertFrom-VDF (Get-Content "$($storePath)\steamapps\libraryfolders.vdf" -Encoding UTF8)
		}

		$libraryPaths = $steamVdf.libraryfolders.GetEnumerator() | & { Process {
				#god, .GetEnumerator() makes it so much easier, than using get-member
				if ($null -ne $_.value.path) {
					$_.value.path
				}
			} }
		$manifestFiles = ($libraryPaths -replace '\\\\', '\') | & { Process {
				if (Test-Path $_) {
					[System.IO.Directory]::EnumerateFiles("$_\SteamApps\", '*.acf')
				} 
			} }
		$appids = $manifestFiles | & { Process { [System.IO.Path]::GetFileNameWithoutExtension($_) -replace 'appmanifest_', '' } } 
	

		$RSAppinfo = [powershell]::Create()
		$RSAppinfo.Runspace.SessionStateProxy.SetVariable('appids', $appids)
		$RSAppinfo.Runspace.SessionStateProxy.SetVariable('Root', $PSScriptRoot)
		$RSAppinfo.Runspace.SessionStateProxy.SetVariable('PSObjectToHashtable', $PSObjectToHashtable)
		[void]$RSAppinfo.AddScript({
				$function = [ScriptBlock]::Create($PSObjectToHashtable)
				. $function

				$VDFParse = Join-Path $Root 'VDFparse.exe'
				if (Test-Path $VDFParse -PathType 'Leaf') {
					$appinfo = (. $VDFParse appinfo $appids) | ConvertFrom-Json -ErrorAction SilentlyContinue
					if ($LASTEXITCODE -or !$appinfo) {
						Write-Warning "Steam install found and `"VDFparse.exe`" found, but it encountered an error.
Only basic info can be retrieved."	
					}
				}
				else {
					Write-Warning "Steam install found, but no `"VDFparse.exe`" is present in `"$Root`".
Only basic info can be retrieved."
				}

				if ($appinfo) {
					$appinfo.datasets | & { Process {
							if ($_.Data.appinfo.depots) {
								$_.Data.appinfo.depots = $_.Data.appinfo.depots | Convert-PSObjectToHashtable
								$_.Data.appinfo.depots.GetEnumerator() | & { Process {
										if ($_.Value.Manifests) {
											$_.Value.Manifests = $_.Value.Manifests | Convert-PSObjectToHashtable
										}
									} }
							}
							if ($_.Data.appinfo.config.launch) {
								$_.Data.appinfo.config.launch = $_.Data.appinfo.config.launch | Convert-PSObjectToHashtable
											
							}
					
						} }
					Write-Output $appinfo
				}
				
			})
		$RSAppinfoHandle = $RSAppinfo.BeginInvoke()
		
		$steamapps = $manifestFiles | & { Process {
				$manifest = ConvertFrom-VDF (Get-Content $_ -Encoding UTF8)
					 
						
				if ($manifest.AppState.name) {
						
					#if (Test-Path $steamgamepath) {
					Write-Output ([PSCustomObject]@{
							Name            = $manifest.AppState.name
							ID              = [String]$manifest.AppState.appid
							LibPath         = [System.IO.Path]::GetDirectoryName($_)
							Path            = $manifest.AppState.installdir
							InstalledDepots = ($manifest.AppState.InstalledDepots | Convert-PSObjectToHashtable).keys
							Branch          = Invoke-Command { if ($manifest.AppState.MountedConfig.BetaKey) { $manifest.AppState.MountedConfig.BetaKey } else { $null } }
						})
				}
			} }
	
		$appinfo = $RSAppinfo.EndInvoke($RSAppinfoHandle)
		$RSAppinfo.Runspace.Close()
		$RSAppinfo.Dispose()

		foreach ($game in $steamapps) {
			############
			$LibPath = $game.LibPath
			$Path = $game.Path
			$type = $appinfo.datasets | & { Process { if ($_.id -eq $game.id) { $_.Data.appinfo.common.type } } }
			
			if ($type) {
				$steamgamepath = switch ( $type ) {
					'Music' { Join-Path (Join-Path $LibPath '\music\') $Path }
					default { Join-Path (Join-Path $LibPath '\common\') $Path }
				}
			}
			else { $steamgamepath = Join-Path (Join-Path $LibPath '\common\') $Path }

			if ((Test-Path $steamgamepath)) {
				$gameobject = [App]@{
					Name     = $game.Name
					Type     = & { if ($type) { $type } else { 0 } }
					Platform = [Platform]@{
						Name = 'Steam'
						ID   = $game.ID
					}
					Path     = "$steamgamepath\"
				}
				if ($appinfo) {
					if ( ($appinfo.datasets | Where-Object id -EQ $game.ID).data.appinfo.config.launch ) {
						$branch = $game.Branch
						$launch = ($appinfo.datasets | Where-Object id -EQ $game.ID).Data.appinfo.config.launch.GetEnumerator() | & { Process {
								if (  $_.value.executable ) {
									if (($branch -eq $_.value.config.betakey) -or !$_.value.config.betakey) {
										[LaunchParamSet]@{
											Executable  = $_.value.executable
											Arguments   =	$_.value.arguments
											WorkingDir  =	$_.value.workingdir 
											Arch        = & { if ($_.value.config.osarch -eq 64)	{ 'AMD64' }
												elseif ($_.value.config.osarch -eq 32)	{ 'I386' }
												else { 0 } }
											Description =	$_.value.description 
											OS          = & { 
												if ($_.value.config.oslist) { $_.value.config.oslist }
												elseif ([System.IO.Path]::GetExtension($_.value.Executable) -eq '.exe') { 'Windows' }
												else { 0 }
											}
										}
									}
								}
							} }
						if ($launch) { $gameobject.Launch = $launch }
					}
				}
				Write-Output $gameobject | Add-SteamAppIDText
			}
			
		}
	}
}

function Get-LibraryEGS {
	$Registry	=	'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Epic Games\EpicGamesLauncher'
	#Get EGS games
	if (Test-Path $Registry) { 
		Write-Verbose 'EGS install found!'

		$storePath = (Get-ItemProperty -Path $Registry).AppDataPath
		if (Test-Path "$storePath\Manifests") {
			[System.IO.Directory]::EnumerateFiles("$storePath\Manifests", '*.item') | & { Process {
					$manifest = (Get-Content -Path $_ -Encoding UTF8) | ConvertFrom-Json
					if (Test-Path $manifest.InstallLocation) {
						if ($manifest.AppCategories -Contains 'games') { $type = 'Game' } elseif ($manifest.AppCategories -Contains 'software') { $type = 'Application' }
						$gameobject = [App]@{
							Name     = $manifest.DisplayName
							Type     = $type
							Platform = [Platform]@{
								Name = 'EGS'
								ID   = $manifest.InstallationGuid
							}
							Path     = "$($manifest.InstallLocation)\"
						}
						if ( $manifest.LaunchExecutable ) {
							$launch = [LaunchParamSet]@{
								Executable =	$manifest.LaunchExecutable
								Arguments  = $manifest.LaunchCommand
							}
							if ([System.IO.Path]::GetExtension($manifest.LaunchExecutable) -eq '.exe') { $launch.OS = 'Windows' } 
						}
							
					}
					if ($launch) { $gameobject.Launch = $launch }
					Write-Output $gameobject | Add-SteamAppIDText
				}
				
			} 
  }
	}
}
function Get-LibraryGOG {
	$Registry	=	'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\GOG.com\Games'
	#Get GOG games
	if (Test-Path $Registry) {
		Write-Verbose 'GOG install found!'

			(Get-Item -Path $Registry).GetSubKeyNames() | & { Process {
				$manifest = Get-ItemProperty -Path "$Registry\$_"
				if (!$manifest.dependsOn) {
					if (Test-Path $manifest.path) {
						$gameobject = [App]@{
							Name     = $manifest.gameName
							Platform = [Platform]@{
								Name = 'GOG'
								ID   = [String]$manifest.gameID
							}
							Path     = "$($manifest.path)\"
						}
						
						if ( $manifest.launchCommand ) {
							$executable = $manifest.launchCommand.Replace($gameobject.path, '') -replace (' $', '')
							$launch = [LaunchParamSet]@{
								Executable =	$executable
								Arguments  = $manifest.LaunchParamSet
							}
							if ($manifest.workingDir.Replace($manifest.path, ''))	{ $launch.WorkingDir = $manifest.workingDir.Replace($gameobject.path, '') }
							if ([System.IO.Path]::GetExtension($launch.Executable) -eq '.exe') { $launch.OS = 'Windows' }
						
						}
						if ($launch) { $gameobject.Launch = $launch }
						Write-Output $gameobject | Add-SteamAppIDText
					}
				
						
				}
			} }
	}
}
function Get-LibraryXBOX {
	$Registry	=	'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\GamingServices\PackageRepository\Root'
	#Get XBOX games
	if (Test-Path $Registry) {
				
		Write-Verbose 'XBOX install found!'
		$xbox = (Get-ChildItem -Path "$Registry\*\*") | & { Process {
				$ImagePath = (($_ | Get-ItemProperty).Root).Replace('\\?\', '')
				$manifest = Join-Path $ImagePath '/appxmanifest.xml'

				if (Test-Path $manifest -PathType 'Leaf') {
					[xml]$xml = Get-Content (Join-Path $ImagePath '/appxmanifest.xml') -Encoding 'Utf8'
					Write-Output @{
						Drive = $ImagePath.Substring(0, 3)
						ID    = $xml.Package.Identity.Name
						Name  = $xml.Package.Properties.DisplayName
					}
				}
			} }
		# Gets install folders
		$xboxDrives = ($xbox.Drive | Sort-Object -Unique) | & { Process {
				if (Test-Path (Join-Path $_ '\.GamingRoot') -PathType 'Leaf') {
					Write-Output @{
						Drive = $_
						Root  = Join-Path $_ (((Get-Content "$_\.GamingRoot" -Encoding 'Unicode').Substring(4)).replace("`0", '')) # String needs to be cleaned out of null characters.
					}
				}
			} }
		$xbox | & { Process {
				$_.add('Path', ( Join-Path ($xboxDrives | Where-Object Drive -EQ $_.Drive).Root "$($_.Name -replace ('\\|\/|:|\*|\?|"|<|>|\|','-'))\Content\"))
			
				if (Test-Path $_.Path) {

					$gameobject = ([App]@{
							Name     = $_.Name
							Platform = [Platform]@{
								Name = 'XBOX'
								ID   = $_.id 
							}
							Path     = $_.Path
						})
				}
				$manifest = [xml](Get-Content (Join-Path $_.Path 'appxmanifest.xml'))
				if (($manifest.Package.Applications.Application.Attributes | Where-Object Name -EQ Executable).Value) {
					$launch = [LaunchParamSet]@{
						Executable =	($manifest.Package.Applications.Application.Attributes | Where-Object Name -EQ Executable).Value
						OS         = 'Windows'
					}
				}
				if ($launch) { $gameobject.Launch = $launch }
				Write-Output $gameobject | Add-SteamAppIDText
			} }
	}
}
function Get-LibraryItch {
	$storePath	=	Join-Path $env:APPDATA '/itch/db/butler.db'
	if (Test-Path $storePath -PathType 'Leaf') {
		Write-Verbose 'itch install found!'
		$sqlite = Join-Path $PSScriptRoot 'sqlite3.exe'
		if (Test-Path $sqlite -PathType 'Leaf') {
			$manifest = ( (. $sqlite -json $storePath 'SELECT verdict,title,classification,game_id FROM caves INNER JOIN games ON caves.game_id = games.id;') | ConvertFrom-Json) | & { Process {
					$_.verdict = $_.verdict | ConvertFrom-Json
					$_
				} }
			$manifest | & { Process {
					if (Test-Path $_.verdict.basePath) {
						$gameobject = ([App]@{
								Name     = $_.title
								Type     = $_.classification
								Platform = [Platform]@{
									Name = 'itch'
									ID   = $_.game_id
								}
								Path     = "$($_.verdict.basePath)\"
							})
				
						$launch = $_.verdict.candidates | & { Process {
								[LaunchParamSet]@{
									Executable = $_.path
									OS         = $_.flavor
									Arch       = & { if ($_.arch -eq 386) { 'I386' } else { $_.arch } }
								}
							} }
						if ($launch) { $gameobject.Launch = $launch }
					}
					Write-Output $gameobject | Add-SteamAppIDText
				} }
		}
		else {
			Write-Warning "itch install found, but no `"SQlite3.exe`" is present in `"$PSScriptRoot`".
Please put the SQLite command line tool in `"$PSScriptRoot`" to add support for itch."
		}
	}	
}
function Get-LibrarySKIF {
	$Registry	=	'Registry::HKEY_CURRENT_USER\SOFTWARE\Kaldaien\Special K\Games'
	#Get custom SKIF games
	if (Test-Path $Registry) {
		Write-Verbose 'SKIF install found!'

	(Get-Item -Path $Registry).GetSubKeyNames() | & { Process {
				$manifest = Get-ItemProperty -Path "$Registry\$_"
				if (Test-Path $manifest.InstallDir) {
					$gameobject = ([App]@{
							Name     = $manifest.Name
							Platform = [Platform]@{
								Name = 'SKIF'
								ID   = $manifest.ID
							}
							Path     = "$($manifest.InstallDir)\"
						})
					if ( $manifest.ExeFileName ) {
						$launch = [LaunchParamSet]@{ Executable =	$manifest.ExeFileName }
						if ($manifest.LaunchOptions) { $launch.Arguments = $manifest.LaunchOptions }
					}
					if ($launch) { $gameobject.Launch = $launch }
					Write-Output $gameobject | Add-SteamAppIDText
				}
			
			} }
	}
}

function Get-GameLibraries { 
	[CmdletBinding()]
	param (
		[Parameter()][String[]]$Platforms
	)
	& {
		if ($null -ne $Platforms) {
			switch ($Platforms) {
				'Steam'	{ Get-LibrarySteam }
				'EGS'	{ Get-LibraryEGS }
				'GOG'	{ Get-LibraryGOG }
				'XBOX'	{ Get-LibraryXBOX }
				'itch'	{ Get-LibraryItch }
				'SKIF'	{ Get-LibrarySKIF }
				default { Write-Warning "Unknown Plattform: $_" }
			} 
		}
		else {
			Get-LibrarySteam
			Get-LibraryEGS
			Get-LibraryGOG
			Get-LibraryXBOX
			Get-LibraryItch
			Get-LibrarySKIF
		}
	}
}