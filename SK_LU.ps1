<# 
	.Synopsis 
	Scans all game folders SKIF also knows about and updates any local Special K DLLs found.
	
	.Description 
    This script scan all game folders SKIF also knows about and replaces any local Special K DLLs found with the ones in Special Ks default install folder.
	You can add the absolute path to local DLLs to the "blacklist" array in "SK_LocalUpdater.json" to exclude it. This can be useful if the game only works with a specific version of Special K.
	You can add the absolute path to local DLLs to the "AdditionalDLLs" array in "SK_LocalUpdater.json" to also update those.
	
	.Notes
	Created by Spodi and Wall_SoGB
	v24.04.05
 #>

[CmdletBinding()]
param (
	[Parameter()][switch]$NoGUI,
	[Parameter()][switch]$Scan,
	[Parameter()][string]$WorkingDir
)

#$WorkingDir | out-Host
#[string](get-location) | out-host

Import-Module -Name (Join-Path $PSScriptRoot 'SpecialK_PSLibrary.psm1') -Function 'Get-SkPath', 'Get-SkDll' -Force
Import-Module -Name (Join-Path $PSScriptRoot 'GameLibrary.psm1') -Function 'Get-GameLibraries' -Force

#region <FUNCTIONS>

function Find-SkDlls {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory, ValueFromPipelineByPropertyName, ValueFromPipeline)][String]$Path,
		[Parameter(ValueFromPipelineByPropertyName)]$Platform,
		[Parameter(ValueFromPipelineByPropertyName)]$Recurse
	)
	begin {
		$dllsList = ('dxgi.dll', 'd3d11.dll', 'd3d9.dll', 'd3d8.dll', 'ddraw.dll', 'dinput8.dll', 'opengl32.dll')
	}
	process {
		Invoke-Command {
			if ($Recurse) {
				[System.IO.Directory]::EnumerateFiles($Path, '*.dll', 'AllDirectories') | Write-Output
			}
			else {
				[System.IO.Directory]::EnumerateFiles($Path, '*.dll') | Write-Output
			}
		} | Where-Object { ((Split-Path $_ -Leaf) -in $dllsList) } | Get-Item -ErrorAction 'SilentlyContinue' | Where-Object { ($_.VersionInfo.ProductName -EQ 'Special K') } | Where-Object LinkType -Like $null | Add-Member -PassThru Platform $Platform | Write-Output
	}
}
function Update-DllList { 
	[CmdletBinding()]
	param (
		[Parameter(Mandatory, ValueFromPipeline)]$dlls
	)
	begin {
		$blacklist = (Get-Content $PSScriptRoot\SK_LU_settings.json | ConvertFrom-Json).Blacklist | Sort-Object -Unique
		$fixedVersions = (Get-Content $PSScriptRoot\SK_LU_fixedVersions.json | ConvertFrom-Json)
	}
	process {
		if ($dlls.Name) {
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
			elseif (($dlls.Platform | ForEach-Object { $_ -in [string[]]$fixedVersions.Platform }) -contains $true) {
				Add-Member -InputObject $obj -MemberType NoteProperty -Name IsChecked -Value $False -TypeName System.Boolean
			}
			else {
				Add-Member -InputObject $obj -MemberType NoteProperty -Name IsChecked -Value $True -TypeName System.Boolean
			}
			Write-Output $obj
		}

	}
}
function Register-UpdateTask {
	$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "`"$PSCommandPath`" -nogui"
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
	Write-Host 'Task created succesfully'
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
	[System.Collections.ArrayList]$gamepaths = @()
	Write-Host -NoNewline 'Searching for registered games... '
	$listTime = Measure-Command {
		$gamelist = Get-GameLibraries | Where-Object { ($_.Type -eq 'Game') -or ($_.Type -eq 'Undefined') }
	}
	Write-Host "Took $($listTime.TotalSeconds) Seconds."
	foreach ($entry in $gamelist) {
		if ($entry.launch.executable) {
			foreach ($executable in $entry.launch.executable) {
				$path = Split-Path (Join-Path $entry.path $executable)

				if (Test-Path $path -PathType Container) {
					[void]$gamepaths.add(
						[PSCustomObject]@{
							Platform = $entry.Platform
							Path     = "$($path)\"
						}
					)
				}
				if (($path -match 'Launcher') -and ((Split-Path $path) -notmatch 'Launcher')) {
					$path = (Split-Path $path)
				}
				
			}
		}
		if ($entry.path) {
			if (Test-Path $entry.path -PathType Container) {
				[void]$gamepaths.add(
					[PSCustomObject]@{
						Platform = $entry.Platform
						Path     = $entry.path
					}
				)
			}
		}
	}

	$knownunrealsub = @('Binaries\Win64', 'Binaries\Win32', 'bin\x64', 'bin\x86')
	$knownsub = @('x64', 'x86', 'bin', 'binaries', 'win32', 'win64')

	$unrealsubreg = $knownunrealsub -replace '$', '\' -replace '(\\|\^|\$|\.|\||\?|\*|\+|\(|\)|\[\{)', '\$1' -join '$|'

	foreach ($path in $gamepaths.Clone()) {
		
		$exelist = [System.IO.Directory]::EnumerateDirectories($Path.path)
		foreach ($exe in $exelist) {

			if ($exe -notmatch 'Engine$') {
				foreach ($appendix in $knownunrealsub) {
					$finalpath = Join-Path $path.path $appendix
					if (Test-Path $finalpath -PathType Container) {
						[void]$gamepaths.add(
							[PSCustomObject]@{
								Platform = $entry.Platform
								Path     = "$($finalpath)\"
							}
						)
					}
				}
			}

		}
		
		if ($path.path -notmatch $unrealsubreg) {
			foreach ($appendix in $knownsub) {
				$finalpath = Join-Path $path.path $appendix
				if (Test-Path $finalpath -PathType Container) {
					[void]$gamepaths.add(
						[PSCustomObject]@{
							Platform = $entry.Platform
							Path     = "$($finalpath)\"
						}
					)
				}
			}

		}
	
		ForEach ($path in $AdditionalScanPaths) {
			[void]$gamepaths.add(
				[PSCustomObject]@{
					recurse = $true
					Path    = $path
				}	
			)
		}
	}



	$dlls = $gamepaths.ToArray() | Group-Object path, recurse | ForEach-Object { $_.Group[0] }
	Write-Host -NoNewline "Scanning $($dlls.count) registered game folders... "
	$enumTime = Measure-Command {
		$dlls = $dlls | Find-SkDlls
	}
	Write-Host "Took $($enumTime.TotalSeconds) Seconds."
	$JSON = $dlls | Select-Object FullName, Platform | ConvertTo-Json -Compress
	if (!$JSON) {
		$JSON = ' '
	}
	[System.IO.File]::WriteAllLines("$PSScriptRoot\SK_LU_cache.json", $JSON)
	Write-Output $dlls
		
}
#endregion </FUNCTIONS>


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
		$cacheTime = Measure-Command {
			$dllcache = (Get-Content $PSScriptRoot\SK_LU_cache.json | ConvertFrom-Json)
		}
		Write-Host "Took $($cacheTime.TotalSeconds) Seconds."
	}
}	
if ($dllcache) {
	$dlls = $dllcache | ForEach-Object { Get-Item $_.FullName -ErrorAction 'SilentlyContinue' | Add-Member -PassThru Platform $_.Platform } | Where-Object { ($_.VersionInfo.ProductName -EQ 'Special K') } | Write-Output
}
else {
	#Write-Host -NoNewline 'Scanning game folders for a local SpecialK dlls, this could take a while... '
	$dlls = ScanAndCache $AdditionalScanPaths
}
if ($whitelist) {
	[Array]$dlls += $whitelist | Get-Item -ErrorAction 'SilentlyContinue' | Where-Object { ($_.VersionInfo.ProductName -EQ 'Special K') } | Where-Object { ($_.FullName -notin $dlls.FullName) } | Write-Output
}
$instances = $dlls | Sort-Object 'FullName' -Unique | Update-DllList
Write-Host 'Done'

if ($NoGUI) {
	$instances | Where-Object IsChecked -EQ $true | ForEach-Object {
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
$GUI.Nodes = $XAML.SelectNodes('//*[@x:Name]', $GUI.NsMgr) | ForEach-Object {
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
if ([Array]$SKVariants.Variant -Contains 'Main') {
	$GUI.Nodes.VariantsComboBox.SelectedItem = 'Main'
}
else {
	$GUI.Nodes.VariantsComboBox.SelectedIndex = '0'
}

[Array]$selectedVariant = $SKVersions | Where-Object Variant -EQ $GUI.Nodes.VariantsComboBox.SelectedItem
if ($selectedVariant.count -eq 2) {
	$GUI.Nodes.Version.Text = "$($selectedVariant[0].Bits)Bit - v$($selectedVariant[0].Version) | $($selectedVariant[1].Bits)Bit - v$($selectedVariant[1].Version)"
}
elseif ($selectedVariant.Count -eq 1) {
	$GUI.Nodes.Version.Text = "$($selectedVariant[0].Bits)Bit - v$($selectedVariant[0].Version)"
}
else {
	$GUI.Nodes.Version.Text = 'Error'
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
		Write-Host 'Task removed succesfully'
		$GUI.Nodes.TaskButton.Content = 'Enable automatic update'
	}
	else {
		Register-UpdateTask
		$GUI.Nodes.TaskButton.Content = 'Disable automatic update'
	}
}

$Events.ButtonScan = {
	#Write-Host -NoNewline 'Scanning game folders for a local SpecialK dlls, this could take a while... '
	$dlls = ScanAndCache $AdditionalScanPaths
	if ($whitelist) {
		[Array]$dlls += $whitelist | Get-Item -ErrorAction 'SilentlyContinue' | Where-Object { ($_.VersionInfo.ProductName -EQ 'Special K') } | Write-Output
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
	[Array]$selectedVariant = $SKVersions | Where-Object Variant -EQ $GUI.Nodes.VariantsComboBox.SelectedItem
	if ($selectedVariant.count -eq 2) {
		$GUI.Nodes.Version.Text = "$($selectedVariant[0].Bits)Bit - v$($selectedVariant[0].Version) | $($selectedVariant[1].Bits)Bit - v$($selectedVariant[1].Version)"
	}
	elseif ($selectedVariant.count -eq 1) {
		$GUI.Nodes.Version.Text = "$($selectedVariant[0].Bits)Bit - v$($selectedVariant[0].Version)"
	}
	else {
		$GUI.Nodes.Version.Text = 'Error'
	}
}


$Events.ButtonDelete = {
	if ((Show-MessageBox -Message 'Are you sure you want to delete selected items?
This can not be undone!' -Title 'Confirm deletion' -Button 'YesNo' -Icon 'Question') -EQ 'Yes') {
		$GUI.Nodes.Games.ItemsSource | Where-Object 'IsChecked' -EQ $True | ForEach-Object {
			Remove-Item $_.FullName
			if ($GUI.Nodes.Games.ItemsSource.Count -gt 1) {
				[array]$script:instances[[array]::IndexOf($GUI.Nodes.Games.ItemsSource, $_)] = $null
			}
			else {
				$script:instances = @($null)
			}
		}
		$script:instances = $script:instances | Where-Object { $_ } #clear $null
		$GUI.Nodes.Games.ItemsSource = $null
		$GUI.Nodes.Games.ItemsSource = [Array]$script:instances
	}
}

[System.Windows.Input.MouseButtonEventHandler]$Events.ClickGameGrid = { 
	if ( ($_.LeftButton -EQ 'Pressed') -and ($_.OriginalSource.Name -EQ 'PathText') ) {
		$_.OriginalSource.DataContext.FullName
		. explorer.exe /select,"$($_.OriginalSource.DataContext.FullName)"
	}
}
[System.Windows.RoutedEventHandler]$Events.ButtonClickHandler = {
	If ($_.OriginalSource.Name -eq 'UpdateButton') { . $Events.ButtonUpdate }
	elseif ($_.OriginalSource.Name -eq 'ScanButton') { . $Events.ButtonScan }
	elseif ($_.OriginalSource.Name -eq 'TaskButton') { . $Events.ButtonTask }
	elseif ($_.OriginalSource.Name -eq 'PathText') { . explorer.exe /select,"$($_.OriginalSource.DataContext.FullName)" }
	
}

# $GUI.Nodes.UpdateButton.Add_Click()
# $GUI.Nodes.ScanButton.Add_Click()
# $GUI.Nodes.TaskButton.Add_Click()
$GUI.Nodes.CheckboxSelectAll.Add_Click($Events.SelectAll)
$GUI.Nodes.VariantsComboBox.Add_SelectionChanged($Events.VariantChange)
$GUI.Nodes.DeleteButton.Add_Click($Events.ButtonDelete)
$GUI.WPF.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $Events.ButtonClickHandler)

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
			$Remote = ((ConvertFrom-Json (Invoke-WebRequest 'https://sk-data.special-k.info/repository.json' -ErrorAction 'SilentlyContinue').Content).Main.Versions | Where-Object Branches -EQ 'Discord')[0]
			
			if ($Remote) {
				$NewestRemote = [version]$Remote.Name
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

					$GUI.Nodes.Update.Text = "There's an update available for your global Install: ($NewestRemote)`n"
					$GUI.Nodes.Update.Foreground = 'Green'
					if (($Remote.Installer -match '^https://') -or ($Remote.Installer -match '^http://')) {

				

						$InstallerLink = New-Object System.Windows.Documents.Hyperlink
						$InstallerLink.Inlines.add('Download')
						$InstallerLink.ToolTip = $Remote.Installer
						$InstallerLink.Add_Click({ Start-Process $Remote.Installer })

						$GUI.Nodes.Update.Inlines.add($InstallerLink)
					}
				})
		}
		else {
			$GUI.WPF.Dispatcher.Invoke([action] { 
					$GUI.Nodes.Update.Text = ''
				})
		}
	})

if (! $instances) {
	[void](Show-MessageBox -Message 'No local SpecialK installs found' -Title 'Error' -Button OK -Icon Warning)
}
$UpdateHandle = $UpdatePowershell.BeginInvoke()

[void]$GUI.WPF.ShowDialog() #show window

$UpdatePowershell.EndInvoke($UpdateHandle) | Out-Host
$UpdatePowershell.Dispose()
$UpdateRunspace.Close()
exit 0
