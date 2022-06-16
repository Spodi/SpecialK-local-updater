<# 
	.Synopsis 
	Scans all game folders SKIF also knows about and updates any local Special K DLLs found.
	
	.Description 
    This script scan all game folders SKIF also knows about and replaces any local Special K DLLs found with the ones in Special Ks default install folder.
	You can add the absolute path to local DLLs to the "blacklist" array in "SK_LocalUpdater.json" to exclude it. This can be useful if the game only works with a specific version of Special K.
	You can add the absolute path to local DLLs to the "AdditionalDLLs" array in "SK_LocalUpdater.json" to also update those.
	
	.Notes
	Created by Spodi and Wall_SoGB
	v22.6.10
 #>

[CmdletBinding()]
param (
	[Parameter()][switch]$NoGUI,
	[Parameter()][switch]$Scan
)
	
#region <FUNCTIONS>
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
function Get-GameFolders { 
	[CmdletBinding()]
	param (
		[Parameter()][String[]]$DisabledPlattforms
	)

	# Game paths
	$SteamRegistry	=	'Registry::HKEY_CURRENT_USER\Software\Valve\Steam\'
	$SKIFRegistry	=	'Registry::HKEY_CURRENT_USER\SOFTWARE\Kaldaien\Special K\Games'
	$GOGRegistry	=	'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\GOG.com\Games'
	$EGSRegistry	=	'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Epic Games\EpicGamesLauncher'
	$XBOXRegistry	=	'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\GamingServices\PackageRepository\Root'

	Invoke-Command {	
		If ($DisabledPlattforms -notcontains 'Steam') {
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
								Write-output ([PSCustomObject]@{
										PlatformName = 'Steam'
										id           = $acf.AppState.appid
										path         = (Join-Path (Join-Path $_ '\SteamApps\common\') $acf.AppState.installdir) #don't care about things in other folders, like \SteamApps\music. Non existing paths are filtered out later.
									})
							}
						}
					}
				}
			}
		}
		If ($DisabledPlattforms -notcontains 'GOG') {
			#Get GOG games
			if (Test-Path $GOGRegistry) {
				Write-Verbose 'GOG install found!'

		(Get-Item -Path $GOGRegistry).GetSubKeyNames() | ForEach-Object {
					$GOG = Get-ItemProperty -Path "$GOGRegistry\$_"
					Write-output ([PSCustomObject]@{
							PlatformName = 'GOG'
							id           = $GOG.gameID
							path         = $GOG.InstallDir
						})
				}
			}
		}
		If ($DisabledPlattforms -notcontains 'EGS') {
			#Get EGS games
			if (Test-Path $EGSRegistry) { 
				Write-Verbose 'EGS install found!'

				$EGSlibrary = (Get-ItemProperty -Path $EGSRegistry).AppDataPath
				if (Test-Path "$EGSlibrary\Manifests") {
					Get-ChildItem -File "$EGSlibrary\Manifests" | ForEach-Object {
						$file = $_.FullName
						$EGS = (Get-Content -Path $file -Encoding UTF8) | ConvertFrom-Json
						Write-output ([PSCustomObject]@{
								PlatformName = 'EGS'
								id           = $EGS.InstallationGuid
								path         = $EGS.InstallLocation
							})
					}
				}
			}
		}
		If ($DisabledPlattforms -notcontains 'XBOX') {
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
						Write-output ([PSCustomObject]@{
								PlatformName = 'XBOX'
								id           = $null #
								path         = ($_ + ((Get-Content "$_\.GamingRoot").Substring(5)).replace("`0", '')) # String needs to be cleaned out of null characters.
							})
					}
				}
			}
		}
		If ($DisabledPlattforms -notcontains 'SKIF') {
			#Get custom SKIF games
			if (Test-Path $SKIFRegistry) {
				Write-Verbose 'SKIF install found!'

				(Get-Item -Path $SKIFRegistry).GetSubKeyNames() | ForEach-Object {
					$SKIFCustom = Get-ItemProperty -Path "$SKIFRegistry\$_"
					Write-output ([PSCustomObject]@{
							PlatformName = 'SKIF'
							id           = $SKIFCustom.ID
							path         = $SKIFCustom.InstallDir
						})
				}
			}
		}
	}  | Group-Object 'path' | ForEach-object { ([PSCustomObject]@{Path = $_.Name; Platforms = ($_.Group | Select-object * -ExcludeProperty 'path') } | Add-Member -MemberType ScriptMethod -Name 'ToString' -Value { $this.path.ToString() } -PassThru -Force) } | Where-Object { (Test-Path -LiteralPath $_.Path -PathType 'Container') } | Sort-Object 'path' | Write-Output #remove duplicate and invalid entries and sort them nicely
}
function Find-SkDlls {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)][String]$Path,
		[Parameter(ValueFromPipelineByPropertyName)]$Platforms
	)
	begin {
		$dllsList = ('dxgi.dll', 'd3d11.dll', 'd3d9.dll', 'd3d8.dll', 'ddraw.dll', 'dinput8.dll', 'opengl32.dll')
	}
	process {
		[System.IO.Directory]::EnumerateFiles($Path, '*.dll', 'AllDirectories') | Where-Object { ((Split-Path $_ -Leaf) -in $dllsList) } | Get-Item -ErrorAction 'SilentlyContinue' | Where-Object { ($_.VersionInfo.ProductName -EQ 'Special K') } | Where-Object LinkType -like $null | Add-Member -PassThru Platforms $Platforms | Write-Output
	}
}
function Update-DllList { 
	[CmdletBinding()]
	param (
		[Parameter(Mandatory, ValueFromPipeline)]$dlls
	)
	begin {
		$blacklist = (Get-Content $PSScriptRoot\SK_LU_settings.json | ConvertFrom-Json).Blacklist | Sort-Object -Unique
		$fixedVersions = (Get-Content $PSScriptRoot\SK_LU_fixedVersions.json | ConvertFrom-Json) | Select-Object PlatformName, id
	}
	process {
		$obj = New-Object PSObject
		Add-Member -InputObject $obj -MemberType NoteProperty -Name Name -Value $dlls.Name
		Add-Member -InputObject $obj -MemberType NoteProperty -Name FullName -Value $dlls.FullName
		Add-Member -InputObject $obj -MemberType NoteProperty -Name Directory -Value $dlls.DirectoryName
		Add-Member -InputObject $obj -MemberType NoteProperty -Name InternalName -Value $dlls.VersionInfo.InternalName
		Add-Member -InputObject $obj -MemberType NoteProperty -Name Version -Value $dlls.VersionInfo.ProductVersion
		Add-Member -InputObject $obj -MemberType NoteProperty -Name Bits -Value ($dlls.VersionInfo.InternalName -replace '[^0-9]' , '')
		if ((Join-Path -Path $dlls.DirectoryName -ChildPath $dlls.Name) -in $blacklist) {
			Add-Member -InputObject $obj -MemberType NoteProperty -Name IsChecked -Value $False -TypeName System.Boolean
		}
		elseif (($dlls.Platforms | foreach-object { $_ -in [string[]]$fixedVersions }) -contains $true) {
			Add-Member -InputObject $obj -MemberType NoteProperty -Name IsChecked -Value $False -TypeName System.Boolean
		}
		else {
			Add-Member -InputObject $obj -MemberType NoteProperty -Name IsChecked -Value $True -TypeName System.Boolean
		}
		Write-Output $obj

	}
}
function Register-UpdateTask {
	$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "$PSScriptRoot\SK_LocalUpdater.ps1 -nogui"
	$trigger = New-ScheduledTaskTrigger -Daily -At 5pm
	$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME"
	$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RunOnlyIfNetworkAvailable
	$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal
	try {
		Register-ScheduledTask -TaskName 'Special K Local Updater Task' -InputObject $task -User "$env:USERDOMAIN\$env:USERNAME"
	}
	catch {
		Write-Error -Message $_.Exception.Message
		return
	}
	Write-Host "Task created succesfully"
}
function Show-MessageBox {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]																													[string]	$Message,
		[Parameter(Mandatory = $true)]																													[string]	$Title,
		[Parameter(Mandatory = $false)]	[ValidateSet('OK', 'OKCancel', 'RetryCancel', 'YesNo', 'YesNoCancel', 'AbortRetryIgnore')]						[string]	$Button = 'OK',
		[Parameter(Mandatory = $false)] [ValidateSet('Asterisk', 'Error', 'Exclamation', 'Hand', 'Information', 'None', 'Question', 'Stop', 'Warning')]	[string]	$Icon = 'None'
	)
	begin {
		Add-Type -AssemblyName System.Windows.Forms | Out-Null
		[System.Windows.Forms.Application]::EnableVisualStyles()
	}
	process {
		$button = [System.Windows.Forms.MessageBoxButtons]::$Button
		$icon = [System.Windows.Forms.MessageBoxIcon]::$Icon
	}
	end {
		return [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Button, $Icon)
	}
}
function New-XMLNamespaceManager {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[xml]
		$XmlDocument,
		[string]
		$DefaultNamespacePrefix
	)

	$NsMgr = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $XmlDocument.NameTable

	$DefaultNamespace = $XmlDocument.DocumentElement.GetAttribute('xmlns')
	if ($DefaultNamespace -and $DefaultNamespacePrefix) {
		$NsMgr.AddNamespace($DefaultNamespacePrefix, $DefaultNamespace)
	}

	$XmlDocument.DocumentElement.Attributes | 
	Where-Object { $_.Prefix -eq 'xmlns' } |
	ForEach-Object {
		$NsMgr.AddNamespace($_.LocalName, $_.Value)
	}

	return , $NsMgr # unary comma wraps $NsMgr so it isn't unrolled
}

