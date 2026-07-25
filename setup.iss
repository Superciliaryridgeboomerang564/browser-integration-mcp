; ===== Browser-Integration MCP - installer (Inno Setup 6) =====
#define AppName "Browser-Integration MCP"
#define AppVer  "5.0.1"

[Setup]
AppName={#AppName}
AppVersion={#AppVer}
AppPublisher=viRomulus
DefaultDirName={userdocs}\Browser-Integration-mcp\Core-Browser-Integration-mcp
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=lowest
OutputDir=build
OutputBaseFilename=BrowserIntegrationMCP-Setup-v5.0.1
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
DisableReadyPage=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Dirs]
Name: "{userdocs}\Browser-Integration-mcp"

[Files]
Source: "payload\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "README.txt";    DestDir: "{userdocs}\Browser-Integration-mcp"; Flags: ignoreversion
Source: "README.ru.txt"; DestDir: "{userdocs}\Browser-Integration-mcp"; Flags: ignoreversion
Source: "LICENSE";      DestDir: "{userdocs}\Browser-Integration-mcp"; Flags: ignoreversion
Source: "installer-logic.ps1"; Flags: dontcopy

[Code]
var
  AgreePage: TWizardPage;
  AgreeMemo: TNewMemo;
  AgreeCheck: TNewCheckBox;
  SelectPage: TInputOptionWizardPage;
  ReportPage: TOutputMsgMemoWizardPage;
  InstrPage: TOutputMsgMemoWizardPage;
  GInstallExit: Integer;
  GInstalled: Boolean;
  GBrowserNames: TArrayOfString;
  GBrowserExes: TArrayOfString;
  GBrowserCount: Integer;

function RunPS(const Params: String; var ResultCode: Integer): Boolean;
var
  logic: String;
begin
  logic := ExpandConstant('{tmp}\installer-logic.ps1');
  Result := Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -File "' + logic + '" ' + Params,
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function InitializeSetup(): Boolean;
var
  rc, i, p: Integer;
  bf: String;
  lines: TArrayOfString;
begin
  ExtractTemporaryFile('installer-logic.ps1');
  bf := ExpandConstant('{tmp}\browsers.txt');
  if not RunPS('-Mode precheck -BrowsersFile "' + bf + '"', rc) then begin
    MsgBox('Failed to check the environment (PowerShell unavailable). Setup aborted.', mbCriticalError, MB_OK);
    Result := False; Exit;
  end;
  if rc = 1 then begin
    MsgBox('Node.js was not found.' + #13#10 + 'Install Node.js (any version) and run the installer again.', mbCriticalError, MB_OK);
    Result := False; Exit;
  end;
  if rc = 2 then begin
    MsgBox('No supported browser was found.' + #13#10 + 'Install Google Chrome, Microsoft Edge, or Vivaldi and run the installer again.', mbCriticalError, MB_OK);
    Result := False; Exit;
  end;
  if rc <> 0 then begin
    MsgBox('Environment check failed. Setup aborted.', mbCriticalError, MB_OK);
    Result := False; Exit;
  end;
  if LoadStringsFromFile(bf, lines) then begin
    for i := 0 to GetArrayLength(lines)-1 do begin
      p := Pos('|', lines[i]);
      if p > 0 then begin
        SetArrayLength(GBrowserNames, GBrowserCount+1);
        SetArrayLength(GBrowserExes,  GBrowserCount+1);
        GBrowserNames[GBrowserCount] := Copy(lines[i], 1, p-1);
        GBrowserExes[GBrowserCount]  := Copy(lines[i], p+1, Length(lines[i]));
        GBrowserCount := GBrowserCount + 1;
      end;
    end;
  end;
  if GBrowserCount = 0 then begin
    MsgBox('No supported browser was found.', mbCriticalError, MB_OK);
    Result := False; Exit;
  end;
  Result := True;
end;

procedure AgreeCheckClick(Sender: TObject);
begin
  WizardForm.NextButton.Enabled := AgreeCheck.Checked;
end;

procedure InitializeWizard();
var
  instr: String;
  i: Integer;
begin
  WizardForm.WelcomeLabel2.Caption :=
    WizardForm.WelcomeLabel2.Caption + #13#10 + #13#10 +
    'Not affiliated with, endorsed by, or sponsored by Vivaldi Technologies AS, Google LLC, Microsoft Corporation, or Anthropic PBC. Vivaldi, Google Chrome, Microsoft Edge, and Claude are trademarks of their respective owners.' + #13#10 + #13#10 +
    'Installation and use are at your own risk. You must accept the license and liability terms on the next page to continue.';

  { License / liability agreement page with a mandatory checkbox }
  AgreePage := CreateCustomPage(wpWelcome, 'License and Liability Agreement',
    'Please read and accept the terms before installing');

  AgreeMemo := TNewMemo.Create(WizardForm);
  AgreeMemo.Parent := AgreePage.Surface;
  AgreeMemo.Left := 0;
  AgreeMemo.Top := 0;
  AgreeMemo.Width := AgreePage.SurfaceWidth;
  AgreeMemo.Height := AgreePage.SurfaceHeight - ScaleY(30);
  AgreeMemo.ScrollBars := ssVertical;
  AgreeMemo.ReadOnly := True;
  AgreeMemo.WordWrap := True;
  AgreeMemo.Text :=
    'Browser-Integration MCP - License and Legal Terms' + #13#10 + #13#10 +
    'TRADEMARKS. Not affiliated with, endorsed by, or sponsored by Vivaldi Technologies AS, Google LLC, Microsoft Corporation, or Anthropic PBC. Vivaldi, Google Chrome, Microsoft Edge, and Claude are trademarks of their respective owners.' + #13#10 + #13#10 +
    'THIRD-PARTY. This tool bundles chrome-devtools-mcp (Copyright Google LLC, licensed under Apache-2.0); its LICENSE and THIRD_PARTY_NOTICES ship inside the package.' + #13#10 + #13#10 +
    'LICENSE. This software (the "MCP") is licensed under the MIT License.' + #13#10 + #13#10 +
    'USAGE. Intended for lawful, personal use. The tool automates a copy of a supported browser (Google Chrome, Microsoft Edge, or Vivaldi) that you installed yourself, via Chromium''s built-in DevTools Protocol (CDP) using public command-line switches; it does not modify, reverse-engineer, redistribute, or bundle any browser or Claude, and runs as an MCP extension inside your own Claude Desktop. You are responsible for complying with applicable law and with the terms of the software it works with (your browser''s terms of use or EULA and Anthropic''s Usage Policy / Consumer Terms), and for any actions performed through the browser agent.' + #13#10 + #13#10 +
    'WARRANTY AND LIABILITY. The MCP is provided "AS IS", without warranty of any kind. To the maximum extent permitted by applicable law, the author shall not be liable for any claim, damages, or other liability - including any theft, leakage, disclosure, alteration, corruption, deletion, or loss of data, or any direct, indirect, incidental, special, or consequential damages - arising from or in connection with the MCP or any actions performed through it.' + #13#10 + #13#10 +
    'By checking the box below and continuing, you acknowledge that you have read, understood, and accepted these terms. If you do not agree, close the installer.';

  AgreeCheck := TNewCheckBox.Create(WizardForm);
  AgreeCheck.Parent := AgreePage.Surface;
  AgreeCheck.Left := 0;
  AgreeCheck.Top := AgreePage.SurfaceHeight - ScaleY(22);
  AgreeCheck.Width := AgreePage.SurfaceWidth;
  AgreeCheck.Caption := 'I have read and accept the terms above';
  AgreeCheck.OnClick := @AgreeCheckClick;

  { Browser selection page (radio; only the browsers that were found) }
  SelectPage := CreateInputOptionPage(AgreePage.ID,
    'Agent browser', 'Choose which browser the agent will use',
    'A separate, clean profile is created for the selected browser:', True, False);
  for i := 0 to GBrowserCount-1 do
    SelectPage.Add(GBrowserNames[i]);
  SelectPage.SelectedValueIndex := -1;

  ReportPage := CreateOutputMsgMemoPage(wpInstalling,
    'Installation result', 'What was prepared',
    'Summary:', '');

  instr :=
    'One manual step remains (the installer intentionally does not do it for you):' + #13#10 + #13#10 +
    '1) Load the MCP into Claude Desktop:' + #13#10 +
    '   Claude Desktop settings -> Extensions (Advanced Settings) ->' + #13#10 +
    '   "Install Unpacked Extension" -> select the folder:' + #13#10 +
    '   Documents\Browser-Integration-mcp\Core-Browser-Integration-mcp' + #13#10 +
    '   Then enable the extension.' + #13#10 + #13#10 +
    'How it works: the agent browser is a SHARED browser owned by a local broker.' + #13#10 +
    'Chrome runs on a private pipe (no debugging TCP port); the broker exposes a' + #13#10 +
    'loopback WebSocket guarded by a random token and a connecting-process check.' + #13#10 +
    'The MCP starts the broker on first use and connects to it. The browser stays' + #13#10 +
    'open across chats and is shared by every chat/app: they take turns (a new one' + #13#10 +
    'takes over; the previous reconnects on its next action). Closing one chat does' + #13#10 +
    'not close the browser.' + #13#10 + #13#10 +
    'Signing in to sites: ask the agent to open the site, then log in yourself in' + #13#10 +
    'the browser window. The agent profile is separate and clean, and your sessions' + #13#10 +
    'persist in it across restarts.' + #13#10 + #13#10 +
'Links: "Agent Browser" is registered and a Desktop shortcut is created. To open' + #13#10 +
    'clicked links in the agent browser, pick "Agent Browser" in Windows Settings >' + #13#10 +
    'Default apps (this installer opens that page for you at the end). Windows only' + #13#10 +
    'lets you set the default manually.' + #13#10 + #13#10 +
    'Note: this tool automates your chosen browser (Google Chrome, Microsoft Edge,' + #13#10 +
    'or Vivaldi) but is not affiliated with their vendors or Anthropic PBC.';

  InstrPage := CreateOutputMsgMemoPage(ReportPage.ID,
    'Next steps', 'Load the MCP into Claude Desktop',
    'Instructions:', instr);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = AgreePage.ID) and (not AgreeCheck.Checked) then begin
    MsgBox('You must accept the license and liability terms to install.', mbError, MB_OK);
    Result := False;
  end;
  if (CurPageID = SelectPage.ID) and (SelectPage.SelectedValueIndex < 0) then begin
    MsgBox('Please select a browser for the agent before continuing.', mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  rc, idx: Integer;
  mcp, prof, res, bexe, bname: String;
begin
  if CurStep = ssPostInstall then begin
    ExtractTemporaryFile('installer-logic.ps1');
    idx := SelectPage.SelectedValueIndex;
    if idx < 0 then idx := 0;
    bname := GBrowserNames[idx];
    bexe  := GBrowserExes[idx];
    mcp  := ExpandConstant('{app}');
    prof := ExpandConstant('{userdocs}\Browser-Integration-mcp\Browser-Agent-for-Integration-') + bname;
    res  := ExpandConstant('{tmp}\result.txt');
    RunPS('-Mode install -McpDir "' + mcp + '" -ProfileDir "' + prof + '" -BrowserExe "' + bexe + '" -BrowserName "' + bname + '" -ResultFile "' + res + '"', rc);
    GInstallExit := rc;
    GInstalled := True;
    { Register the agent browser as a default-browser candidate (HKCU) and create
      Start Menu + Desktop shortcuts, so it is selectable in Settings > Default apps. }
    Exec('powershell.exe',
      '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\broker\install\register.ps1') + '" -BrowserExe "' + bexe + '"',
      '', SW_HIDE, ewWaitUntilTerminated, rc);
  end;
end;

function GetVal(const Lines: TArrayOfString; const Key: String): String;
var
  i, kl: Integer;
begin
  Result := '';
  kl := Length(Key);
  for i := 0 to GetArrayLength(Lines)-1 do
    if Copy(Lines[i], 1, kl) = Key then begin
      Result := Copy(Lines[i], kl+1, 4096);
      Exit;
    end;
end;

procedure CurPageChanged(CurPageID: Integer);
var
  lines: TArrayOfString;
  res, txt: String;
begin
  if CurPageID = AgreePage.ID then
    WizardForm.NextButton.Enabled := AgreeCheck.Checked
  else
    WizardForm.NextButton.Enabled := True;
  if CurPageID = ReportPage.ID then begin
    res := ExpandConstant('{tmp}\result.txt');
    txt := '';
    if LoadStringsFromFile(res, lines) then begin
      txt := 'Structure created under Documents\Browser-Integration-mcp.' + #13#10 + #13#10 +
             'Agent browser: ' + GetVal(lines, 'BROWSER_NAME=') + #13#10 +
             'Browser path:  ' + GetVal(lines, 'BROWSER=') + #13#10 +
             'Node.js:       ' + GetVal(lines, 'NODE=') + #13#10 + #13#10 +
             'MCP configured (paths baked in): ' + GetVal(lines, 'MCP_BAKED=') + '  (1 = yes)' + #13#10 +
             'Agent profile folder ready:      ' + GetVal(lines, 'PROFILE_OK=') + '  (1 = yes)' + #13#10;
      if GInstallExit <> 0 then
        txt := txt + #13#10 + 'WARNING: exit code = ' + IntToStr(GInstallExit) + '. Something may not be fully installed.';
    end else
      txt := 'Could not read the installation result. Exit code: ' + IntToStr(GInstallExit);
    ReportPage.RichEditViewer.Lines.Text := txt;
  end;
end;

procedure DeinitializeSetup();
var
  err: Integer;
begin
  if GInstalled then begin
    ShellExec('', ExpandConstant('{userdocs}\Browser-Integration-mcp\README.txt'), '', '', SW_SHOWNORMAL, ewNoWait, err);
    ShellExec('', ExpandConstant('{userdocs}\Browser-Integration-mcp\README.ru.txt'), '', '', SW_SHOWNORMAL, ewNoWait, err);
    { Open Default apps so the user can pick "Agent Browser" right away (Windows
      does not allow setting the default programmatically). }
    ShellExec('open', 'ms-settings:defaultapps', '', '', SW_SHOWNORMAL, ewNoWait, err);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  rc: Integer;
  cleanup: String;
begin
  if CurUninstallStep = usUninstall then begin
    { Before files are removed: stop the broker + agent browser, reverse the
      default-browser registration, and delete the broker's runtime data - but
      KEEP the agent browser profile (your logins). Run the shipped script while
      it still exists (the program folder is deleted right after this step). }
    cleanup := ExpandConstant('{app}\broker\install\uninstall-cleanup.ps1');
    if FileExists(cleanup) then
      Exec('powershell.exe',
        '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + cleanup + '"',
        '', SW_HIDE, ewWaitUntilTerminated, rc);
  end;
  if CurUninstallStep = usPostUninstall then begin
    { Belt-and-suspenders in case the cleanup script was missing: new + legacy
      registry keys and shortcuts. The agent profile is never touched. }
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\BrowserIntegrationURL');
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\BrowserIntegrationHTM');
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Clients\StartMenuInternet\BrowserIntegration');
    RegDeleteValue(HKCU, 'Software\RegisteredApplications', 'BrowserIntegration');
    DeleteFile(ExpandConstant('{userprograms}\Agent Browser.lnk'));
    DeleteFile(ExpandConstant('{userdesktop}\Agent Browser.lnk'));
    DeleteFile(ExpandConstant('{userdesktop}\Browser-Integration (1).lnk'));
    DeleteFile(ExpandConstant('{userdesktop}\Browser-Integration (2).lnk'));
    DeleteFile(ExpandConstant('{userdesktop}\Browser-Integration (3).lnk'));
  end;
end;
