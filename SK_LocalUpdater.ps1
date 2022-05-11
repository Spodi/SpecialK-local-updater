<# 
	.Synopsis 
	Scans all game folders SKIF also knows about and updates any local Special K DLLs found.
	
	.Description 
    This script scan all game folders SKIF also knows about and replaces any local Special K DLLs found with the ones in Special Ks default install folder.
	You can add the absolute path to local DLLs to the "blacklist" array in "SK_LocalUpdater.json" to exclude it. This can be useful if the game only works with a specific version of Special K.
	You can add the absolute path to local DLLs to the "AdditionalDLLs" array in "SK_LocalUpdater.json" to also update those.
	
	.Notes
	Createdy by Spodi and Wall_SoGB
 #>
[CmdletBinding()]
param (
	[Parameter(Mandatory = $false)]
	[switch]$NoGUI,
	[switch]$Scan
)

#region Variables
# SpecialK Variables
$SK_DLLPath = [Environment]::GetFolderPath('MyDocuments') + '\My Mods\SpecialK'
$SpecialKVersions = @()
Get-Item "$SK_DLLPath\SpecialK*.dll" | Sort-Object name -Descending | ForEach-Object {
	$tempSKDll = New-Object PSObject
	Add-Member -InputObject $tempSKDll -MemberType NoteProperty -Name 'Name' -Value $_.Name
	Add-Member -InputObject $tempSKDll -MemberType NoteProperty -Name 'Version' -Value $_.VersionInfo.ProductVersion
	Add-Member -InputObject $tempSKDll -MemberType NoteProperty -Name 'VersionInternal' -Value $_.VersionInfo.ProductVersionRaw
	Add-Member -InputObject $tempSKDll -MemberType NoteProperty -Name 'Bits' -Value ($_.VersionInfo.InternalName -replace '[^0-9]' , '')
	$variant = ($_.Name -Replace '^.*?SpecialK[6,3][4,2]-?|\.dll.*$')
	if (!$variant) {
		$variant = 'Main'
	}
	Add-Member -InputObject $tempSKDll -MemberType NoteProperty -Name 'Variant' -Value $variant
	$SpecialKVersions += $tempSKDll
	Remove-Variable tempSKDll, variant
}
$SpecialKNewestVersionInternal = ((ConvertFrom-Json (Invoke-WebRequest https://sk-data.special-k.info/repository.json -ErrorAction SilentlyContinue).Content).Main.Versions | Where-Object Branches -EQ 'Discord')[0].Name
$SpecialKNewestVersion = $SpecialKNewestVersionInternal
$potentialNewestVersion = ($SpecialKVersions | Sort-Object VersionInternal -Descending)[0]
if ($potentialNewestVersion.VersionInternal -gt $SpecialKNewestVersionInternal) {
	$SpecialKNewestVersionInternal = $potentialNewestVersion.VersionInternal
	$SpecialKNewestVersion = $potentialNewestVersion.Version
}

$blacklist = $null
$whitelist = $null
$dllcache = $null
$dlls = $null

$apps = @()

if (Test-Path $PSScriptRoot\SK_LU_settings.json) {
	$blacklist = (Get-Content $PSScriptRoot\SK_LU_settings.json | ConvertFrom-Json).Blacklist
	$whitelist = (Get-Content $PSScriptRoot\SK_LU_settings.json | ConvertFrom-Json).AdditionalDLLs
} else {
	New-Item $PSScriptRoot\SK_LU_settings.json
	Set-Content $PSScriptRoot\SK_LU_settings.json -Value (@{'Blacklist' = @(); 'AdditionalDLLs' = @() } | ConvertTo-Json)
}

# Theming and window stuff
#Data for light or dark theme
$theme = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme').AppsUseLightTheme
if ($theme -eq 0) {
	$Foreground = 'White'
	$Background = '#141414'
	$WindowBackground = '#1a1a1a'
	$MouseOver = '#2b2b2b'
	$ButtonBackground = '#333333'
} else {
	$Foreground = 'Black'
	$Background = '#f2f2f2'
	$WindowBackground = '#ffffff'
	$MouseOver = '#e0e0e0'
	$ButtonBackground = '#d9d9d9'
}
#Round corners in win11
if ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuild).CurrentBuild -lt 22000) {
	$CornerRadius = 0
} else {
	$CornerRadius = 4
}
$windowTitle = 'SpecialK local install updater'
#endregion

#region Functions
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
			} elseif ($quotedElements.Count -eq 2) {
				# Create a new String hash
				Add-Member -InputObject $element -MemberType NoteProperty -Name $quotedElements[0].Value -Value $quotedElements[1].Value
			} elseif ($line -match '{') {
				$chain.Add($depth, $element)
				$depth++
				$parent = $chain.($depth - 1) # AKA $element
                
			} elseif ($line -match '}') {
				$depth--
				$parent = $chain.($depth - 1)
				$element = $parent
				$chain.Remove($depth)
			} else {
				# Comments etc
			}
		}

		return $root
	}
    
}