function ScanAndCache {
	param($AdditionalScanPath)
	$dlls = Get-GameFolders
	$dlls += $AdditionalScanPaths
	$dlls = $dlls | Group-Object path | foreach-object { $_.Group[0] } | Find-SkDlls
	[System.IO.File]::WriteAllLines("$PSScriptRoot\SK_LU_cache.json", ($dlls | select-object FullName, Platforms | ConvertTo-Json -Compress))
	Write-Output $dlls
}
#endregion </FUNCTIONS>


Import-Module -Name (Join-Path $PSScriptRoot 'SpecialK_PSLibrary.psm1') -force

$whitelist = $null
$dllcache = $null
$dlls = $null

$SK_DLLPath = Get-SkPath -ErrorAction 'Stop'

$SKVersions = Get-SkDll | ForEach-Object {
	$obj = New-Object PSObject
	Add-Member -InputObject $obj -MemberType NoteProperty -Name 'Name' -Value $_.Name
	Add-Member -InputObject $obj -MemberType NoteProperty -Name 'Version' -Value $_.VersionInfo.ProductVersion
	Add-Member -InputObject $obj -MemberType NoteProperty -Name 'VersionInternal' -Value $_.VersionInfo.ProductVersionRaw
	Add-Member -InputObject $obj -MemberType NoteProperty -Name 'Bits' -Value ($_.VersionInfo.InternalName -replace '[^0-9]' , '')
	if (($_.Name -eq 'SpecialK64.dll') -or ($_.Name -eq 'SpecialK32.dll')) {	
		$variant = 'Main'
	}
	else {
		$variant = ($_.Name -Replace '^.*?SpecialK[6,3][4,2]-?|\.dll.*$')
	}
	Add-Member -InputObject $obj -MemberType NoteProperty -Name 'Variant' -Value $variant
	Write-Output $obj
	Remove-Variable 'obj', 'variant'
}
$NewestLocal = ($SKVersions | Sort-Object VersionInternal -Descending)[0]
$SKVariants = ($SKVersions | Select-Object Variant -Unique)

