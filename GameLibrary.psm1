<#
.NOTES
Spodi's Powershell Game Library Module v22.12.18
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
Function ConvertFrom-VDF {
	<# 
 .Synopsis 
     Reads a Valve Data File (VDF) formatted string into a custom object.
 .Description 
     The ConvertFrom-VDF cmdlet converts a VDF-formatted string to a custom object (PSCustomObject) that has a property for each field in the VDF string. VDF is used as a textual data format for Valve software applications, such as Steam.
 .Parameter InputObject
     Specifies the VDF strings to convert to PSObjects. Enter a variable that contains the string, or type a command or expression that gets the string. 
 .Example 
     $vdf = ConvertFrom-VDF -InputObject (Get-Content ".\SharedConfig.vdf")
     Description 
     ----------- 
     Gets the content of a VDF file named "SharedConfig.vdf" in the current location and converts it to a PSObject named $vdf
 .Inputs 
     System.String
 .Outputs 
     PSCustomObject
 .NOTES
     Stol... er, borrowed from:
     https://github.com/ChiefIntegrator/Steam-GetOnTop/blob/master/Modules/SteamTools/SteamTools.psm1
 #>
	param
	(
		[Parameter(Position = 0, Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[System.String[]]$InputObject
	)
	process {
		$root = New-Object -TypeName PSObject
		$chain = [ordered]@{}
		$depth = 0
		$parent = $root
		$element = $null
		
		ForEach ($line in $InputObject) {
			$quotedElements = (Select-String -Pattern '(?<=")([^\"\t\s]+\s?)+(?=")' -InputObject $line -AllMatches).Matches
    
			if ($quotedElements.Count -eq 1) {
				# Create a new (sub) object
				$element = New-Object -TypeName PSObject
				Add-Member -InputObject $parent -MemberType NoteProperty -Name $quotedElements[0].Value -Value $element
			}
			elseif ($quotedElements.Count -eq 2) {
				# Create a new String hash
				Add-Member -InputObject $element -MemberType NoteProperty -Name $quotedElements[0].Value -Value $quotedElements[1].Value
			}
			elseif ($line -match '{') {
				$chain.Add($depth, $element)
				$depth++
				$parent = $chain.($depth - 1) # AKA $element
                
			}
			elseif ($line -match '}') {
				$depth--
				$parent = $chain.($depth - 1)
				$element = $parent
				$chain.Remove($depth)
			}
			else {
				# Comments etc
			}
		}

		return $root
	}
    
}

function Add-SteamAppIDText {
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline)][PSCustomObject]$Games
	)
	process {
		if ($Games.Path) {
			if ($Games.Launch.Executable) {
				
				$path = $Games.Launch.Executable | foreach-object {
					Join-Path (split-path (join-path $games.path $_)) steam_appid.txt
				}
			}
			else {
				$path = Join-Path $Games.Path steam_appid.txt
			}
		}
		if ($path) {
			$path | ForEach-Object {
				if (Test-Path $_) {
					$id = Get-Content -TotalCount 1 -LiteralPath $_
					if ($id) {
						$obj = [PSCustomObject]@{Name = "Steam"; ID = [String]$id }
						if (($Games.PlatformInfo | foreach-object { $_ -in [string[]]$obj }) -notcontains $true) {
							[Array]$Games.PlatformInfo += $obj
						}
					}
				}
			}
		}
		Write-Output $Games
	}
}