function Select-AllGames {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNull()]$CheckBox
	)

	if ($CheckBox.IsChecked) {
		$instances | ForEach-Object {
			$_.IsChecked = $true
		}
	} elseif ($CheckBox.IsChecked = $null) {
	} else {
		$instances | ForEach-Object {
			$_.IsChecked = $false
			$CheckBox.IsChecked = $false
		}
	}
	$Games.ItemsSource = $null
	$Games.ItemsSource = $instances
}

function Show-MessageBox {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$Message,
		[Parameter(Mandatory = $true)]
		[string]
		$Title,
		[Parameter(Mandatory = $false)] [ValidateSet('OK', 'OKCancel', 'RetryCancel', 'YesNo', 'YesNoCancel', 'AbortRetryIgnore')]
		[string]
		$Button = 'OK',
		[Parameter(Mandatory = $false)] [ValidateSet('Asterisk', 'Error', 'Exclamation', 'Hand', 'Information', 'None', 'Question', 'Stop', 'Warning')]
		[string]
		$Icon = 'None'
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

	If ($DisabledPlattforms -notcontains 'SKIF') {
		#Get custom SKIF games
		if (Test-Path $SKIFRegistry) {
			Write-Verbose 'SKIF install found!'

	(Get-Item -Path $SKIFRegistry).GetSubKeyNames() | ForEach-Object {
				$SKIFCustom = Get-ItemProperty -Path "$SKIFRegistry\$_"
				$apps += $SKIFCustom.InstallDir
			}
		}
	}
	If ($DisabledPlattforms -notcontains 'Steam') {
		#get Steam games
		if (Test-Path $SteamRegistry) {
			Write-Verbose 'Steam install found!'

			$steamPath = "$((Get-ItemProperty $SteamRegistry).SteamPath)".Replace('/', '\')

			# Old: \steamapps\libraryfolders.vdf
			# New:    \config\libraryfolders.vdf

			If (Test-Path "$($steamPath)\config\libraryfolders.vdf") {
				$steamVdf = ConvertFrom-VDF (Get-Content "$($steamPath)\config\libraryfolders.vdf" -Encoding UTF8)
			} else {
				$steamVdf = ConvertFrom-VDF (Get-Content "$($steamPath)\steamapps\libraryfolders.vdf" -Encoding UTF8)
			}

			#what even is this monstrosity? :D
			$steamlib = $steamVdf.libraryfolders | Get-Member -MemberType NoteProperty, Property | Select-Object -ExpandProperty Name | ForEach-Object { #this is for getting the nested objects name
				if ($null -ne $steamVdf.libraryfolders.$_.path) {
					$steamVdf.libraryfolders.$_.path
				}
			}
			$steamlib.replace('\\\\', '\') | ForEach-Object {
				if (Test-Path $_) {
					ForEach ($file in (Get-ChildItem "$_\SteamApps\*.acf") ) {
						$acf = ConvertFrom-VDF (Get-Content $file -Encoding UTF8)
						$apps += ($acf.AppState.InstallDir -replace ('^', "$_\SteamApps\common\")) #don't care about things in other folders, like \SteamApps\music. Non existing paths are filtered out later.
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
				$apps += $GOG.Path
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
					$acf = (Get-Content -Path $file -Encoding UTF8) | ConvertFrom-Json
					$apps += $acf.InstallLocation
				}
			}
		}
	}
	If ($DisabledPlattforms -notcontains 'XBOX') {
		#Get XBOX games
		if (Test-Path $XBOXRegistry) {
			$xboxDrives = @()
			Write-Verbose 'XBOX install found!'
		(Get-ChildItem -Path "$XBOXRegistry\*\*") | ForEach-Object {
				# Gets registered drive letter
				$xboxDrives += (($_ | Get-ItemProperty).Root).Replace('\\?\', '').Substring(0, 3) 	
			}
			# Gets install folders
		($xboxDrives | Sort-Object -Unique) | ForEach-Object {
				if (Test-Path $_) {
					$apps += ($_ + ((Get-Content "$_\.GamingRoot").Substring(5)).replace("`0", '')) # String needs to be cleaned out of null characters.
				}
			}
		}
	}
	$apps | Sort-Object -Unique | Where-Object { (Test-Path -LiteralPath $_ -PathType 'Container') } | Write-Output #remove duplicate and invalid entries and sort them nicely
}

function Find-SkDlls {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory, ValueFromPipeline)][String]$Path
	)
	begin {
		Write-Host -NoNewline 'Scanning game folders for a local SpecialK.dll, this could take a while... '
		$dllsList = ('dxgi.dll', 'd3d11.dll', 'd3d9.dll', 'd3d8.dll', 'ddraw.dll', 'dinput8.dll', 'opengl32.dll')
	}
	process {
		[System.IO.Directory]::EnumerateFiles($Path, '*.dll', 'AllDirectories') | Where-Object { ((Split-Path $_ -Leaf) -in $dllsList) } | Get-Item | Where-Object { ($_.VersionInfo.ProductName -EQ 'Special K') } | Write-Output
	}
}

function Register-UpdateTask {
	$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "$PSScriptRoot\SK_LocalUpdater.ps1 -nogui"
	$trigger = New-ScheduledTaskTrigger -Daily -At 5pm
	$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME
	$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
	$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal
	Register-ScheduledTask -TaskName 'Special K Local Updater Task' -InputObject $task -User $env:USERNAME
}

function Update-DllList { 
	[CmdletBinding()]
	param (
		[Parameter(Mandatory, ValueFromPipeline)]$dlls,
		[Parameter(Position = 0)]$blacklist
	)
	process {
		$obj = New-Object PSObject
		Add-Member -InputObject $obj -MemberType NoteProperty -Name Name -Value $_.Name
		Add-Member -InputObject $obj -MemberType NoteProperty -Name Directory -Value $_.DirectoryName
		Add-Member -InputObject $obj -MemberType NoteProperty -Name InternalName -Value $_.VersionInfo.InternalName
		Add-Member -InputObject $obj -MemberType NoteProperty -Name Version -Value $_.VersionInfo.ProductVersion
		Add-Member -InputObject $obj -MemberType NoteProperty -Name Bits -Value ($_.VersionInfo.InternalName -replace '[^0-9]' , '')
		if ((Join-Path -Path $_.DirectoryName -ChildPath $_.Name) -in $blacklist) {
			Add-Member -InputObject $obj -MemberType NoteProperty -Name IsChecked -Value $False -TypeName System.Boolean
		} else {
			Add-Member -InputObject $obj -MemberType NoteProperty -Name IsChecked -Value $True -TypeName System.Boolean
		}
		Write-Output $obj

	}
}

Function Show-GameList {
	$SpecialKVariants = ($SpecialKVersions | Select-Object Variant -Unique)
	Add-Type -AssemblyName PresentationCore, PresentationFramework, System.Windows.Forms
	[xml]$XAML = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
   			xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    		Name="Window"
			Title="$($windowTitle)"
			Foreground="$($Foreground)"
			Background="$($WindowBackground)"
			$(if(Test-Path "$PSScriptRoot\SKIF.ico"){"Icon=`"$PSScriptRoot\SKIF.ico`""})
    		MinHeight="300" MinWidth="300" Width="640"
			Height="Auto"
    		SizeToContent="Height" WindowStartupLocation="CenterScreen"
    		TextOptions.TextFormattingMode="Display" SnapsToDevicePixels="True"
    		FontFamily="Segoe UI" FontSize="13" ShowInTaskbar="True">
    		<Window.Resources>
				<Style TargetType="{x:Type Label}">
					<Setter Property="Foreground" Value="$($Foreground)"/>
            	</Style>
            	<Style TargetType="{x:Type Button}">
					<Setter Property="Foreground" Value="$($Foreground)"/>
					<Setter Property="Background" Value="$($ButtonBackground)"/>
					<Setter Property="BorderBrush" Value="$($ButtonBackground)" />
                	<Setter Property="Margin" Value="10"/>
                	<Setter Property="Padding" Value="10"/>
					<Style.Triggers>
                		<Trigger Property="IsMouseOver" Value="True">
                    		<Setter Property="Foreground" Value="Black"/>
                		</Trigger>
            		</Style.Triggers>
					<Style.Resources>
            			<Style TargetType="Border">
               				<Setter Property="CornerRadius" Value="$($CornerRadius)"/>
            			</Style>
        			</Style.Resources>
            	</Style>
				<Style TargetType="{x:Type DataGrid}">
            		<Setter Property="Background" Value="$($Background)" />
            		<Setter Property="HorizontalGridLinesBrush" Value="#585858" />
            		<Setter Property="VerticalGridLinesBrush" Value="#585858" />
            		<Setter Property="BorderBrush" Value="#585858" />
					<Setter Property="Margin" Value="10"/>
					<Setter Property="Padding" Value="4,8,4,8"/>
					<Setter Property="VerticalAlignment" Value="Center" />
					<Setter Property="RowHeight" Value="30"/>
					<Style.Resources>
            			<Style TargetType="{x:Type Border}">
               				<Setter Property="CornerRadius" Value="$($CornerRadius)"/>
            			</Style>
        			</Style.Resources>
				</Style>
				<Style TargetType="{x:Type DataGridRow}">
            		<Setter Property="Background" Value="$($Background)" />
            		<Setter Property="Foreground" Value="$($Foreground)" />
					<Style.Resources>
            			<Style TargetType="{x:Type Border}">
               				<Setter Property="CornerRadius" Value="$($CornerRadius)"/>
            			</Style>
        			</Style.Resources>
            		<Style.Triggers>
                		<Trigger Property="IsMouseOver" Value="True">
                    		<Setter Property="Background" Value="$($MouseOver)"/>
                		</Trigger>
            		</Style.Triggers>
        		</Style>
				<Style TargetType="{x:Type DataGridColumnHeader}">
						<Setter Property="HorizontalContentAlignment" Value="Center"/>
						<Setter Property="Background" Value="$($Background)" />
						<Setter Property="Foreground" Value="$($Foreground)" />
						<Setter Property="FontWeight" Value="Bold" />
				</Style>
				<Style TargetType="DataGridRowHeader">
					<Setter Property="Background" Value="$($Background)" />
            		<Setter Property="Foreground" Value="$($Foreground)" />
				</Style>
				<Style TargetType="DataGridCell">              
				  <Setter Property="Template">
					<Setter.Value>
					  <ControlTemplate TargetType="{x:Type DataGridCell}">
						<Grid Background="{TemplateBinding Background}">
						  <ContentPresenter VerticalAlignment="Center"/>
						</Grid>
					  </ControlTemplate>
					</Setter.Value>
				  </Setter>
				  <Setter Property="Padding" Value="40"/>
				</Style>
        	</Window.Resources>
        	<Grid>
            	<Grid.RowDefinitions>
                	<RowDefinition Height="Auto"/>
                	<RowDefinition Height="*"/>
                	<RowDefinition Height="Auto"/>
            	</Grid.RowDefinitions>
                <Label Grid.Row="0">
					<TextBlock HorizontalAlignment="Stretch" Margin="5, 10, 10, 10">
						Installed SpecialK version: 
						<LineBreak/> 
						$(
							$a = $SpecialKVersions | Sort-Object Variant, VersionInternal -Unique -Descending
                            $a | ForEach-Object {
								if(($a | Where-Object Variant -Like $_.Variant).Count -eq 2){
									if($_.VersionInternal -ge $SpecialKNewestVersionInternal){
										"$($_.Variant) - x$($_.Bits) - $($_.Version)"
									}
									else{
										"$($_.Variant) - x$($_.Bits) - <Bold Foreground=`"Orange`">$($_.version)</Bold>"
									}
								}
								else{
									if($_.VersionInternal -ge $SpecialKNewestVersionInternal){
										"$($_.Variant) - $($_.Version)"
									}
									else{
										"$($_.Variant) - <Bold Foreground=`"Orange`">$($_.version)</Bold>"
									}
								}
                                '<LineBreak/>'
                            }
                            
							if(($SpecialKVersions.VersionInternal | Select-Object -Unique -First 1) -lt $SpecialKNewestVersionInternal){
							"<LineBreak/>
							<Bold Foreground=`"Green`">There's an update available! ($SpecialKNewestVersionInternal)</Bold>"
							}
                            if($SpecialKVariants.Count){
                                "<LineBreak/>
								Variant to use:
								<LineBreak/>
								<ComboBox Name=`"VariantsComboBox`" MinWidth=`"82`" Width=`"Auto`"/>"
                            }
						)
					</TextBlock>
				</Label>
				<DataGrid Name="Games" AutoGenerateColumns="False" Height="Auto" Width="Auto" VerticalAlignment="Top" Grid.Row="1" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
						<DataGrid.Columns>
							<DataGridCheckBoxColumn Binding="{Binding Path=IsChecked,UpdateSourceTrigger=PropertyChanged}" MinWidth="30" MaxWidth="30" ElementStyle="{DynamicResource MetroDataGridCheckBox}" EditingElementStyle="{DynamicResource MetroDataGridCheckBox}">
								<DataGridCheckBoxColumn.Header>
									<CheckBox Name="CheckboxSelectAll" IsChecked="True">
										<CheckBox.LayoutTransform>
        									<ScaleTransform ScaleX="1.25" ScaleY="1.25" />
    									</CheckBox.LayoutTransform>
									</CheckBox>
						 		</DataGridCheckBoxColumn.Header>
					  		 </DataGridCheckBoxColumn>
							<DataGridTextColumn Header="Directory" Binding="{Binding Path=Directory}" MinWidth="70" Width="*" IsReadOnly="True">
								<DataGridTextColumn.ElementStyle>
									<Style TargetType="{x:Type TextBlock}">
										<Setter Property="Margin" Value="10,0,10,0" />
									</Style>
								</DataGridTextColumn.ElementStyle>
							</DataGridTextColumn>
							<DataGridTextColumn Header="Name" Binding="{Binding Path=Name}" MinWidth="70" Width="Auto" MaxWidth="100" IsReadOnly="True">
								<DataGridTextColumn.ElementStyle>
									<Style TargetType="{x:Type TextBlock}">
										<Setter Property="TextAlignment" Value="Center"/>
										<Setter Property="Margin" Value="10,0,10,0" />
									</Style>
								</DataGridTextColumn.ElementStyle>
							</DataGridTextColumn>
							<DataGridTextColumn Header="Bits" Binding="{Binding Path=Bits}" MinWidth="35" MaxWidth="35" IsReadOnly="True">
								<DataGridTextColumn.ElementStyle>
									<Style TargetType="{x:Type TextBlock}">
										<Setter Property="TextAlignment" Value="Center"/>
										<Setter Property="Margin" Value="10,0,10,0" />
									</Style>
								</DataGridTextColumn.ElementStyle>
							</DataGridTextColumn>
							<DataGridTextColumn Header="Version" Binding="{Binding Path=Version}" MinWidth="60" Width="Auto" MaxWidth="80" IsReadOnly="True">
								<DataGridTextColumn.ElementStyle>
									<Style TargetType="{x:Type TextBlock}">
										<Style.Triggers>
											<Trigger Property="Text" Value="$($SpecialKNewestVersion)">
												<Setter Property="Foreground" Value="$($Foreground)"/>
												<Setter Property="Margin" Value="10,0,10,0" />
											</Trigger>
										</Style.Triggers>
										<Setter Property="Foreground" Value="Orange"/>
										<Setter Property="TextAlignment" Value="Center"/>
									</Style>
								</DataGridTextColumn.ElementStyle>
							</DataGridTextColumn>
						</DataGrid.Columns>
					</DataGrid>
            	<Button Name="UpdateButton" Grid.Row="2" HorizontalAlignment="Right" VerticalAlignment="Bottom" Width="100">Update</Button>
				<Button Name="ScanButton" Grid.Row="2" HorizontalAlignment="Left" VerticalAlignment="Bottom" Width="100">Scan</Button>
				<Button Name="TaskButton" Grid.Row="2" HorizontalAlignment="Center" VerticalAlignment="Bottom" Width="Auto">
				$(if(Get-ScheduledTask -TaskName 'Special K Local Updater Task' -ErrorAction Ignore){
					'Disable Automatic Update'
				}
				else{
					'Enable Automatic Update'
				})
				</Button>
			</Grid>
	</Window>
"@
    
	$Reader = (New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAML)
	$Form = [Windows.Markup.XamlReader]::Load($Reader)

	$XAML.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
		Set-Variable -Name ($_.Name) -Value $Form.FindName($_.Name) -Scope Global
	}
	if ($SpecialKVariants.Count) {
		$VariantsComboBox.ItemsSource = $SpecialKVariants.Variant
		$VariantsComboBox.SelectedItem = 'Main'
	}

	$CheckboxSelectAll.Add_Click({ Select-AllGames -CheckBox $_.source })

	$ButtonUpdate = {
		$Games.ItemsSource | Where-Object { $_.IsChecked -eq $True } | ForEach-Object {
			$destination = Join-Path -Path $_.Directory -ChildPath $_.Name
			try {			
				$usedDll = $SpecialKVersions | Where-Object Bits -Like $_.Bits | Where-Object Variant -EQ $VariantsComboBox.SelectedItem
				$source = Join-Path -Path $SK_DLLPath -ChildPath $usedDll.Name
				Write-Host "Copy item `"$($source)`" to destination `"$destination`""
				Copy-Item -LiteralPath $source -Destination $destination -ErrorAction 'Stop'
				$_.Version = $usedDll.Version
			} catch {
				Write-Error "Failed to update `"$destination`"
$_"
			}
			$i++
		}
		$Games.ItemsSource = $null
		$Games.ItemsSource = $instances
	}

	$ButtonTask = {
		if (Get-ScheduledTask -TaskName 'Special K Local Updater Task' -ErrorAction Ignore) {
			Unregister-ScheduledTask -TaskName 'Special K Local Updater Task' -Confirm:$false
			$TaskButton.Content = 'Enable automatic update'
		} else {
			Register-UpdateTask
			$TaskButton.Content = 'Disable automatic update'
		}
	}

	$ButtonScan = {
		$dlls = Get-GameFolders | Find-SkDlls
		[System.IO.File]::WriteAllLines("$PSScriptRoot\SK_LU_cache.json", ($dlls.FullName | ConvertTo-Json))	
		if ($whitelist) {
			$dlls += $whitelist
		}
		$instances = $dlls | Update-DllList $blacklist
		Write-Host 'Done'
		$Games.ItemsSource = $null
		$Games.ItemsSource = $instances
	}

	$Window.Add_Loaded({
			$Games.ItemsSource = $instances
		})

	$UpdateButton.Add_Click($ButtonUpdate)
	$ScanButton.Add_Click($ButtonScan)
	$TaskButton.Add_Click($ButtonTask)


	if ($instances) {
		$Form.ShowDialog() | Out-Null
	} else {
		Show-MessageBox -Message 'No SpecialK installs found' -Title $windowTitle -Button OK -Icon Warning
	}

}

#endregion

if (! $Scan) {
	if (Test-Path $PSScriptRoot\SK_LU_cache.json) {
		Write-Host -NoNewline 'Loading cached locations...'
		$dllcache = (Get-Content $PSScriptRoot\SK_LU_cache.json | ConvertFrom-Json)
	}
}	
if ($dllcache) {
	$dlls += $dllcache | Get-Item | Where-Object { ($_.VersionInfo.ProductName -EQ 'Special K') } | Write-Output
} else {
	$dlls += Get-GameFolders | Find-SkDlls
	[System.IO.File]::WriteAllLines("$PSScriptRoot\SK_LU_cache.json", ($dlls.FullName | ConvertTo-Json))
		
}
if ($whitelist) {
	$dlls += $whitelist
}
Write-Host 'Done'

$instances = $dlls | Update-DllList $blacklist

if ($NoGUI) {
	Write-Host ''
	$instances | ForEach-Object {
		$destination = Join-Path -Path $_.Directory -ChildPath $_.Name
		if ($destination -notin $blacklist) {	
			Write-Host "Copy item `"$(Join-Path -Path $SK_DLLPath -ChildPath $_.InternalName)`" to destination `"$destination`""
			Copy-Item -LiteralPath (Join-Path -Path $SK_DLLPath -ChildPath $_.InternalName) -Destination $destination
		}
	} 
} else {
	Show-GameList
}