if (Test-Path $PSScriptRoot\SK_LU_settings.json) {
	$whitelist = (Get-Content $PSScriptRoot\SK_LU_settings.json | ConvertFrom-Json).AdditionalDLLs | Sort-Object -Unique
	$AdditionalScanPaths = (Get-Content $PSScriptRoot\SK_LU_settings.json | ConvertFrom-Json).AdditionalScanPaths | Sort-Object -Unique
}
else {
	[void](New-Item $PSScriptRoot\SK_LU_settings.json)
	Set-Content $PSScriptRoot\SK_LU_settings.json -Value (@{'Blacklist' = @(); 'AdditionalDLLs' = @(); 'AdditionalScanPaths' = @() } | ConvertTo-Json)
	$whitelist = $null
	$AdditionalScanPaths = $null
}

if (! $Scan) {
	if (Test-Path $PSScriptRoot\SK_LU_cache.json) {
		Write-Host -NoNewline 'Loading cached locations... '
		$dllcache = (Get-Content $PSScriptRoot\SK_LU_cache.json | ConvertFrom-Json)
	}
}	
if ($dllcache) {
	$dlls = $dllcache | ForEach-Object { Get-Item $_.FullName -ErrorAction 'SilentlyContinue' | Add-Member -PassThru Platforms $_.Platforms } | Where-Object { ($_.VersionInfo.ProductName -EQ 'Special K') } | Write-Output
}
else {
	Write-Host -NoNewline 'Scanning game folders for a local SpecialK dlls, this could take a while... '
	$dlls = ScanAndCache $AdditionalScanPaths
}
if ($whitelist) {
	$dlls += $whitelist | Get-Item -ErrorAction 'SilentlyContinue' | Where-Object { ($_.VersionInfo.ProductName -EQ 'Special K') } | Where-Object { ($_.FullName -notin $dlls.FullName) } | Write-Output
}
$instances = $dlls | Sort-Object 'FullName' -Unique | Update-DllList
Write-Host 'Done'

