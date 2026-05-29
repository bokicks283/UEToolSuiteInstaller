using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;

namespace UEToolSuiteInstaller.Gui;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        try
        {
            Application.Run(new InstallerForm());
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"Installer UI failed to start.{Environment.NewLine}{Environment.NewLine}{ex.GetType().Name}: {ex.Message}",
                "UE Tool Suite Installer",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }
}

internal sealed class InstallerForm : Form
{
    private static readonly TimeSpan NoOutputTimeout = TimeSpan.FromMinutes(4);
    private static readonly TimeSpan MaxInstallDuration = TimeSpan.FromMinutes(60);
    private const string DefaultProgressMessage = "Waiting to start...";
    private const string DefaultWebsiteThemeId = "neutral";
    private const int MainPaneMinSize = 360;
    private const int LogPaneMinSize = 220;

    private readonly SplitContainer mainSplitContainer = new();
    private readonly Panel mainContentScrollPanel = new();
    private readonly TableLayoutPanel rootLayout = new();
    private readonly TextBox projectPathTextBox = new();
    private readonly Button browseButton = new();
    private readonly Button installButton = new();
    private readonly Button cancelButton = new();
    private readonly CheckBox showLogCheckBox = new();
    private readonly CheckBox showAdvancedOptionsCheckBox = new();
    private readonly CheckBox runInitCheckBox = new();
    private readonly CheckBox initNonInteractiveCheckBox = new();
    private readonly CheckBox skipLfsPullCheckBox = new();
    private readonly CheckBox skipUnrealSyncCheckBox = new();
    private readonly CheckBox skipShellAliasesCheckBox = new();
    private readonly CheckBox noBackupCheckBox = new();
    private readonly CheckBox skipDocsCheckBox = new();
    private readonly CheckBox skipWebsiteCheckBox = new();
    private readonly CheckBox adoptExistingWebsiteCheckBox = new();
    private readonly CheckBox skipTestsCheckBox = new();
    private readonly CheckBox skipAiToolsCheckBox = new();
    private readonly CheckBox skipArtSourceToolsCheckBox = new();
    private readonly CheckBox skipCodingStandardsToolsCheckBox = new();
    private readonly CheckBox skipOptionalToolSetupCheckBox = new();
    private readonly CheckBox skipDocsSetupCheckBox = new();
    private readonly CheckBox skipDocsNpmInstallCheckBox = new();
    private readonly CheckBox forceDocsNpmInstallCheckBox = new();
    private readonly CheckBox skipDocsBridgeInstallCheckBox = new();
    private readonly CheckBox noBuildCheckBox = new();
    private readonly CheckBox noRegenCheckBox = new();
    private readonly ComboBox websiteThemeComboBox = new();
    private readonly TextBox websiteLogoPathTextBox = new();
    private readonly Button browseWebsiteLogoButton = new();
    private readonly Button clearWebsiteLogoButton = new();
    private readonly Panel advancedOptionsPanel = new();
    private readonly ProgressBar installProgressBar = new();
    private readonly Label progressLabel = new();
    private readonly Label statusLabel = new();
    private readonly Panel logPanel = new();
    private readonly TextBox logTextBox = new();
    private readonly object outputStateLock = new();
    private readonly object processStateLock = new();

    private CancellationTokenSource? installCancellation;
    private Process? activeProcess;
    private int currentProgress;
    private long lastOutputTicksUtc;
    private string lastOutputLine = string.Empty;
    private bool logPaneHasBeenShown;
    private List<WebsiteThemeOption> websiteThemeOptions = new();

    public InstallerForm()
    {
        Text = "UE Tool Suite Installer";
        Width = 1080;
        Height = 760;
        MinimumSize = new Size(920, 640);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10F);
        BackColor = Color.FromArgb(248, 249, 251);

