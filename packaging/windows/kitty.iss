; Inno Setup script for the kitty Windows port.
; Build: run make-dist.sh first (creates ..\..\dist\kitty), then
;   ISCC.exe /DAppVersion=<version> kitty.iss
; Produces dist\kitty-setup.exe. Per-user install: no admin required.

#ifndef AppVersion
  #define AppVersion "0.48.0"
#endif

[Setup]
AppId={{A303A4CC-F4EE-40BE-B881-1C25CDB1AC19}
AppName=kitty
AppVersion={#AppVersion}
AppPublisher=Kovid Goyal (Windows port by ecstra)
AppPublisherURL=https://sw.kovidgoyal.net/kitty/
DefaultDirName={autopf}\kitty
DisableProgramGroupPage=yes
; Keep kitty installable on a standard account. Auto constants and HKA below
; resolve to this user's profile and registry hive in non-administrative mode.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=kitty-setup
SetupIconFile=..\..\kitty\launcher\kitty.ico
UninstallDisplayIcon={app}\kitty\launcher\kitty.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ChangesEnvironment=yes

[Tasks]
Name: "addtopath"; Description: "Add kitty to your user PATH (so 'kitty' and 'kitten' work in your terminals)"
Name: "contextmenu"; Description: "Add 'Open in kitty' to your Explorer right-click menu for this account"
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\..\dist\kitty\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
Source: "..\..\dist\kitty-menu.msix"; DestDir: "{app}\msix"; Tasks: contextmenu; Check: IsWin11
Source: "..\..\dist\kitty-menu.cer"; DestDir: "{app}\msix"; Tasks: contextmenu; Check: IsWin11

[Icons]
Name: "{autoprograms}\kitty"; Filename: "{app}\kitty\launcher\kitty.exe"; WorkingDir: "{%USERPROFILE}"
Name: "{autodesktop}\kitty"; Filename: "{app}\kitty\launcher\kitty.exe"; WorkingDir: "{%USERPROFILE}"; Tasks: desktopicon

[Registry]
; Classic registry verbs. These are the whole entry on Windows 10, whose menu
; reads nothing else. On Windows 11 the sparse MSIX package supplies the modern
; menu, and these cover Show more options, which the modern menu falls back to.
; If a Windows 11 build ever shows the packaged verb in Show more options as
; well, this would read as a duplicate there and should be gated back behind
; "Check: not IsWin11".
; Right-click on a folder
Root: HKA; Subkey: "Software\Classes\Directory\shell\kitty"; ValueType: string; ValueName: ""; ValueData: "Open in kitty"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\kitty"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\kitty\launcher\kitty.exe"; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\kitty\command"; ValueType: string; ValueName: ""; ValueData: """{app}\kitty\launcher\kitty.exe"" --directory ""%V"""; Tasks: contextmenu
; Right-click on the background of an open folder
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\kitty"; ValueType: string; ValueName: ""; ValueData: "Open in kitty"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\kitty"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\kitty\launcher\kitty.exe"; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\kitty\command"; ValueType: string; ValueName: ""; ValueData: """{app}\kitty\launcher\kitty.exe"" --directory ""%V"""; Tasks: contextmenu
; Right-click on a drive
Root: HKA; Subkey: "Software\Classes\Drive\shell\kitty"; ValueType: string; ValueName: ""; ValueData: "Open in kitty"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Drive\shell\kitty"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\kitty\launcher\kitty.exe"; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Drive\shell\kitty\command"; ValueType: string; ValueName: ""; ValueData: """{app}\kitty\launcher\kitty.exe"" --directory ""%V"""; Tasks: contextmenu

[Code]
const EnvKey = 'Environment';

function IsWin11(): Boolean;
var
  V: TWindowsVersion;
begin
  GetWindowsVersionEx(V);
  Result := V.Build >= 22000;
end;

function BinDir(): string;
begin
  Result := ExpandConstant('{app}') + '\bin';
end;

procedure EnvAddPath(const Dir: string);
var
  Paths: string;
begin
  if not RegQueryStringValue(HKCU, EnvKey, 'Path', Paths) then
    Paths := '';
  if Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Paths) + ';') > 0 then
    exit;
  if (Paths <> '') and (Paths[Length(Paths)] <> ';') then
    Paths := Paths + ';';
  Paths := Paths + Dir;
  RegWriteExpandStringValue(HKCU, EnvKey, 'Path', Paths);
end;

procedure EnvRemovePath(const Dir: string);
var
  Paths, Upper: string;
  P: Integer;
begin
  if not RegQueryStringValue(HKCU, EnvKey, 'Path', Paths) then
    exit;
  Upper := ';' + Uppercase(Paths) + ';';
  P := Pos(';' + Uppercase(Dir) + ';', Upper);
  if P = 0 then
    exit;
  { P is an index into the ';'-prefixed string: cut the entry and one ';' }
  Delete(Paths, P, Length(Dir) + 1);
  RegWriteExpandStringValue(HKCU, EnvKey, 'Path', Paths);
end;

function ExecAndWait(const FileName, Params: string): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(FileName, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := Result and (ResultCode = 0);
end;

procedure ReportContextMenuFailure();
begin
  SuppressibleMsgBox(
    'kitty was installed, but Windows could not enable its optional Explorer context menu. You can still launch kitty from the Start menu.',
    mbError, MB_OK, IDOK);
end;

{ Windows 11 modern context menu: trust the self-signed certificate and
  register the sparse MSIX package pointing at the install directory. }
procedure RegisterMsix();
begin
  { Trust only this user's package certificate; no machine-wide trust or admin
    rights are needed for a per-user sparse package installation. }
  if not ExecAndWait(ExpandConstant('{sys}\certutil.exe'),
       ExpandConstant('-user -addstore -f TrustedPeople "{app}\msix\kitty-menu.cer"')) then begin
    ReportContextMenuFailure();
    exit;
  end;
  { Replace any prior registration for this user before registering the new
    package against this install directory. }
  if not ExecAndWait(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
       ExpandConstant('-NoProfile -ExecutionPolicy Bypass -Command "try { Get-AppxPackage -Name ''Ecstra.Kitty.ContextMenu'' | Remove-AppxPackage -ErrorAction SilentlyContinue; Add-AppxPackage -Path ''{app}\msix\kitty-menu.msix'' -ExternalLocation ''{app}'' -ErrorAction Stop; exit 0 } catch { Write-Error $_; exit 1 }"')) then
    ReportContextMenuFailure();
end;

procedure UnregisterMsix();
begin
  ExecAndWait(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
       '-NoProfile -ExecutionPolicy Bypass -Command "Get-AppxPackage -Name Ecstra.Kitty.ContextMenu | Remove-AppxPackage -ErrorAction SilentlyContinue"');
end;

procedure RemovePackageCertificate();
begin
  if FileExists(ExpandConstant('{app}\msix\kitty-menu.cer')) then
    ExecAndWait(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      ExpandConstant('-NoProfile -ExecutionPolicy Bypass -Command "$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(''{app}\msix\kitty-menu.cer''); Remove-Item -LiteralPath (''Cert:\CurrentUser\TrustedPeople\'' + $cert.Thumbprint) -ErrorAction SilentlyContinue"'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    if WizardIsTaskSelected('addtopath') then begin
      EnvAddPath(BinDir());
      { Older installs put the DLL-laden launcher directory on PATH: remove it. }
      EnvRemovePath(ExpandConstant('{app}') + '\kitty\launcher');
    end;
    if WizardIsTaskSelected('contextmenu') and IsWin11() then
      RegisterMsix();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    UnregisterMsix();
    RemovePackageCertificate();
  end;
  if CurUninstallStep = usPostUninstall then begin
    EnvRemovePath(BinDir());
    EnvRemovePath(ExpandConstant('{app}') + '\kitty\launcher');
  end;
end;
