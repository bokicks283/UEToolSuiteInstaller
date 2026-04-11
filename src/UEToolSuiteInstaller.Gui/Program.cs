using System.Diagnostics;
using System.Text;

namespace UEToolSuiteInstaller.Gui;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new InstallerForm());
    }
}

internal sealed class InstallerForm : Form
{
    private readonly TextBox projectPathTextBox = new();
    private readonly Button browseButton = new();
    private readonly Button installButton = new();
    private readonly CheckBox runInitCheckBox = new();
    private readonly CheckBox skipLfsPullCheckBox = new();
    private readonly CheckBox skipUnrealSyncCheckBox = new();
    private readonly CheckBox installAliasesCheckBox = new();
    private readonly CheckBox noBackupCheckBox = new();
    private readonly TextBox logTextBox = new();
    private readonly Label statusLabel = new();
    private CancellationTokenSource? installCancellation;

    public InstallerForm()
    {
        Text = "UE Tool Suite Installer";
        Width = 860;
        Height = 640;
        MinimumSize = new Size(780, 560);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10F);
        BackColor = Color.FromArgb(248, 249, 251);

        BuildLayout();
    }

    private void BuildLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 6,
            Padding = new Padding(24),
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var title = new Label
        {
            Text = "Install UE Tool Suite",
            AutoSize = true,
            Font = new Font("Segoe UI Semibold", 20F),
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 0, 0, 6),
        };
        root.Controls.Add(title);

        var subtitle = new Label
        {
            Text = "Choose a UE 5 .uproject file. The installer will update managed tool-suite paths and preserve project-specific Git ignore/attribute rules.",
            AutoSize = true,
            MaximumSize = new Size(780, 0),
            ForeColor = Color.FromArgb(72, 79, 96),
            Margin = new Padding(0, 0, 0, 20),
        };
        root.Controls.Add(subtitle);

        var pickerPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 2,
            Margin = new Padding(0, 0, 0, 16),
        };
        pickerPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        pickerPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        pickerPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        pickerPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var pickerLabel = new Label
        {
            Text = "Project",
            AutoSize = true,
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 0, 0, 6),
        };
        pickerPanel.Controls.Add(pickerLabel, 0, 0);
        pickerPanel.SetColumnSpan(pickerLabel, 2);

        projectPathTextBox.Dock = DockStyle.Fill;
        projectPathTextBox.ReadOnly = true;
        projectPathTextBox.PlaceholderText = "Select a .uproject file...";
        projectPathTextBox.Margin = new Padding(0, 0, 10, 0);
        pickerPanel.Controls.Add(projectPathTextBox, 0, 1);

        browseButton.Text = "Browse...";
        browseButton.AutoSize = true;
        browseButton.Height = projectPathTextBox.Height;
        browseButton.Click += (_, _) => BrowseForProject();
        pickerPanel.Controls.Add(browseButton, 1, 1);
        root.Controls.Add(pickerPanel);

        var optionsPanel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true,
            WrapContents = false,
            Margin = new Padding(0, 0, 0, 16),
        };

        runInitCheckBox.Text = "Run repo initialization after install";
        runInitCheckBox.Checked = true;
        runInitCheckBox.AutoSize = true;

        skipLfsPullCheckBox.Text = "Skip Git LFS pull during init";
        skipLfsPullCheckBox.Checked = true;
        skipLfsPullCheckBox.AutoSize = true;

        skipUnrealSyncCheckBox.Text = "Skip first Unreal sync during init";
        skipUnrealSyncCheckBox.Checked = true;
        skipUnrealSyncCheckBox.AutoSize = true;

        installAliasesCheckBox.Text = "Install managed PowerShell shell aliases";
        installAliasesCheckBox.Checked = true;
        installAliasesCheckBox.AutoSize = true;

        noBackupCheckBox.Text = "Replace managed paths without backups";
        noBackupCheckBox.Checked = false;
        noBackupCheckBox.AutoSize = true;

        optionsPanel.Controls.Add(runInitCheckBox);
        optionsPanel.Controls.Add(skipLfsPullCheckBox);
        optionsPanel.Controls.Add(skipUnrealSyncCheckBox);
        optionsPanel.Controls.Add(installAliasesCheckBox);
        optionsPanel.Controls.Add(noBackupCheckBox);
        root.Controls.Add(optionsPanel);

        installButton.Text = "Install";
        installButton.AutoSize = true;
        installButton.Padding = new Padding(18, 7, 18, 7);
        installButton.BackColor = Color.FromArgb(31, 102, 214);
        installButton.ForeColor = Color.White;
        installButton.FlatStyle = FlatStyle.Flat;
        installButton.FlatAppearance.BorderSize = 0;
        installButton.Click += async (_, _) => await RunInstallAsync();
        root.Controls.Add(installButton);

        logTextBox.Multiline = true;
        logTextBox.ReadOnly = true;
        logTextBox.ScrollBars = ScrollBars.Vertical;
        logTextBox.BackColor = Color.FromArgb(20, 24, 33);
        logTextBox.ForeColor = Color.FromArgb(238, 241, 247);
        logTextBox.Font = new Font("Consolas", 9F);
        logTextBox.Dock = DockStyle.Fill;
        logTextBox.Margin = new Padding(0, 16, 0, 12);
        root.Controls.Add(logTextBox);

        statusLabel.Text = "Ready";
        statusLabel.AutoSize = true;
        statusLabel.ForeColor = Color.FromArgb(72, 79, 96);
        root.Controls.Add(statusLabel);

        Controls.Add(root);
    }

    private void BrowseForProject()
    {
        using var dialog = new OpenFileDialog
        {
            Title = "Choose Unreal Engine project",
            Filter = "Unreal Project (*.uproject)|*.uproject",
            CheckFileExists = true,
            Multiselect = false,
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            projectPathTextBox.Text = dialog.FileName;
            statusLabel.Text = "Ready";
        }
    }

    private async Task RunInstallAsync()
    {
        if (installCancellation is not null)
        {
            return;
        }

        var projectPath = projectPathTextBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(projectPath) || !File.Exists(projectPath))
        {
            MessageBox.Show(this, "Choose a valid .uproject file first.", "Project Required", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var targetRoot = Path.GetDirectoryName(projectPath);
        if (string.IsNullOrWhiteSpace(targetRoot) || !Directory.Exists(targetRoot))
        {
            MessageBox.Show(this, "Could not resolve the selected project folder.", "Project Required", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var installerRoot = FindInstallerRoot();
        if (installerRoot is null)
        {
            MessageBox.Show(this, "The bundled installer payload was not found. Rebuild the release package and try again.", "Installer Payload Missing", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        var pwshPath = FindCommandOnPath("pwsh.exe");
        if (pwshPath is null)
        {
            MessageBox.Show(this, "PowerShell 7 (pwsh.exe) is required. Install PowerShell 7 and run this installer again.", "PowerShell 7 Required", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        installCancellation = new CancellationTokenSource();
        installButton.Enabled = false;
        browseButton.Enabled = false;
        statusLabel.Text = "Installing...";
        logTextBox.Clear();
        var options = new InstallOptions(
            RunInit: runInitCheckBox.Checked,
            SkipLfsPull: skipLfsPullCheckBox.Checked,
            SkipUnrealSync: skipUnrealSyncCheckBox.Checked,
            InstallAliases: installAliasesCheckBox.Checked,
            NoBackup: noBackupCheckBox.Checked);

        try
        {
            var exitCode = await Task.Run(() => RunInstallerProcess(pwshPath, installerRoot, targetRoot, projectPath, options, installCancellation.Token));
            if (exitCode == 0)
            {
                statusLabel.Text = "Install complete";
                MessageBox.Show(this, "UE Tool Suite install completed.", "Install Complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                statusLabel.Text = $"Install failed with exit code {exitCode}";
                MessageBox.Show(this, $"Installer failed with exit code {exitCode}. Review the log for details.", "Install Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
        catch (Exception ex)
        {
            statusLabel.Text = "Install failed";
            AppendLog("ERROR: " + ex.Message);
            MessageBox.Show(this, ex.Message, "Install Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            installCancellation.Dispose();
            installCancellation = null;
            installButton.Enabled = true;
            browseButton.Enabled = true;
        }
    }

    private int RunInstallerProcess(string pwshPath, string installerRoot, string targetRoot, string projectPath, InstallOptions options, CancellationToken cancellationToken)
    {
        var scriptPath = Path.Combine(installerRoot, "Install-UEToolSuite.ps1");
        var args = new List<string>
        {
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            scriptPath,
            "-TargetRepoRoot",
            targetRoot,
            "-TargetUProjectPath",
            projectPath,
        };

        if (options.RunInit)
        {
            args.Add("-RunInit");
        }

        if (options.SkipLfsPull)
        {
            args.Add("-SkipLfsPull");
        }

        if (options.SkipUnrealSync)
        {
            args.Add("-SkipUnrealSync");
        }

        if (!options.InstallAliases)
        {
            args.Add("-SkipShellAliases");
        }

        if (options.NoBackup)
        {
            args.Add("-NoBackup");
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = pwshPath,
            WorkingDirectory = installerRoot,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };

        foreach (var arg in args)
        {
            startInfo.ArgumentList.Add(arg);
        }

        AppendLog("> " + pwshPath + " " + string.Join(" ", args.Select(QuoteForLog)));

        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        process.OutputDataReceived += (_, e) => { if (e.Data is not null) AppendLog(e.Data); };
        process.ErrorDataReceived += (_, e) => { if (e.Data is not null) AppendLog(e.Data); };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        process.WaitForExit();
        cancellationToken.ThrowIfCancellationRequested();
        return process.ExitCode;
    }

    private static string? FindInstallerRoot()
    {
        foreach (var candidate in EnumerateInstallerRootCandidates())
        {
            if (File.Exists(Path.Combine(candidate, "Install-UEToolSuite.ps1")) &&
                Directory.Exists(Path.Combine(candidate, "payload")))
            {
                return candidate;
            }
        }

        return null;
    }

    private static IEnumerable<string> EnumerateInstallerRootCandidates()
    {
        var baseDirectory = AppContext.BaseDirectory;
        yield return baseDirectory;
        yield return Directory.GetCurrentDirectory();

        var current = new DirectoryInfo(baseDirectory);
        for (var i = 0; i < 5 && current.Parent is not null; i++)
        {
            current = current.Parent;
            yield return current.FullName;
        }
    }

    private static string? FindCommandOnPath(string commandName)
    {
        var path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        foreach (var directory in path.Split(Path.PathSeparator))
        {
            if (string.IsNullOrWhiteSpace(directory))
            {
                continue;
            }

            var candidate = Path.Combine(directory.Trim(), commandName);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    private static string QuoteForLog(string value)
    {
        return value.Contains(' ') ? '"' + value.Replace("\"", "\\\"") + '"' : value;
    }

    private void AppendLog(string line)
    {
        if (InvokeRequired)
        {
            BeginInvoke(new Action<string>(AppendLog), line);
            return;
        }

        logTextBox.AppendText(line + Environment.NewLine);
    }
}

internal sealed record InstallOptions(
    bool RunInit,
    bool SkipLfsPull,
    bool SkipUnrealSync,
    bool InstallAliases,
    bool NoBackup);