        ConfigureWindowIcon();
        BuildLayout();
        LoadWebsiteThemeOptions();
        WireDependencyEvents();
        ApplyOptionDependencies();
        Shown += (_, _) => ApplySplitterMinimums();
        SizeChanged += (_, _) => ApplySplitterMinimums();
    }

    private void ConfigureWindowIcon()
    {
        var icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        if (icon is not null)
        {
            Icon = icon;
        }
    }

    private void BuildLayout()
    {
        mainSplitContainer.Dock = DockStyle.Fill;
        mainSplitContainer.Orientation = Orientation.Horizontal;
        mainSplitContainer.BorderStyle = BorderStyle.None;
        mainSplitContainer.SplitterWidth = 8;
        mainSplitContainer.Panel1MinSize = 0;
        mainSplitContainer.Panel2MinSize = 0;
        mainSplitContainer.Panel2Collapsed = true;
        Controls.Add(mainSplitContainer);

        mainContentScrollPanel.Dock = DockStyle.Fill;
        mainContentScrollPanel.AutoScroll = true;
        mainContentScrollPanel.Padding = new Padding(0);
        mainSplitContainer.Panel1.Controls.Add(mainContentScrollPanel);

        rootLayout.Dock = DockStyle.Top;
        rootLayout.AutoSize = true;
        rootLayout.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        rootLayout.ColumnCount = 1;
        rootLayout.RowCount = 8;
        rootLayout.Padding = new Padding(24);
        rootLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        rootLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        rootLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        rootLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        rootLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        rootLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        rootLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        rootLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        mainContentScrollPanel.Controls.Add(rootLayout);

        var title = new Label
        {
            Text = "Install UE Tool Suite",
            AutoSize = true,
            Font = new Font("Segoe UI Semibold", 20F),
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 0, 0, 6),
        };
        rootLayout.Controls.Add(title, 0, 0);

        var subtitle = new Label
        {
            Text = "Choose a UE 5 .uproject file. The installer updates managed suite paths while preserving project-specific Git ignore/attribute content.",
            AutoSize = true,
            MaximumSize = new Size(980, 0),
            ForeColor = Color.FromArgb(72, 79, 96),
            Margin = new Padding(0, 0, 0, 20),
        };
        rootLayout.Controls.Add(subtitle, 0, 1);

        var pickerPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 2,
            Margin = new Padding(0, 0, 0, 14),
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
        browseButton.Click += (_, _) => BrowseForProject();
        pickerPanel.Controls.Add(browseButton, 1, 1);
        rootLayout.Controls.Add(pickerPanel, 0, 2);

        var optionsContainer = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            Margin = new Padding(0, 0, 0, 14),
        };
        optionsContainer.AutoSize = true;
        optionsContainer.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        optionsContainer.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        optionsContainer.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        optionsContainer.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        optionsContainer.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var coreOptionsLabel = new Label
        {
            Text = "Core options",
            AutoSize = true,
            Font = new Font(Font, FontStyle.Bold),
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 0, 0, 6),
        };
        optionsContainer.Controls.Add(coreOptionsLabel, 0, 0);

        var coreOptionsFlow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            WrapContents = false,
            Margin = new Padding(0, 0, 0, 8),
        };

        ConfigureOptionCheckBox(runInitCheckBox, "Run repo initialization after install", true);
        ConfigureOptionCheckBox(initNonInteractiveCheckBox, "Init non-interactive mode", true);
        ConfigureOptionCheckBox(skipLfsPullCheckBox, "Skip Git LFS pull during init", true);
        ConfigureOptionCheckBox(skipUnrealSyncCheckBox, "Skip first Unreal sync during init", true);
        ConfigureOptionCheckBox(skipShellAliasesCheckBox, "Skip PowerShell shell alias install during init (-SkipShellAliases)", false);
        ConfigureOptionCheckBox(noBackupCheckBox, "Replace managed paths without backups", false);

        coreOptionsFlow.Controls.Add(runInitCheckBox);
        coreOptionsFlow.Controls.Add(initNonInteractiveCheckBox);
        coreOptionsFlow.Controls.Add(skipLfsPullCheckBox);
        coreOptionsFlow.Controls.Add(skipUnrealSyncCheckBox);
        coreOptionsFlow.Controls.Add(skipShellAliasesCheckBox);
        coreOptionsFlow.Controls.Add(noBackupCheckBox);
        coreOptionsFlow.Controls.Add(BuildDocsBrandingPanel());
        optionsContainer.Controls.Add(coreOptionsFlow, 0, 1);

        ConfigureOptionCheckBox(showAdvancedOptionsCheckBox, "Show advanced options", false);
        showAdvancedOptionsCheckBox.Margin = new Padding(0, 0, 0, 8);
        showAdvancedOptionsCheckBox.CheckedChanged += (_, _) =>
        {
            advancedOptionsPanel.Visible = showAdvancedOptionsCheckBox.Checked;
        };
        optionsContainer.Controls.Add(showAdvancedOptionsCheckBox, 0, 2);

        BuildAdvancedOptionsPanel();
        advancedOptionsPanel.Visible = false;
        optionsContainer.Controls.Add(advancedOptionsPanel, 0, 3);
        rootLayout.Controls.Add(optionsContainer, 0, 3);

        var actionPanel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            AutoSize = true,
            WrapContents = false,
            Margin = new Padding(0, 0, 0, 12),
        };

        installButton.Text = "Install";
        installButton.AutoSize = true;
        installButton.Padding = new Padding(18, 7, 18, 7);
        installButton.BackColor = Color.FromArgb(31, 102, 214);
        installButton.ForeColor = Color.White;
        installButton.FlatStyle = FlatStyle.Flat;
        installButton.FlatAppearance.BorderSize = 0;
        installButton.Click += async (_, _) => await RunInstallAsync();
        actionPanel.Controls.Add(installButton);

        cancelButton.Text = "Cancel";
        cancelButton.AutoSize = true;
        cancelButton.Padding = new Padding(18, 7, 18, 7);
        cancelButton.Enabled = false;
        cancelButton.Click += (_, _) => CancelInstall();
        actionPanel.Controls.Add(cancelButton);

        ConfigureOptionCheckBox(showLogCheckBox, "Show terminal output", false);
        showLogCheckBox.Margin = new Padding(16, 11, 0, 0);
        showLogCheckBox.CheckedChanged += (_, _) => SetLogVisibility(showLogCheckBox.Checked);
        actionPanel.Controls.Add(showLogCheckBox);
        rootLayout.Controls.Add(actionPanel, 0, 4);

        var progressPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            Margin = new Padding(0, 0, 0, 10),
        };
        progressPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        progressPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        installProgressBar.Dock = DockStyle.Fill;
        installProgressBar.Minimum = 0;
        installProgressBar.Maximum = 100;
        installProgressBar.Style = ProgressBarStyle.Continuous;
        installProgressBar.Height = 18;
        progressPanel.Controls.Add(installProgressBar, 0, 0);

        progressLabel.Text = DefaultProgressMessage;
        progressLabel.AutoSize = true;
        progressLabel.ForeColor = Color.FromArgb(72, 79, 96);
        progressLabel.Margin = new Padding(0, 6, 0, 0);
        progressPanel.Controls.Add(progressLabel, 0, 1);
        rootLayout.Controls.Add(progressPanel, 0, 5);

        statusLabel.Text = "Ready";
        statusLabel.AutoSize = true;
        statusLabel.ForeColor = Color.FromArgb(72, 79, 96);
        rootLayout.Controls.Add(statusLabel, 0, 7);

        logPanel.Dock = DockStyle.Fill;
        logPanel.Padding = new Padding(16, 12, 16, 12);

        logTextBox.Multiline = true;
        logTextBox.ReadOnly = true;
        logTextBox.WordWrap = false;
        logTextBox.ScrollBars = ScrollBars.Both;
        logTextBox.BackColor = Color.FromArgb(20, 24, 33);
        logTextBox.ForeColor = Color.FromArgb(238, 241, 247);
        logTextBox.Font = new Font("Consolas", 10.5F);
        logTextBox.Dock = DockStyle.Fill;

        logPanel.Controls.Add(logTextBox);
        mainSplitContainer.Panel2.Controls.Add(logPanel);

        SetLogVisibility(false);
        SetProgress(0, DefaultProgressMessage, allowDecrease: true);
    }

    private void ApplySplitterMinimums()
    {
        if (mainSplitContainer.IsDisposed)
        {
            return;
        }

        var primaryLength = mainSplitContainer.Orientation == Orientation.Horizontal
            ? mainSplitContainer.ClientSize.Height
            : mainSplitContainer.ClientSize.Width;
        var available = Math.Max(0, primaryLength - mainSplitContainer.SplitterWidth);
        var targetPanel2Min = mainSplitContainer.Panel2Collapsed ? 0 : LogPaneMinSize;
        var targetPanel1Min = Math.Max(0, Math.Min(MainPaneMinSize, available - targetPanel2Min));

        if (mainSplitContainer.Panel2MinSize != targetPanel2Min)
        {
            mainSplitContainer.Panel2MinSize = targetPanel2Min;
        }

        if (mainSplitContainer.Panel1MinSize != targetPanel1Min)
        {
            mainSplitContainer.Panel1MinSize = targetPanel1Min;
        }
    }

    private Control BuildDocsBrandingPanel()
    {
        var panel = new TableLayoutPanel
        {
            ColumnCount = 4,
            RowCount = 3,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = new Padding(0, 8, 0, 0),
            Padding = new Padding(10, 10, 10, 8),
            BackColor = Color.FromArgb(244, 246, 250),
        };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var headerLabel = new Label
        {
            Text = "Docs website branding",
            AutoSize = true,
            Font = new Font("Segoe UI", 9.5F, FontStyle.Bold),
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 0, 0, 6),
        };
        panel.Controls.Add(headerLabel, 0, 0);
        panel.SetColumnSpan(headerLabel, 4);

        var themeLabel = new Label
        {
            Text = "Theme",
            AutoSize = true,
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 6, 10, 0),
        };
        panel.Controls.Add(themeLabel, 0, 1);

        websiteThemeComboBox.DropDownStyle = ComboBoxStyle.DropDownList;
        websiteThemeComboBox.Width = 360;
        websiteThemeComboBox.Margin = new Padding(0, 2, 10, 0);
        panel.Controls.Add(websiteThemeComboBox, 1, 1);
        panel.SetColumnSpan(websiteThemeComboBox, 3);

        var logoLabel = new Label
        {
            Text = "Logo (.svg/.png)",
            AutoSize = true,
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 8, 10, 0),
        };
        panel.Controls.Add(logoLabel, 0, 2);

        websiteLogoPathTextBox.ReadOnly = true;
        websiteLogoPathTextBox.PlaceholderText = "Optional custom project logo...";
        websiteLogoPathTextBox.Margin = new Padding(0, 4, 10, 0);
        websiteLogoPathTextBox.Width = 420;
        panel.Controls.Add(websiteLogoPathTextBox, 1, 2);

        browseWebsiteLogoButton.Text = "Browse...";
        browseWebsiteLogoButton.AutoSize = true;
        browseWebsiteLogoButton.Margin = new Padding(0, 3, 6, 0);
        browseWebsiteLogoButton.Click += (_, _) => BrowseForWebsiteLogo();
        panel.Controls.Add(browseWebsiteLogoButton, 2, 2);

        clearWebsiteLogoButton.Text = "Clear";
        clearWebsiteLogoButton.AutoSize = true;
        clearWebsiteLogoButton.Margin = new Padding(0, 3, 0, 0);
        clearWebsiteLogoButton.Click += (_, _) =>
        {
            websiteLogoPathTextBox.Text = string.Empty;
            statusLabel.Text = "Ready";
        };
        panel.Controls.Add(clearWebsiteLogoButton, 3, 2);

        return panel;
    }

    private void BrowseForWebsiteLogo()
    {
        using var dialog = new OpenFileDialog
        {
            Title = "Choose website logo asset",
            Filter = "Logo files (*.svg;*.png)|*.svg;*.png",
            CheckFileExists = true,
            Multiselect = false,
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            websiteLogoPathTextBox.Text = dialog.FileName;
            statusLabel.Text = "Ready";
        }
    }

    private void BuildAdvancedOptionsPanel()
    {
        advancedOptionsPanel.Dock = DockStyle.Fill;
        advancedOptionsPanel.Padding = new Padding(10, 8, 10, 8);
        advancedOptionsPanel.BorderStyle = BorderStyle.FixedSingle;
        advancedOptionsPanel.BackColor = Color.FromArgb(244, 246, 250);
        advancedOptionsPanel.Margin = new Padding(0, 0, 0, 0);
        advancedOptionsPanel.AutoSize = true;
        advancedOptionsPanel.AutoSizeMode = AutoSizeMode.GrowAndShrink;

        var advancedLayout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = new Padding(0),
        };
        advancedLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        advancedLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));

        var payloadColumn = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            WrapContents = false,
            Margin = new Padding(0, 0, 12, 0),
        };
        payloadColumn.Controls.Add(CreateSectionLabel("Payload scope"));
        ConfigureOptionCheckBox(skipDocsCheckBox, "Skip Docs payload", false);
        ConfigureOptionCheckBox(skipWebsiteCheckBox, "Skip website payload", false);
        ConfigureOptionCheckBox(adoptExistingWebsiteCheckBox, "Adopt existing unmanaged website", false);
        ConfigureOptionCheckBox(skipTestsCheckBox, "Skip payload test scripts", false);
        ConfigureOptionCheckBox(skipAiToolsCheckBox, "Skip AI docs/tooling payload", false);
        ConfigureOptionCheckBox(skipArtSourceToolsCheckBox, "Skip ArtSource tooling payload", false);
        ConfigureOptionCheckBox(skipCodingStandardsToolsCheckBox, "Skip coding standards payload", false);
        payloadColumn.Controls.Add(skipDocsCheckBox);
        payloadColumn.Controls.Add(skipWebsiteCheckBox);
        payloadColumn.Controls.Add(adoptExistingWebsiteCheckBox);
        payloadColumn.Controls.Add(skipTestsCheckBox);
        payloadColumn.Controls.Add(skipAiToolsCheckBox);
        payloadColumn.Controls.Add(skipArtSourceToolsCheckBox);
        payloadColumn.Controls.Add(skipCodingStandardsToolsCheckBox);

        var initColumn = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            WrapContents = false,
            Margin = new Padding(12, 0, 0, 0),
        };
        initColumn.Controls.Add(CreateSectionLabel("Init and build advanced"));
        ConfigureOptionCheckBox(skipOptionalToolSetupCheckBox, "Skip optional tool setup during init", false);
        ConfigureOptionCheckBox(skipDocsSetupCheckBox, "Skip docs setup during init", false);
        ConfigureOptionCheckBox(skipDocsNpmInstallCheckBox, "Skip docs npm install during init", false);
        ConfigureOptionCheckBox(forceDocsNpmInstallCheckBox, "Force docs npm install during init", false);
        ConfigureOptionCheckBox(skipDocsBridgeInstallCheckBox, "Skip docs VS Code bridge install", false);
        ConfigureOptionCheckBox(noBuildCheckBox, "Run init build flow without compile step (-NoBuild)", false);
        ConfigureOptionCheckBox(noRegenCheckBox, "Run init build flow without regen step (-NoRegen)", false);
        initColumn.Controls.Add(skipOptionalToolSetupCheckBox);
        initColumn.Controls.Add(skipDocsSetupCheckBox);
        initColumn.Controls.Add(skipDocsNpmInstallCheckBox);
        initColumn.Controls.Add(forceDocsNpmInstallCheckBox);
        initColumn.Controls.Add(skipDocsBridgeInstallCheckBox);
        initColumn.Controls.Add(noBuildCheckBox);
        initColumn.Controls.Add(noRegenCheckBox);

        var noteLabel = new Label
        {
            AutoSize = true,
            ForeColor = Color.FromArgb(82, 89, 106),
            Margin = new Padding(0, 6, 0, 0),
            Text = "Internal maintenance flags (PayloadRoot, NoLegacyCleanup) stay CLI-only.",
        };
        initColumn.Controls.Add(noteLabel);

        advancedLayout.Controls.Add(payloadColumn, 0, 0);
        advancedLayout.Controls.Add(initColumn, 1, 0);
        advancedOptionsPanel.Controls.Add(advancedLayout);
    }

    private static Label CreateSectionLabel(string text)
    {
        return new Label
        {
            Text = text,
            AutoSize = true,
            Font = new Font("Segoe UI", 9.5F, FontStyle.Bold),
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 0, 0, 6),
        };
    }

    private static void ConfigureOptionCheckBox(CheckBox control, string text, bool isChecked)
    {
        control.Text = text;
        control.Checked = isChecked;
        control.AutoSize = true;
        control.Margin = new Padding(0, 0, 0, 5);
    }

    private void WireDependencyEvents()
    {
        runInitCheckBox.CheckedChanged += (_, _) => ApplyOptionDependencies();
        skipWebsiteCheckBox.CheckedChanged += (_, _) => ApplyOptionDependencies();
        skipDocsSetupCheckBox.CheckedChanged += (_, _) => ApplyOptionDependencies();
        skipUnrealSyncCheckBox.CheckedChanged += (_, _) => ApplyOptionDependencies();
        skipDocsNpmInstallCheckBox.CheckedChanged += (_, _) =>
        {
            if (skipDocsNpmInstallCheckBox.Checked)
            {
                forceDocsNpmInstallCheckBox.Checked = false;
            }
            ApplyOptionDependencies();
        };
        forceDocsNpmInstallCheckBox.CheckedChanged += (_, _) =>
        {
            if (forceDocsNpmInstallCheckBox.Checked)
            {
                skipDocsNpmInstallCheckBox.Checked = false;
            }
            ApplyOptionDependencies();
        };
    }

    private void ApplyOptionDependencies()
    {
        if (installCancellation is not null)
        {
            return;
        }

        var websiteEnabled = !skipWebsiteCheckBox.Checked;
        websiteThemeComboBox.Enabled = websiteEnabled;
        websiteLogoPathTextBox.Enabled = websiteEnabled;
        browseWebsiteLogoButton.Enabled = websiteEnabled;
        clearWebsiteLogoButton.Enabled = websiteEnabled;
        adoptExistingWebsiteCheckBox.Enabled = websiteEnabled;
        if (!websiteEnabled)
        {
            adoptExistingWebsiteCheckBox.Checked = false;
        }

        var initEnabled = runInitCheckBox.Checked;
        initNonInteractiveCheckBox.Enabled = initEnabled;
        skipLfsPullCheckBox.Enabled = initEnabled;
        skipUnrealSyncCheckBox.Enabled = initEnabled;
        skipShellAliasesCheckBox.Enabled = initEnabled;
        skipOptionalToolSetupCheckBox.Enabled = initEnabled;
        skipDocsSetupCheckBox.Enabled = initEnabled;

        var docsSubOptionsEnabled = initEnabled && !skipDocsSetupCheckBox.Checked;
        skipDocsNpmInstallCheckBox.Enabled = docsSubOptionsEnabled;
        forceDocsNpmInstallCheckBox.Enabled = docsSubOptionsEnabled;
        skipDocsBridgeInstallCheckBox.Enabled = docsSubOptionsEnabled;

        var buildOptionEnabled = initEnabled && !skipUnrealSyncCheckBox.Checked;
        noBuildCheckBox.Enabled = buildOptionEnabled;
        noRegenCheckBox.Enabled = buildOptionEnabled;
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
        SetInstallUiState(enabled: false);
        statusLabel.Text = "Installing...";
        logTextBox.Clear();
        SetProgress(3, "Preparing installer command...", allowDecrease: true);

        var options = CollectInstallOptions();

        try
        {
            var exitCode = await Task.Run(() => RunInstallerProcess(pwshPath, installerRoot, targetRoot, projectPath, options, installCancellation.Token));
            if (exitCode == 0)
            {
                SetProgress(100, "Install complete");
                statusLabel.Text = "Install complete";
                var choice = MessageBox.Show(
                    this,
                    "UE Tool Suite install completed.\n\nInstall in another project?",
                    "Install Complete",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question);

                if (choice == DialogResult.Yes)
                {
                    ResetForNextInstall();
                }
                else
                {
                    Close();
                    return;
                }
            }
            else
            {
                EnsureLogVisibleOnFailure();
                statusLabel.Text = $"Install failed with exit code {exitCode}";
                SetProgress(100, "Install failed");
                MessageBox.Show(this, $"Installer failed with exit code {exitCode}. Review terminal output for the failure stage and retry.", "Install Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
        catch (OperationCanceledException)
        {
            EnsureLogVisibleOnFailure();
            statusLabel.Text = "Install canceled";
            SetProgress(100, "Install canceled");
            AppendLog("[Installer GUI] Install canceled by user.");
            MessageBox.Show(this, "Install canceled. Review terminal output to confirm where the process stopped.", "Install Canceled", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        catch (TimeoutException ex)
        {
            EnsureLogVisibleOnFailure();
            statusLabel.Text = "Install timed out";
            AppendLog("ERROR: " + ex.Message);
            SetProgress(100, "Install timed out");
            MessageBox.Show(this, ex.Message, "Install Timed Out", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        catch (Exception ex)
        {
            EnsureLogVisibleOnFailure();
            statusLabel.Text = "Install failed";
            AppendLog("ERROR: " + ex.Message);
            SetProgress(100, "Install failed");
            MessageBox.Show(this, ex.Message, "Install Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            installCancellation?.Dispose();
            installCancellation = null;
            if (!IsDisposed && !Disposing)
            {
                SetInstallUiState(enabled: true);
            }
        }
    }

    private void CancelInstall()
    {
        if (installCancellation is null || installCancellation.IsCancellationRequested)
        {
            return;
        }

        statusLabel.Text = "Cancelling install...";
        cancelButton.Enabled = false;
        AppendLog("[Installer GUI] Cancellation requested...");
        installCancellation.Cancel();

        lock (processStateLock)
        {
            if (activeProcess is not null)
            {
                TryKillProcessTree(activeProcess);
            }
        }
    }

    private InstallOptions CollectInstallOptions()
    {
        var runInit = runInitCheckBox.Checked;
        var skipDocsSetup = runInit && skipDocsSetupCheckBox.Checked;
        var skipUnrealSync = runInit && skipUnrealSyncCheckBox.Checked;
        var selectedTheme = (websiteThemeComboBox.SelectedItem as WebsiteThemeOption)?.Id ?? DefaultWebsiteThemeId;
        var logoPath = string.IsNullOrWhiteSpace(websiteLogoPathTextBox.Text) ? null : websiteLogoPathTextBox.Text.Trim();

        return new InstallOptions(
            RunInit: runInit,
            InitNonInteractive: runInit && initNonInteractiveCheckBox.Checked,
            SkipLfsPull: runInit && skipLfsPullCheckBox.Checked,
            SkipShellAliases: runInit && skipShellAliasesCheckBox.Checked,
            SkipOptionalToolSetup: runInit && skipOptionalToolSetupCheckBox.Checked,
            SkipDocsSetup: skipDocsSetup,
            SkipDocsNpmInstall: runInit && !skipDocsSetup && skipDocsNpmInstallCheckBox.Checked,
            ForceDocsNpmInstall: runInit && !skipDocsSetup && forceDocsNpmInstallCheckBox.Checked,
            SkipDocsBridgeInstall: runInit && !skipDocsSetup && skipDocsBridgeInstallCheckBox.Checked,
            SkipUnrealSync: skipUnrealSync,
            NoBuild: runInit && !skipUnrealSync && noBuildCheckBox.Checked,
            NoRegen: runInit && !skipUnrealSync && noRegenCheckBox.Checked,
            SkipDocs: skipDocsCheckBox.Checked,
            SkipWebsite: skipWebsiteCheckBox.Checked,
            AdoptExistingWebsite: !skipWebsiteCheckBox.Checked && adoptExistingWebsiteCheckBox.Checked,
            SkipTests: skipTestsCheckBox.Checked,
            SkipAITools: skipAiToolsCheckBox.Checked,
            SkipArtSourceTools: skipArtSourceToolsCheckBox.Checked,
            SkipCodingStandardsTools: skipCodingStandardsToolsCheckBox.Checked,
            NoBackup: noBackupCheckBox.Checked,
            WebsiteTheme: selectedTheme,
            WebsiteLogoPath: logoPath);
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

        if (options.SkipDocs) { args.Add("-SkipDocs"); }
        if (options.SkipWebsite) { args.Add("-SkipWebsite"); }
        if (options.SkipTests) { args.Add("-SkipTests"); }
        if (options.SkipAITools) { args.Add("-SkipAITools"); }
        if (options.SkipArtSourceTools) { args.Add("-SkipArtSourceTools"); }
        if (options.SkipCodingStandardsTools) { args.Add("-SkipCodingStandardsTools"); }
        if (options.NoBackup) { args.Add("-NoBackup"); }
        if (!options.SkipWebsite)
        {
            if (options.AdoptExistingWebsite) { args.Add("-AdoptExistingWebsite"); }
            args.Add("-WebsiteTheme");
            args.Add(string.IsNullOrWhiteSpace(options.WebsiteTheme) ? DefaultWebsiteThemeId : options.WebsiteTheme!);
            if (!string.IsNullOrWhiteSpace(options.WebsiteLogoPath))
            {
                args.Add("-WebsiteLogoPath");
                args.Add(options.WebsiteLogoPath!);
            }
        }

        if (options.RunInit)
        {
            args.Add("-RunInit");
            if (options.InitNonInteractive) { args.Add("-InitNonInteractive"); }
            if (options.SkipLfsPull) { args.Add("-SkipLfsPull"); }
            if (options.SkipShellAliases) { args.Add("-SkipShellAliases"); }
            if (options.SkipOptionalToolSetup) { args.Add("-SkipOptionalToolSetup"); }
            if (options.SkipDocsSetup) { args.Add("-SkipDocsSetup"); }
            if (options.SkipDocsNpmInstall) { args.Add("-SkipDocsNpmInstall"); }
            if (options.ForceDocsNpmInstall) { args.Add("-ForceDocsNpmInstall"); }
            if (options.SkipDocsBridgeInstall) { args.Add("-SkipDocsBridgeInstall"); }
            if (options.SkipUnrealSync) { args.Add("-SkipUnrealSync"); }
            if (options.NoBuild) { args.Add("-NoBuild"); }
            if (options.NoRegen) { args.Add("-NoRegen"); }
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

        SetLastOutputLine(string.Empty);
        Interlocked.Exchange(ref lastOutputTicksUtc, DateTime.UtcNow.Ticks);
        SetProgress(5, "Starting installer process...");
        AppendLog("> " + pwshPath + " " + string.Join(" ", args.Select(QuoteForLog)));

        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        lock (processStateLock)
        {
            activeProcess = process;
        }

        try
        {
            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data is not null)
                {
                    HandleProcessOutputLine(e.Data);
                }
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data is not null)
                {
                    HandleProcessOutputLine(e.Data);
                }
            };

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            SetProgress(8, "Installer started...");

            var startedAtUtc = DateTime.UtcNow;
            while (!process.WaitForExit(500))
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    TryKillProcessTree(process);
                    cancellationToken.ThrowIfCancellationRequested();
                }

                var nowUtc = DateTime.UtcNow;
                var idleSinceOutput = nowUtc - new DateTime(Interlocked.Read(ref lastOutputTicksUtc), DateTimeKind.Utc);
                if (idleSinceOutput > NoOutputTimeout)
                {
                    TryKillProcessTree(process);
                    var lastLine = GetLastOutputLine();
                    var lastDetail = string.IsNullOrWhiteSpace(lastLine) ? "<no output received>" : lastLine;
                    throw new TimeoutException($"Installer produced no output for {NoOutputTimeout.TotalMinutes:N0} minutes and was terminated. Last output: {lastDetail}. Enable terminal output and retry.");
                }

                if (nowUtc - startedAtUtc > MaxInstallDuration)
                {
                    TryKillProcessTree(process);
                    throw new TimeoutException($"Installer exceeded the maximum runtime limit of {MaxInstallDuration.TotalMinutes:N0} minutes and was terminated.");
                }
            }

            process.WaitForExit();
            cancellationToken.ThrowIfCancellationRequested();
            return process.ExitCode;
        }
        finally
        {
            lock (processStateLock)
            {
                activeProcess = null;
            }
        }
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

    private void LoadWebsiteThemeOptions()
    {
        var fallback = new List<WebsiteThemeOption>
        {
            new(DefaultWebsiteThemeId, "Neutral Slate", "Balanced neutral docs theme with restrained contrast."),
        };

        websiteThemeOptions = fallback;
        var defaultThemeId = DefaultWebsiteThemeId;

        try
        {
            var installerRoot = FindInstallerRoot();
            if (!string.IsNullOrWhiteSpace(installerRoot))
            {
                var catalogPath = Path.Combine(installerRoot, "payload", "website", "theme-presets", "theme-catalog.json");
                if (File.Exists(catalogPath))
                {
                    var catalogRaw = File.ReadAllText(catalogPath, Encoding.UTF8);
                    var catalog = JsonSerializer.Deserialize<WebsiteThemeCatalog>(catalogRaw, new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true,
                    });

                    if (catalog?.Themes is { Count: > 0 })
                    {
                        var parsed = new List<WebsiteThemeOption>();
                        foreach (var theme in catalog.Themes)
                        {
                            if (theme is null || string.IsNullOrWhiteSpace(theme.Id))
                            {
                                continue;
                            }

                            parsed.Add(new WebsiteThemeOption(
                                theme.Id.Trim(),
                                string.IsNullOrWhiteSpace(theme.Label) ? theme.Id.Trim() : theme.Label.Trim(),
                                theme.Description?.Trim() ?? string.Empty));
                        }

                        if (parsed.Count > 0)
                        {
                            websiteThemeOptions = parsed;
                            if (!string.IsNullOrWhiteSpace(catalog.DefaultTheme))
                            {
                                defaultThemeId = catalog.DefaultTheme.Trim();
                            }
                        }
                    }
                }
            }
        }
        catch
        {
            websiteThemeOptions = fallback;
            defaultThemeId = DefaultWebsiteThemeId;
        }

        websiteThemeComboBox.BeginUpdate();
        try
        {
            websiteThemeComboBox.Items.Clear();
            foreach (var option in websiteThemeOptions)
            {
                websiteThemeComboBox.Items.Add(option);
            }

            if (websiteThemeComboBox.Items.Count == 0)
            {
                websiteThemeComboBox.Items.Add(fallback[0]);
                websiteThemeOptions = fallback;
            }

            var selectedOption = websiteThemeOptions.FirstOrDefault(option =>
                option.Id.Equals(defaultThemeId, StringComparison.OrdinalIgnoreCase));
            selectedOption ??= websiteThemeOptions[0];
            websiteThemeComboBox.SelectedItem = selectedOption;
        }
        finally
        {
            websiteThemeComboBox.EndUpdate();
        }
    }

    private static string QuoteForLog(string value)
    {
        return value.Contains(' ') ? '"' + value.Replace("\"", "\\\"") + '"' : value;
    }

    private void HandleProcessOutputLine(string line)
    {
        SetLastOutputLine(line);
        Interlocked.Exchange(ref lastOutputTicksUtc, DateTime.UtcNow.Ticks);
        AppendLog(line);
        UpdateProgressFromOutput(line);
    }

    private void UpdateProgressFromOutput(string line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return;
        }

        if (line.Contains("[UE Tool Suite Installer] Target project:", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(12, "Resolving target project...");
            return;
        }

        if (line.Contains("[UE Tool Suite Installer] Payload:", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(15, "Validating payload...");
            return;
        }

        if (line.Contains("[UE Tool Suite Installer] Payload manifest:", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(25, "Loading payload manifest...");
            return;
        }

        if (line.Contains("[UE Tool Suite Installer] Backed up existing website before adoption:", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(35, "Backing up existing website before adoption...");
            return;
        }

        if (line.Contains("[UE Tool Suite Installer] Preserved customized docs files were not overwritten.", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(46, "Preserving customized docs and generating update report...");
            return;
        }

        if (line.Contains("[UE Tool Suite Installer] Applied website theme", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(52, "Applying docs website theme and branding...");
            return;
        }

        if (line.Contains("[UE Tool Suite Installer] Installed/updated UE tool suite paths:", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(58, "Payload install/update complete.");
            return;
        }

        if (line.Contains("[UE Tool Suite Installer] Running target bootstrap:", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(62, "Starting repo initialization...");
            return;
        }

        if (line.Contains("[Init] Repo root:", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(66, "Initializing repo tooling...");
            return;
        }

        if (line.Contains("[Init] Initializing Git LFS filters for this repo", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(70, "Initializing Git LFS filters...");
            return;
        }

        if (line.Contains("[Init] Pulling LFS content", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(74, "Pulling Git LFS content...");
            return;
        }

        if (line.Contains("[Init] Applying recommended repo-local git config...", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(78, "Applying git configuration...");
            return;
        }

        if (line.Contains("ignored tracked file", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(82, "Updating ignored tracked files...");
            return;
        }

        if (line.Contains("[Init] Running Enable-GitHooks.ps1...", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(84, "Enabling git hooks...");
            return;
        }

        if (line.Contains("[Init] Configuring git aliases:", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(86, "Configuring git conflict helper aliases...");
            return;
        }

        if (line.Contains("[Init] Configuring PowerShell aliases for the dispatcher", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(88, "Installing PowerShell command aliases...");
            return;
        }

        if (line.Contains("[Init] Running hook self-test...", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(90, "Running hook self-test...");
            return;
        }

        if (line.Contains("[Init] Hook self-test completed.", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(91, "Hook self-test complete.");
            return;
        }

        if (line.Contains("[Init] Preparing docs tooling prerequisites...", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(92, "Preparing docs tooling prerequisites...");
            return;
        }

        if (line.Contains("[Init] Skipping docs tooling prerequisite setup.", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(92, "Skipping docs tooling prerequisite setup...");
            return;
        }

        if (line.Contains("[Init] Installing docs site dependencies with npm install...", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(93, "Installing docs dependencies (npm install)...");
            return;
        }

        if (line.Contains("[Init] Installing optional docs VS Code bridge...", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(94, "Installing docs VS Code bridge...");
            return;
        }

        if (line.Contains("[Init] Skipping docs VS Code bridge install", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(94, "Skipping docs VS Code bridge install...");
            return;
        }

        if (line.Contains("[Init] Running ue-tools docs doctor...", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(95, "Running docs doctor (Docusaurus validation)...");
            return;
        }

        if (line.Contains("Docs check passed.", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(96, "Docs doctor completed.");
            return;
        }

        if (line.Contains("[Init] Running ue-tools build for first-time setup...", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(97, "Running first-time Unreal build setup...");
            return;
        }

        if (line.Contains("[UE Sync]", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(98, "Running Unreal sync/build steps...");
            return;
        }

        if (line.Contains("[Init] Repo initialization complete.", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(99, "Finalizing...");
            return;
        }

        if (line.Contains("[UE Tool Suite Installer] Next step in the target repo:", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(98, "Finalizing...");
            return;
        }

        if (line.Contains("[UE Tool Suite Installer] Done.", StringComparison.OrdinalIgnoreCase))
        {
            SetProgress(100, "Install complete");
        }
    }

    private void SetProgress(int percent, string message, bool allowDecrease = false)
    {
        if (InvokeRequired)
        {
            BeginInvoke(new Action<int, string, bool>(SetProgress), percent, message, allowDecrease);
            return;
        }

        var clamped = Math.Clamp(percent, 0, 100);
        currentProgress = allowDecrease ? clamped : Math.Max(currentProgress, clamped);
        installProgressBar.Value = currentProgress;
        progressLabel.Text = message;
    }

    private void SetInstallUiState(bool enabled)
    {
        installButton.Enabled = enabled;
        cancelButton.Enabled = !enabled && installCancellation is not null && !installCancellation.IsCancellationRequested;
        browseButton.Enabled = enabled;

        showAdvancedOptionsCheckBox.Enabled = enabled;
        noBackupCheckBox.Enabled = enabled;
        skipDocsCheckBox.Enabled = enabled;
        skipWebsiteCheckBox.Enabled = enabled;
        skipTestsCheckBox.Enabled = enabled;
        skipAiToolsCheckBox.Enabled = enabled;
        skipArtSourceToolsCheckBox.Enabled = enabled;
        skipCodingStandardsToolsCheckBox.Enabled = enabled;
        runInitCheckBox.Enabled = enabled;

        if (enabled)
        {
            ApplyOptionDependencies();
        }
        else
        {
            websiteThemeComboBox.Enabled = false;
            websiteLogoPathTextBox.Enabled = false;
            browseWebsiteLogoButton.Enabled = false;
            clearWebsiteLogoButton.Enabled = false;
            initNonInteractiveCheckBox.Enabled = false;
            skipLfsPullCheckBox.Enabled = false;
            skipUnrealSyncCheckBox.Enabled = false;
            skipShellAliasesCheckBox.Enabled = false;
            skipOptionalToolSetupCheckBox.Enabled = false;
            skipDocsSetupCheckBox.Enabled = false;
            skipDocsNpmInstallCheckBox.Enabled = false;
            forceDocsNpmInstallCheckBox.Enabled = false;
            skipDocsBridgeInstallCheckBox.Enabled = false;
            noBuildCheckBox.Enabled = false;
            noRegenCheckBox.Enabled = false;
        }
    }

    private void SetLogVisibility(bool visible)
    {
        if (InvokeRequired)
        {
            BeginInvoke(new Action<bool>(SetLogVisibility), visible);
            return;
        }

        if (visible)
        {
            if (mainSplitContainer.Panel2Collapsed)
            {
                mainSplitContainer.Panel2Collapsed = false;
                ApplySplitterMinimums();
                if (!logPaneHasBeenShown)
                {
                    var primaryLength = mainSplitContainer.Orientation == Orientation.Horizontal
                        ? mainSplitContainer.ClientSize.Height
                        : mainSplitContainer.ClientSize.Width;
                    var desiredDistance = (int)(primaryLength * 0.62);
                    var minimum = mainSplitContainer.Panel1MinSize;
                    var maximum = Math.Max(minimum, primaryLength - mainSplitContainer.SplitterWidth - mainSplitContainer.Panel2MinSize);
                    mainSplitContainer.SplitterDistance = Math.Clamp(desiredDistance, minimum, maximum);
                    logPaneHasBeenShown = true;
                }
            }
        }
        else
        {
            if (!mainSplitContainer.Panel2Collapsed)
            {
                mainSplitContainer.Panel2Collapsed = true;
                ApplySplitterMinimums();
            }
        }
    }

    private void EnsureLogVisibleOnFailure()
    {
        if (!showLogCheckBox.Checked)
        {
            showLogCheckBox.Checked = true;
        }
    }

    private static void TryKillProcessTree(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // Best effort only.
        }
    }

    private void SetLastOutputLine(string line)
    {
        lock (outputStateLock)
        {
            lastOutputLine = line;
        }
    }

    private string GetLastOutputLine()
    {
        lock (outputStateLock)
        {
            return lastOutputLine;
        }
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

    private void ResetForNextInstall()
    {
        projectPathTextBox.Clear();
        websiteLogoPathTextBox.Clear();
        var defaultTheme = websiteThemeOptions.FirstOrDefault(option => option.Id.Equals(DefaultWebsiteThemeId, StringComparison.OrdinalIgnoreCase));
        if (defaultTheme is not null)
        {
            websiteThemeComboBox.SelectedItem = defaultTheme;
        }
        adoptExistingWebsiteCheckBox.Checked = false;
        logTextBox.Clear();
        statusLabel.Text = "Ready";
        SetProgress(0, DefaultProgressMessage, allowDecrease: true);
        showLogCheckBox.Checked = false;
    }
}

internal sealed class WebsiteThemeCatalog
{
    public string? DefaultTheme { get; set; }
    public List<WebsiteThemeCatalogItem>? Themes { get; set; }
}

internal sealed class WebsiteThemeCatalogItem
{
    public string? Id { get; set; }
    public string? Label { get; set; }
    public string? Description { get; set; }
    public string? CssPath { get; set; }
}

internal sealed record WebsiteThemeOption(string Id, string Label, string Description)
{
    public override string ToString()
    {
        return $"{Label} ({Id})";
    }
}

internal sealed record InstallOptions(
    bool RunInit,
    bool InitNonInteractive,
    bool SkipLfsPull,
    bool SkipShellAliases,
    bool SkipOptionalToolSetup,
    bool SkipDocsSetup,
    bool SkipDocsNpmInstall,
    bool ForceDocsNpmInstall,
    bool SkipDocsBridgeInstall,
    bool SkipUnrealSync,
    bool NoBuild,
    bool NoRegen,
    bool SkipDocs,
    bool SkipWebsite,
    bool AdoptExistingWebsite,
    bool SkipTests,
    bool SkipAITools,
    bool SkipArtSourceTools,
    bool SkipCodingStandardsTools,
    bool NoBackup,
    string WebsiteTheme,
    string? WebsiteLogoPath);
