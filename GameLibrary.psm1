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
		if (Test-Path (Join-Path $Games.Path steam_appid.txt)) {
			$id = Get-Content -TotalCount 1 -LiteralPath (Join-Path $Games.Path steam_appid.txt)
			if ($id) {
				$obj = [PSCustomObject]@{Name = "Steam"; ID = $id }
				if (($Games.PlatformInfo | foreach-object { $_ -in [string[]]$obj }) -notcontains $true) {
					[Array]$Games.PlatformInfo += $obj
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
		$steamlib = $steamVdf.libraryfolders | Get-Member -MemberType NoteProperty, Property | Select-Object -ExpandProperty Name | ForEach-Object { #this is for getting the nested objects name
			if ($null -ne $steamVdf.libraryfolders.$_.path) {
				$steamVdf.libraryfolders.$_.path
			}
		}
		($steamlib -replace '\\\\', '\') | ForEach-Object {
			if (Test-Path $_) {
				ForEach ($file in (Get-ChildItem "$_\SteamApps\*.acf") ) {
					$acf = ConvertFrom-VDF (Get-Content $file -Encoding UTF8)
					if ($acf.AppState.name) {
						$steamgamepath = Join-Path (Join-Path $_ '\SteamApps\common\') $acf.AppState.installdir
						if (Test-Path $steamgamepath) {
							Write-output ([PSCustomObject]@{
									Name         = $acf.AppState.name
									PlatformInfo = [PSCustomObject]@{
										Name = 'Steam'
										ID   = $acf.AppState.appid
									}
									Path         = $steamgamepath
								})
						}
					}
				}
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
			if (Test-Path $GOG.path) {
				Write-output ([PSCustomObject]@{
						Name         = $GOG.gameName
						PlatformInfo = [PSCustomObject]@{
							Name = 'GOG'
							ID   = $GOG.gameID
						}
						Path         = $GOG.path
					})
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
					Write-output ([PSCustomObject]@{
							Name         = $EGS.DisplayName
							PlatformInfo = [PSCustomObject]@{
								Name = 'EGS'
								ID   = $EGS.InstallationGuid
							}
							Path         = $EGS.InstallLocation
						})
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
		$xboxDrives = (Get-ChildItem -Path "$XBOXRegistry\*\*") | ForEach-Object {
			# Gets registered drive letter
			Write-output (($_ | Get-ItemProperty).Root).Replace('\\?\', '').Substring(0, 3) 	
		}
		# Gets install folders
($xboxDrives | Sort-Object -Unique) | ForEach-Object {
			if (Test-Path $_) {
				$XBOXGamePath = ($_ + ((Get-Content "$_\.GamingRoot").Substring(5)).replace("`0", '')) # String needs to be cleaned out of null characters.
				if (Test-Path $XBOXGamePath) {
					Write-output ([PSCustomObject]@{
							Name         = $null #TODO: get Name here
							PlatformInfo = [PSCustomObject]@{
								Name = 'XBOX'
								ID   = $null #TODO: get AppID here
							}
							Path         = $XBOXGamePath
						})
				}
			}
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
				foreach ($candidate in $_.verdict.candidates) {
					$itchGamePath = (Split-Path (Join-Path $_.verdict.basePath $candidate.path))
					if (Test-Path $itchGamePath) {
					([PSCustomObject]@{
							Name         = ($games | Where-Object 'id' -EQ $_.game_id).title
							PlatformInfo = [PSCustomObject]@{
								Name = 'itch'
								ID   = $_.game_id
							}
							Path         = $itchGamePath
						})
					}
				}
			}
		}
		else {
			Write-Warning "itch install found, but no `"SQlite3.exe`" is present in `"$PSScriptRoot`".
Please put the SQLite command line tool in `"$PSScriptRoot`" to add support for itch."
		}
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
				Write-output ([PSCustomObject]@{
						Name         = $SKIFCustom.Name
						PlatformInfo = [PSCustomObject]@{
							Name = 'SKIF'
							ID   = $SKIFCustom.ID
						}
						Path         = $SKIFCustom.InstallDir
					})
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
			([PSCustomObject]@{Name = ($_.Group.Name | Sort-Object -Unique); PlatformInfo = ($_.Group.PlatformInfo  | Sort-Object { [String[]]$_ } -Unique); Path = $_.Name })
		}
	}

}