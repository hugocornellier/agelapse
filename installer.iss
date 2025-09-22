#define MyAppName "AgeLapse"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "Hugo Cornellier"
#define MyAppExeName "agelapse.exe"
#define MyAppURL "https://github.com/hugocornellier/agelapse"

[Setup]
AppId={{8D6A1D50-8A21-4E3C-9BB9-3CBB0A1C2F3C}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={pf64}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=dist\installer
OutputBaseFilename={#MyAppName}_Setup_{#MyAppVersion}_x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupLogging=yes
PrivilegesRequired=admin
SetupIconFile=windows\runner\resources\app_icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Entire Flutter release output
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

; Ensure critical Flutter runtime files are present (belt & suspenders)
Source: "build\windows\x64\runner\Release\icudtl.dat"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\d3dcompiler_47.dll"; DestDir: "{app}"; Flags: ignoreversion

; Explicitly copy the data/ tree (flutter_assets, etc.)
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs createallsubdirs ignoreversion

; VC++ Redist payload (optional but recommended)
Source: "packaging\redist\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Code]
function VCInstalled: Boolean;
var
  Installed: Cardinal;
begin
  Result := False;

  if RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) and (Installed = 1) then
    Result := True;

  if (not Result) and RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\VC\Runtimes\x64', 'Installed', Installed) and (Installed = 1) then
    Result := True;

  if (not Result) and RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) and (Installed = 1) then
    Result := True;

  if (not Result) and RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\VC\Runtimes\x64', 'Installed', Installed) and (Installed = 1) then
    Result := True;
end;

function NeedsVCRedist: Boolean;
begin
  Result := not VCInstalled();
end;

[Run]
; Install VC++ runtime if not present
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Check: NeedsVCRedist(); Flags: skipifdoesntexist waituntilterminated

; Optional: launch after install
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
