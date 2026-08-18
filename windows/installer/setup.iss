; Downlo PRO Windows 安装包脚本（Inno Setup 6）
; 生成单个 setup.exe，用户双击即可安装（含开始菜单/桌面快捷方式/卸载）
; 用法：iscc setup.iss

#define MyAppName "Downlo PRO"
#define MyAppVersion "2.0.0"
#define MyAppExeName "downlo_test.exe"

[Setup]
AppId={{7C1A2B3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=Output
OutputBaseFilename=DownloPRO-Setup-{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