if ($NoGUI) {
	$instances | where-object IsChecked -eq $true | ForEach-Object {
		Write-Host "Copy item `"$(Join-Path -Path $SK_DLLPath -ChildPath $_.InternalName)`" to destination `"$($_.FullName)`""
		Copy-Item -LiteralPath (Join-Path -Path $SK_DLLPath -ChildPath $_.InternalName) -Destination $_.FullName
	}
	exit 0
}


$LightTheme = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme').AppsUseLightTheme

$GUI = [hashtable]::Synchronized(@{})

[string]$XAML = (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'SK_LU_GUI.xml')) -replace 'mc:Ignorable="d"' -replace '^<Win.*', '<Window'


if ($LightTheme) {
	$XAML = $XAML -replace 'BasedOn="{StaticResource DarkTheme}"', 'BasedOn="{StaticResource LightTheme}"'
	$XAML = $XAML -replace 'Style="{StaticResource DarkThemeButton}"', 'Style="{StaticResource LightThemeButton}"'
	$XAML = $XAML -replace '§VersionForeground§', 'Black'
}
else {
	$XAML = $XAML -replace '§VersionForeground§', 'White'
}

#Round corners in win11
if ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuild).CurrentBuild -ge 22000) {
	$XAML = $XAML -replace 'Property="CornerRadius" Value="0"', 'Property="CornerRadius" Value="4"'
}
[xml]$XAML = $XAML


Add-Type -AssemblyName 'PresentationFramework'
$GUI.NsMgr = (New-XMLNamespaceManager $XAML)
$GUI.WPF = [Windows.Markup.XamlReader]::Load( (New-Object System.Xml.XmlNodeReader $XAML) )
$GUI.Nodes = $XAML.SelectNodes("//*[@x:Name]", $GUI.NsMgr) | ForEach-Object {
	@{ $_.Name = $GUI.WPF.FindName($_.Name) }
}
if ($LightTheme) {
	$GUI.WPF.Background = 'white'
	$GUI.WPF.Foreground = 'black'
}


if (Test-Path "$PSScriptRoot\SKIF.ico") {
	$GUI.WPF.Icon = "$PSScriptRoot\SKIF.ico"
}

$GUI.Nodes.VariantsComboBox.ItemsSource = [Array]$SKVariants.Variant
$GUI.Nodes.VariantsComboBox.SelectedItem = 'Main'

$selectedVariant = $SKVersions | where-object Variant -eq $GUI.Nodes.VariantsComboBox.SelectedItem
if ($selectedVariant[0] -and $selectedVariant[1]) {
	$GUI.Nodes.Version.Text = "$($selectedVariant[0].Bits)Bit - v$($selectedVariant[0].Version) | $($selectedVariant[1].Bits)Bit - v$($selectedVariant[1].Version)"
}
elseif ($selectedVariant[0]) {
	$GUI.Nodes.Version.Text = "$($selectedVariant[0].Bits)Bit - v$($selectedVariant[0].Version)"
}
else {
	$GUI.Nodes.Version.Text = "Error"
}


$GUI.Nodes.VersionColumn.ElementStyle.Triggers[1].Value = $NewestLocal.Version

