# Special K Local Updater (SKLU)

This script scan all game folders SKIF also knows about and replaces any local Special K DLLs found with the ones in Special Ks default install folder.

The script will create a settings file (SK_LU_settings.json) on the first start. 
You can add the absolute path to local DLLs to the `Blacklist` array in the settings file to exclude it from updating (automatically uncheck it in the GUI and also excludes it when using `-NoGUI`. This can be useful if the game only works with a specific version of Special K.
You can add the absolute path to local DLLs to the `AdditionalDLLs` array in the settings file to also include them in the GUI and update those automatically with `-NoGUI`.

It stores found dlls in a seperate file (SK_LU_cache.json) and uses them instead of scanning each time the updater is started. You have to rescan using the Scan button or `-Scan` parameter when you added or removed a local install. Be aware that scanning can take a long time. The ones added the settings file are always picked up without a scan.
`-NoGUI` tries to automatically patch all known dlls according to cache and settings.

The auto update button currently creates a daily task that makes use of `-NoGUI`.

#### Example SK_LU_settings.json

```
{
    "Blacklist":  [
        "C:\\Users\\Spodi\\AppData\\Local\\osu!\\OpenGL32.dll"
                  ],
    "AdditionalDLLs":  [
        "D:\\Games\\Dungeons and Dragons Online\\dxgi.dll",
        "D:\\Games\\Dungeons and Dragons Online\\x64\\dxgi.dll"
                       ]
}
```
