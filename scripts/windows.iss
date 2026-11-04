#define AppVersion "0.8.0"
#ifndef BundleDir
  #define BundleDir "..\apps\devcat_flutter\build\windows\x64\runner\Release"
#endif
[Setup]
AppId={{655B3A52-8BFC-45F6-A4DD-54F88CF7064F}
AppName=DevCat
AppVersion={#AppVersion}
AppPublisher=DevCat contributors
DefaultDirName={localappdata}\Programs\DevCat
DefaultGroupName=DevCat
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=DevCat-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\apps\devcat_flutter\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\devcat.exe
[InstallDelete]
Type: filesandordirs; Name: "{app}\runtime"
[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\DevCat"; Filename: "{app}\devcat.exe"
Name: "{autodesktop}\DevCat"; Filename: "{app}\devcat.exe"; Tasks: desktopicon
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
[Run]
Filename: "{app}\devcat.exe"; Description: "Launch DevCat"; Flags: nowait postinstall skipifsilent