$(if (Get-ScheduledTask -TaskName 'Special K Local Updater Task' -ErrorAction Ignore) {
		$GUI.Nodes.TaskButton.Content = 'Disable Automatic Update'
	}
	else {
		$GUI.Nodes.TaskButton.Content = 'Enable Automatic Update'
	})

$Events = @{}

$Events.ButtonUpdate = {
	$GUI.Nodes.Games.ItemsSource | Where-Object { $_.IsChecked -eq $True } | ForEach-Object {
		try {			
			$usedDll = $SKVersions | Where-Object Bits -Like $_.Bits | Where-Object Variant -EQ $GUI.Nodes.VariantsComboBox.SelectedItem
			$source = Join-Path -Path $SK_DLLPath -ChildPath $usedDll.Name
			if (!(Test-Path -PathType 'Leaf' $source) ) { Throw "No matching $($_.Bits)Bit dll for selected variant found." }
			Write-Host "Copy item `"$($source)`" to destination `"$($_.FullName)`""
			Copy-Item -LiteralPath $source -Destination $_.FullName -ErrorAction 'Stop'
			$_.Version = $usedDll.Version
		}
		catch {
			Write-Error "Failed to update `"$($_.FullName)`"
$_"
		}
		$i++
	}
	$GUI.Nodes.Games.ItemsSource = $null
	$GUI.Nodes.Games.ItemsSource = [Array]$script:instances
}

$Events.ButtonTask = {
	if (Get-ScheduledTask -TaskName 'Special K Local Updater Task' -ErrorAction Ignore) {
		try {
			Unregister-ScheduledTask -TaskName 'Special K Local Updater Task' -Confirm:$false
		}
		catch {
			Write-Error ($_.Exception.Message)
			return
		}
		Write-Host "Task removed succesfully"
		$GUI.Nodes.TaskButton.Content = 'Enable automatic update'
	}
	else {
		Register-UpdateTask
		$GUI.Nodes.TaskButton.Content = 'Disable automatic update'
	}
}

$Events.ButtonScan = {
	Write-Host -NoNewline 'Scanning game folders for a local SpecialK dlls, this could take a while... '
	$dlls = ScanAndCache $AdditionalScanPaths
	if ($whitelist) {
		$dlls += $whitelist | Get-Item -ErrorAction 'SilentlyContinue' | Where-Object { ($_.VersionInfo.ProductName -EQ 'Special K') } | Write-Output
	}
	$script:instances = $dlls | Sort-Object 'FullName' -Unique | Update-DllList
	Write-Host 'Done'
	$GUI.Nodes.Games.ItemsSource = $null
	$GUI.Nodes.Games.ItemsSource = [Array]$script:instances
}


$Events.SelectAll = {
	
	if ($GUI.Nodes.CheckboxSelectAll.IsChecked) {
		$script:instances | ForEach-Object {
			$_.IsChecked = $true
		}
	}
	elseif ($GUI.Nodes.CheckboxSelectAll.IsChecked = $null) {
	}
	else {
		$script:instances | ForEach-Object {
			$_.IsChecked = $false
		}
		$GUI.Nodes.CheckboxSelectAll.IsChecked = $false
	}
	$GUI.Nodes.Games.ItemsSource = $null
	$GUI.Nodes.Games.ItemsSource = [Array]$script:instances
}

$Events.VariantChange = {
	$selectedVariant = $SKVersions | where-object Variant -eq $GUI.Nodes.VariantsComboBox.SelectedItem
	if ($selectedVariant[0] -and $selectedVariant[1]) {
		$GUI.Nodes.Version.Text = "$($selectedVariant[0].Bits)Bit - v$($selectedVariant[0].Version) | $($selectedVariant[1].Bits)Bit - v$($selectedVariant[1].Version)"
	}
	elseif ($selectedVariant[0]) {
		$GUI.Nodes.Version.Text = "$($selectedVariant[0].Bits)Bit - v$($selectedVariant[0].Version)"
	}
	else {
		$GUI.Nodes.Version.Text = "Error"
	}
}


$Events.ButtonDelete = {
	if ((Show-MessageBox -Message 'Are you sure you want to delete selected items?
This can not be undone!' -Title 'Confirm deletion' -Button 'YesNo' -Icon 'Question') -EQ 'Yes') {
		$GUI.Nodes.Games.ItemsSource | Where-Object 'IsChecked' -eq $True | ForEach-Object {
			Remove-Item $_.FullName
			[array]$script:instances[[array]::IndexOf($GUI.Nodes.Games.ItemsSource,$_)] = $null
		}
		$script:instances = $script:instances | Where-Object { $_ } #clear $null
		$GUI.Nodes.Games.ItemsSource = $null
		$GUI.Nodes.Games.ItemsSource = [Array]$script:instances
	}
}


$GUI.Nodes.UpdateButton.Add_Click($Events.ButtonUpdate)
$GUI.Nodes.ScanButton.Add_Click($Events.ButtonScan)
$GUI.Nodes.TaskButton.Add_Click($Events.ButtonTask)
$GUI.Nodes.CheckboxSelectAll.Add_Click($Events.SelectAll)
$GUI.Nodes.VariantsComboBox.Add_SelectionChanged($Events.VariantChange)
$GUI.Nodes.DeleteButton.Add_Click($Events.ButtonDelete)

$GUI.WPF.Add_Loaded({
		$GUI.Nodes.Games.ItemsSource = [Array]$script:instances
	})

#$GUI.Nodes.VersionColumn.ElementStyle.Triggers | out-host #

#$GUI.Nodes.VariantsComboBox | Get-Member -Type Event | Format-Wide -Column  4 -Property Name 

$UpdateRunspace = [runspacefactory]::CreateRunspace()
$UpdateRunspace.ApartmentState = 'STA'
$UpdateRunspace.ThreadOptions = 'ReuseThread'
$UpdateRunspace.Open()
$UpdateRunspace.SessionStateProxy.SetVariable('GUI', $GUI)
$UpdateRunspace.SessionStateProxy.SetVariable('SKVersions', $SKVersions)
$UpdateRunspace.SessionStateProxy.SetVariable('NewestLocal', $NewestLocal)
$UpdateRunspace.SessionStateProxy.SetVariable('GUI.Nodes.VersionColumn.ElementStyle.Triggers', $GUI.Nodes.VersionColumn.ElementStyle.Triggers)
$UpdatePowershell = [powershell]::Create()
$UpdatePowershell.Runspace = $UpdateRunspace
[void]$UpdatePowershell.AddScript({
		$GUI.WPF.Dispatcher.Invoke([action] {
				$GUI.Nodes.Update.Text = 'Checking SKs Discord branch for updates...'
			})
		$i = 0
		while ($i -le 3) {
			$NewestRemote = ((ConvertFrom-Json (Invoke-WebRequest 'https://sk-data.special-k.info/repository.json' -ErrorAction 'SilentlyContinue').Content).Main.Versions | Where-Object Branches -EQ 'Discord')[0].Name
			if ($NewestRemote) {
				break
			}
			else {
				$i++
			}
		}
		
		if (!$NewestRemote) {
			$GUI.WPF.Dispatcher.Invoke([action] {
					$GUI.Nodes.Update.Text = 'Update check failed.'
					$GUI.Nodes.Update.Foreground = 'Red'
				})
			exit 1
		}
		$GUI.WPF.Dispatcher.Invoke([action] {
				$GUI.Nodes.VersionColumn.ElementStyle.Triggers[0].Value = $NewestRemote #Why you no work?
			})

		if ($NewestRemote -gt $NewestLocal.VersionInternal) {
			$GUI.WPF.Dispatcher.Invoke([action] {
					$GUI.Nodes.Update.Text = "There's an update available! ($NewestRemote)"
					$GUI.Nodes.Update.Foreground = 'Green'
				})
		}
		else {
			$GUI.WPF.Dispatcher.Invoke([action] { 
					$GUI.Nodes.Update.Text = ""
				})
		}
	})

if (! $instances) {
	Show-MessageBox -Message 'No SpecialK installs found' -Title 'Error' -Button OK -Icon Warning
	exit 1
}
$UpdateHandle = $UpdatePowershell.BeginInvoke()

[void]$GUI.WPF.ShowDialog() #show window

$UpdatePowershell.EndInvoke($UpdateHandle) | out-Host
$UpdatePowershell.Dispose()
$UpdateRunspace.Close()
exit 0
