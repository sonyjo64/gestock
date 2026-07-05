; ─────────────────────────────────────────────────────────────────────────────
; Installateur Windows pour Gestock (POS Flutter)
; Compiler avec Inno Setup 6 :  ISCC.exe installer.iss
; Le fichier d'installation est généré dans :  installer\Gestock_Setup_v1.0.0.exe
; ─────────────────────────────────────────────────────────────────────────────

#define MyAppName "Gestock"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Smart Security"
#define MyAppExeName "pos_flutter.exe"

[Setup]
; Identifiant unique de l'application (ne pas changer entre les versions).
AppId={{A7E4C9F1-3B2D-4E6A-9C1F-8D5B0A2E7F34}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}

; Installation PAR UTILISATEUR dans %LOCALAPPDATA%\Gestock (pas d'admin requis).
; Indispensable : l'application crée sa base de données (pos_data) à côté de
; l'exécutable ; ce dossier doit donc être inscriptible (Program Files ne l'est pas).
DefaultDirName={localappdata}\{#MyAppName}
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

OutputDir=installer
OutputBaseFilename=Gestock_Setup_v{#MyAppVersion}
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
; Tout le contenu du build Release (exe + dll + dossier data\).
; IMPORTANT : on exclut "pos_data" (base de données de développement) pour que
; chaque nouvelle installation démarre avec une base vierge.
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "pos_data\*,pos_data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