function Get-LibrarySteam {
	$SteamRegistry	=	'Registry::HKEY_CURRENT_USER\Software\Valve\Steam\'
	#get Steam games
	if (Test-Path $SteamRegistry) {
		Write-Verbose 'Steam install found!'

		$steamPath = "$((Get-ItemProperty $SteamRegistry).SteamPath)".Replace('/', '\')

		# Old: \steamapps\libraryfolders.vdf
		# New:    \config\libraryfolders.vdf

		If (Test-Path "$($steamPath)\config\libraryfolders.vdf") {
			$steamVdf = ConvertFrom-VDF (Get-Content "$($steamPath)\config\libraryfolders.vdf" -Encoding UTF8)
		}
		else {
			$steamVdf = ConvertFrom-VDF (Get-Content "$($steamPath)\steamapps\libraryfolders.vdf" -Encoding UTF8)
		}

		#what even is this monstrosity? :D
		$steamlib = ($steamVdf.libraryfolders | Convert-PSObjectToHashtable).GetEnumerator() | ForEach-Object { #god, .GetEnumerator() makes it so much easier, than using get-member
			if ($null -ne $_.value.path) {
				$_.value.path
			}
		}
		$steamapps = ($steamlib -replace '\\\\', '\') | ForEach-Object {
			if (Test-Path $_) {
				ForEach ($file in (Get-ChildItem "$_\SteamApps\*.acf") ) {
					$acf = ConvertFrom-VDF (Get-Content $file -Encoding UTF8)
					 
						
					if ($acf.AppState.name) {
						
						#if (Test-Path $steamgamepath) {
						Write-Output ([PSCustomObject]@{
								Name            = $acf.AppState.name
								ID              = [String]$acf.AppState.appid
								LibPath         = $_
								Path            = $acf.AppState.installdir
								InstalledDepots = ($acf.AppState.InstalledDepots | Convert-PSObjectToHashtable).keys
								Branch          = invoke-command { if ($acf.AppState.MountedConfig.BetaKey) { $acf.AppState.MountedConfig.BetaKey } else { $null } }
							})
						#}


					}
				}
			}
		}
 
		if (Test-Path './vdfparse.exe' -PathType 'Leaf') {
			$appinfo = (./vdfparse appinfo $steamapps.ID | ConvertFrom-Json -ErrorAction SilentlyContinue)
			if ($LASTEXITCODE -or !$appinfo) {
				Write-Warning "Steam install found and `"VDFparse.exe`" found, but it encountered an error.
Only basic info can be retrieved."	
			}
		}
		else {
			Write-Warning "Steam install found, but no `"VDFparse.exe`" is present in `"$PSScriptRoot`".
Only basic info can be retrieved."
		}

		if ($appinfo) {

			$appinfo.datasets | foreach-object {
				if ($_.Data.appinfo.depots) {
					$_.Data.appinfo.depots = $_.Data.appinfo.depots | Convert-PSObjectToHashtable
					$_.Data.appinfo.depots.GetEnumerator() | ForEach-Object { 
						if ($_.Value.Manifests) {
							$_.Value.Manifests = $_.Value.Manifests | Convert-PSObjectToHashtable
						}
					}
				}
				if ($_.Data.appinfo.config.launch) {
					$_.Data.appinfo.config.launch = $_.Data.appinfo.config.launch | Convert-PSObjectToHashtable
						
				}

			}
		}

		foreach ($game in $steamapps) {
			############
			
			if ($appinfo) {
				$LibPath = $game.LibPath
				$Path = $game.Path
				$type = ($appinfo.datasets | where-object id -eq $game.id).Data.appinfo.common.type
			
				switch ( $type ) {
					'Music' { $steamgamepath = Join-Path (Join-Path $LibPath '\SteamApps\music\') $Path }
					default { $steamgamepath = Join-Path (Join-Path $LibPath '\SteamApps\common\') $Path }
				}
				if ((Test-Path $steamgamepath)) {
					$gameobject = [PSCustomObject]@{
						Name         = $game.Name
						Type         = $type
						PlatformInfo = [PSCustomObject]@{
							Name = 'Steam'
							ID   = [String]$game.ID
						}
						Path         = "$steamgamepath\"
					}

					if ( ($appinfo.datasets | Where-Object id -eq $game.ID).Data.appinfo.config.launch ) {
						$branch = $game.Branch
						$launch = ($appinfo.datasets | Where-Object id -eq $game.ID).Data.appinfo.config.launch.GetEnumerator() | ForEach-Object {
							if (  $_.value.executable ) {
								if (($branch -eq $_.value.config.betakey) -or !$_.value.config.betakey) {

									if ( ($_.value.config.oslist -eq 'Windows') -or (!$_.value.config.oslist) ) {
								
										if ( !$_.value.config.osarch -or ( ($_.value.config.osarch -eq '64') -and ([Environment]::Is64BitOperatingSystem) ) -or (($_.value.config.osarch -eq '32') -and (![Environment]::Is64BitOperatingSystem))) {
											$temp = [PSCustomObject]@{ Executable = $_.value.executable }
		
											if	($_.value.arguments)	{ $temp | Add-Member Arguments	$_.value.arguments }
											if	($_.value.workingdir)	{ $temp | Add-Member WorkingDir	$_.value.workingdir }
											if	($_.value.config.osarch)	{ $temp | Add-Member Arch	$_.value.config.osarch }
											if	($_.value.description)	{ $temp | Add-Member Description	$_.value.description }
											$temp
										}
									}
								}
							}
						}
						if ($launch) { $gameobject | Add-Member Launch $launch }
					}
				}
				Write-Output $gameobject
						
			}
		}
	}

}


function Get-LibraryGOG {
	$GOGRegistry	=	'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\GOG.com\Games'
	#Get GOG games
	if (Test-Path $GOGRegistry) {
		Write-Verbose 'GOG install found!'

			(Get-Item -Path $GOGRegistry).GetSubKeyNames() | ForEach-Object {
			$GOG = Get-ItemProperty -Path "$GOGRegistry\$_"
			if (!$GOG.dependsOn) {
				if (Test-Path $GOG.path) {
					$gameobject = [PSCustomObject]@{
						Name         = $GOG.gameName
						Type         = $null
						PlatformInfo = [PSCustomObject]@{
							Name = 'GOG'
							ID   = [String]$GOG.gameID
						}
						Path         = "$($GOG.path)\"
					}
				
					if ( $GOG.launchCommand ) {
						$launch = [PSCustomObject]@{ Executable =	$GOG.launchCommand.Replace($gameobject.path, '') -replace (' $', '') }
						if ($GOG.launchParam) { $launch | Add-Member Arguments  $GOG.launchParam }
						if ($GOG.workingDir.Replace($GOG.path, ''))	{ $launch | Add-Member WorkingDir	$GOG.workingDir.Replace($gameobject.path, '') }
					}
					if ($launch) { $gameobject | Add-Member Launch $launch }
					Write-Output $gameobject
				}
				
						
			}
		}
	}
}
function Get-LibraryEGS {
	$EGSRegistry	=	'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Epic Games\EpicGamesLauncher'
	#Get EGS games
	if (Test-Path $EGSRegistry) { 
		Write-Verbose 'EGS install found!'

		$EGSlibrary = (Get-ItemProperty -Path $EGSRegistry).AppDataPath
		if (Test-Path "$EGSlibrary\Manifests") {
			Get-ChildItem -File "$EGSlibrary\Manifests" | ForEach-Object {
				$file = $_.FullName
				$EGS = (Get-Content -Path $file -Encoding UTF8) | ConvertFrom-Json
				if (Test-Path $EGS.InstallLocation) {
					if ($EGS.AppCategories -Contains 'games') { $type = 'Game' } elseif ($EGS.AppCategories -Contains 'software') { $type = 'Application' }
					$gameobject = [PSCustomObject]@{
						Name         = $EGS.DisplayName
						Type         = $type
						PlatformInfo = [PSCustomObject]@{
							Name = 'EGS'
							ID   = [String]$EGS.InstallationGuid
						}
						Path         = "$($EGS.InstallLocation)\"
					}
					if ( $EGS.LaunchExecutable ) {
						$launch = [PSCustomObject]@{ Executable =	$EGS.LaunchExecutable }
						if ($EGS.LaunchCommand) { $launch | Add-Member Arguments  $EGS.LaunchCommand }
					}
					if ($launch) { $gameobject | Add-Member Launch $launch }
					Write-Output $gameobject
				}
				
			}
		}
	}
}
function Get-LibraryXBOX {
	$XBOXRegistry	=	'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\GamingServices\PackageRepository\Root'
	#Get XBOX games
	if (Test-Path $XBOXRegistry) {
				
		Write-Verbose 'XBOX install found!'
		$xbox = @()
		$xbox = (Get-ChildItem -Path "$XBOXRegistry\*\*") | ForEach-Object {
			$ImagePath = (($_ | Get-ItemProperty).Root).Replace('\\?\', '')
			$appxmanifest = join-Path $ImagePath '/appxmanifest.xml'

			if (Test-Path $appxmanifest -PathType 'Leaf') {
				[xml]$xml = get-content (join-Path $ImagePath '/appxmanifest.xml') -Encoding 'Utf8'
				Write-Output @{
					Drive = $ImagePath.Substring(0, 3)
					ID    = $xml.Package.Identity.Name
					Name  = $xml.Package.Properties.DisplayName
				}
			}
		}
		# Gets install folders
		$xboxDrives = ($xbox.Drive | Sort-Object -Unique) | ForEach-Object {
			if (Test-Path (join-path $_ '\.GamingRoot') -PathType 'Leaf') {
				Write-Output @{
					Drive = $_
					Root  = join-Path $_ (((Get-Content "$_\.GamingRoot" -Encoding 'Unicode').Substring(4)).replace("`0", '')) # String needs to be cleaned out of null characters.
				}
			}
		}
		$xbox | ForEach-Object {
			$_.add('Path', ( Join-Path ($xboxDrives | Where-Object Drive -EQ $_.Drive).Root "$($_.Name -replace ('\\|\/|:|\*|\?|"|<|>|\|','-'))\Content\"))
			
			if (Test-Path $_.Path) {

				$gameobject = ([PSCustomObject]@{
						Name         = $_.Name
						Type         = $null
						PlatformInfo = [PSCustomObject]@{
							Name = 'XBOX'
							ID   = [String]$_.id 
						}
						Path         = $_.Path
					})
			}
			$manifest = [xml](Get-Content (join-Path $_.Path 'appxmanifest.xml'))
			if (($manifest.Package.Applications.Application.Attributes | Where-Object Name -EQ Executable).Value) {
				$launch = [PSCustomObject]@{ Executable =	($manifest.Package.Applications.Application.Attributes | Where-Object Name -EQ Executable).Value }
			}
			if ($launch) { $gameobject | Add-Member Launch $launch }
			Write-Output $gameobject
		}
	}
}
function Get-LibraryItch {
	$itchDatabase	=	Join-path $env:APPDATA '/itch/db/butler.db'
	if (Test-Path $itchDatabase -PathType 'Leaf') {
		Write-Verbose 'itch install found!'
		if (Test-Path (Join-Path $PSScriptRoot 'SQlite3.exe') -PathType 'Leaf') {
			$games = (./sqlite3.exe -json $itchDatabase "SELECT * FROM games;" | ConvertFrom-JSON)
			$database = (./sqlite3.exe -json $itchDatabase "SELECT * FROM caves;" | ConvertFrom-JSON) | ForEach-Object {
				$_.verdict = $_.verdict | ConvertFrom-JSON
				$_
			}
			$database | ForEach-Object {
				if (Test-Path $_.verdict.basePath) {
					$gameobject = ([PSCustomObject]@{
							Name         = ($games | Where-Object 'id' -EQ $_.game_id).title
							Type         = ($games | Where-Object 'id' -EQ $_.game_id).classification
							PlatformInfo = [PSCustomObject]@{
								Name = 'itch'
								ID   = [String]$_.game_id
							}
							Path         = "$($_.verdict.basePath)\"
						})
				
					$launch = $_.verdict.candidates | Where-Object 'flavor' -EQ 'Windows' | ForEach-Object {
						[PSCustomObject]@{
							Executable = $_.path
							Arch       = $_.arch
						}
					}
					if ($launch) { $gameobject | Add-Member Launch $launch }
				}
				Write-Output $gameobject
			}
		}
	}
	else {
		Write-Warning "itch install found, but no `"SQlite3.exe`" is present in `"$PSScriptRoot`".
Please put the SQLite command line tool in `"$PSScriptRoot`" to add support for itch."
	}
}
function Get-LibrarySKIF {
	$SKIFRegistry	=	'Registry::HKEY_CURRENT_USER\SOFTWARE\Kaldaien\Special K\Games'
	#Get custom SKIF games
	if (Test-Path $SKIFRegistry) {
		Write-Verbose 'SKIF install found!'

	(Get-Item -Path $SKIFRegistry).GetSubKeyNames() | ForEach-Object {
			$SKIFCustom = Get-ItemProperty -Path "$SKIFRegistry\$_"
			if (Test-Path $SKIFCustom.InstallDir) {
				$gameobject = ([PSCustomObject]@{
						Name         = $SKIFCustom.Name
						PlatformInfo = [PSCustomObject]@{
							Name = 'SKIF'
							ID   = [String]$SKIFCustom.ID
						}
						Path         = "$($SKIFCustom.InstallDir)\"
					})
				if ( $SKIFCustom.ExeFileName ) {
					$launch = [PSCustomObject]@{ Executable =	$SKIFCustom.ExeFileName }
					if ($SKIFCustom.LaunchOptions) { $launch | Add-Member Arguments  $SKIFCustom.LaunchOptions }
				}
				if ($launch) { $gameobject | Add-Member Launch $launch }
				Write-output $gameobject
			}
			
		}
	}
}

function Get-GameLibraries { 
	[CmdletBinding()]
	param (
		[Parameter()][String[]]$Platforms
	)
	if ($null -ne $Platforms) {
		switch ($Platforms) {
			'Steam'	{ Get-LibrarySteam | Add-SteamAppIDText }
			'GOG'	{ Get-LibraryGOG | Add-SteamAppIDText }
			'EGS'	{ Get-LibraryEGS | Add-SteamAppIDText }
			'XBOX'	{ Get-LibraryXBOX | Add-SteamAppIDText }
			'itch'	{ Get-LibraryItch | Add-SteamAppIDText }
			'SKIF'	{ Get-LibrarySKIF | Add-SteamAppIDText }
			default { Write-Warning "Unknown Plattform: $_" }
		} 
	}
	else {
		Get-LibrarySteam | Add-SteamAppIDText
		Get-LibraryGOG | Add-SteamAppIDText
		Get-LibraryEGS | Add-SteamAppIDText
		Get-LibraryXBOX | Add-SteamAppIDText
		Get-LibraryItch | Add-SteamAppIDText
		Get-LibrarySKIF | Add-SteamAppIDText
	}
}

function Group-GameLibraries {
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline)][PSCustomObject[]]$Libraries
	)
	begin {
		#[System.Collections.ArrayList]$Libraries_new = @()
		[array]$Libraries_new = @()
	}
	process {
		#[void]$Libraries_new.add($Libraries)
		$Libraries_new += $Libraries
	}
	end {
		$Libraries_new | Group-Object 'Path' | ForEach-object {
			([PSCustomObject]@{
				Name         = $_.Group.Name | Sort-Object -Unique
				Type         = $_.Group.Type | Sort-Object -Unique
				PlatformInfo = $_.Group.PlatformInfo  | Sort-Object { [String[]]$_ } -Unique
				Path         = $_.Name
				Launch       = $_.Group.Launch | Sort-Object { [String[]]$_ } -Unique
			})
		}
	}

}