; Downie6 Windows 安装包脚本（Inno Setup 6）
; 生成单个 setup.exe，用户双击即可安装（含开始菜单/桌面快捷方式/卸载）
; 用法：iscc setup.iss

#define MyAppName "Downie6"
; 安装目录使用 Downie6；旧版 4KDownle 的目录不会被自动迁移
#define MyAppDirName "Downie6"
#define MyAppVersion "2.0.33"
#define MyAppExeName "Downie6.exe"

[Setup]
AppId={{7C1A2B3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
DefaultDirName={autopf}\{#MyAppDirName}
DefaultGroupName={#MyAppName}
OutputDir=Output
OutputBaseFilename=Downie6-Setup-{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"

[Files]
; WebView2 运行时安装器（CI 下载，安装时若没装 WebView2 就静默装）
Source: "MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; downie6:// 自动化协议（Windows 通过命令行参数传给 Dart main）
Root: HKLM; Subkey: "Software\Classes\downie6"; ValueType: string; ValueName: ""; ValueData: "URL:Downie6 Protocol"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\downie6"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKLM; Subkey: "Software\Classes\downie6\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKLM; Subkey: "Software\Classes\downie6\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""
; 授权自动化：同时接受 Downie 原生 downie-license 和 downie6-license
Root: HKLM; Subkey: "Software\Classes\downie6-license"; ValueType: string; ValueName: ""; ValueData: "URL:Downie6 License Protocol"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\downie6-license"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKLM; Subkey: "Software\Classes\downie6-license\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\downie-license"; ValueType: string; ValueName: ""; ValueData: "URL:Downie License Protocol"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\downie-license"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKLM; Subkey: "Software\Classes\downie-license\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
; 没装 WebView2 就静默安装（/norestart 避免强制重启）
Filename: "{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; Parameters: "/silent /install /norestart"; StatusMsg: "正在安装 WebView2 运行时..."; Check: WebView2NotInstalled; Flags: waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall

[Code]
function WebView2NotInstalled: Boolean;
begin
  Result := not (
    RegKeyExists(HKLM64, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
    RegKeyExists(HKLM64, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
    RegKeyExists(HKCU, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}')
  );
end;
