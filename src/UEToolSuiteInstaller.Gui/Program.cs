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
    private static readonly string[] WebsiteOverrideCandidates =
    {
        "website/docusaurus.config.ts",
        "website/src/css/custom.css",
        "website/src/pages/index.tsx",
        "website/src/pages/index.module.css",
        "Docs/README.md",
    };
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
    private readonly ComboBox websiteInstallModeComboBox = new();
    private readonly Label websiteInstallModeDescriptionLabel = new();
    private readonly TextBox websiteGlobalIconPathTextBox = new();
    private readonly TextBox websiteLogoPathTextBox = new();
    private readonly TextBox websiteFaviconPathTextBox = new();
    private readonly TextBox websiteSocialCardPathTextBox = new();
    private readonly Button browseWebsiteGlobalIconButton = new();
    private readonly Button clearWebsiteGlobalIconButton = new();
    private readonly Button browseWebsiteLogoButton = new();
    private readonly Button clearWebsiteLogoButton = new();
    private readonly Button browseWebsiteFaviconButton = new();
    private readonly Button clearWebsiteFaviconButton = new();
    private readonly Button browseWebsiteSocialCardButton = new();
    private readonly Button clearWebsiteSocialCardButton = new();
    private readonly CheckBox usePerAssetBrandingOverridesCheckBox = new();
    private readonly Panel websiteBrandingOverridesPanel = new();
    private readonly CheckBox customizeWebsiteOverridesCheckBox = new();
    private readonly Panel websiteOverridesPanel = new();
    private readonly Label websiteOverrideHelpLabel = new();
    private readonly ComboBox websiteOverridesBulkModeComboBox = new();
    private readonly DataGridView websiteOverridesGrid = new();
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
    private List<WebsiteInstallModeOption> websiteInstallModeOptions = new();

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
        LoadWebsiteInstallModeOptions();

        var panel = new TableLayoutPanel
        {
            ColumnCount = 1,
            RowCount = 8,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = new Padding(0, 8, 0, 0),
            Padding = new Padding(12, 12, 12, 10),
            BackColor = Color.FromArgb(244, 246, 250),
        };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        for (var i = 0; i < 8; i++)
        {
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        }

        var headerLabel = new Label
        {
            Text = "Docs website branding",
            AutoSize = true,
            Font = new Font("Segoe UI", 9.5F, FontStyle.Bold),
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 0, 0, 6),
        };
        panel.Controls.Add(headerLabel, 0, 0);

        var summaryLabel = new Label
        {
            Text = "Use merge mode to keep project docs content while updating the managed website shell. Branding defaults to one global icon, with optional per-asset overrides only when needed.",
            AutoSize = true,
            MaximumSize = new Size(860, 0),
            ForeColor = Color.FromArgb(72, 79, 96),
            Margin = new Padding(0, 0, 0, 10),
        };
        panel.Controls.Add(summaryLabel, 0, 1);

        var installModePanel = new TableLayoutPanel
        {
            ColumnCount = 2,
            RowCount = 2,
            Dock = DockStyle.Fill,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = new Padding(0, 0, 0, 10),
        };
        installModePanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        installModePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        installModePanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        installModePanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var installModeLabel = new Label
        {
            Text = "Website install mode",
            AutoSize = true,
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 6, 10, 0),
        };
        installModePanel.Controls.Add(installModeLabel, 0, 0);

        websiteInstallModeComboBox.DropDownStyle = ComboBoxStyle.DropDownList;
        websiteInstallModeComboBox.Width = 320;
        websiteInstallModeComboBox.Margin = new Padding(0, 2, 10, 0);
        websiteInstallModeComboBox.Items.Clear();
        websiteInstallModeComboBox.Items.AddRange(websiteInstallModeOptions.Cast<object>().ToArray());
        websiteInstallModeComboBox.SelectedItem = websiteInstallModeOptions.FirstOrDefault(option => option.Id.Equals("MergeExisting", StringComparison.OrdinalIgnoreCase));
        websiteInstallModeComboBox.SelectedIndexChanged += (_, _) => UpdateWebsiteInstallModeDescription();
        installModePanel.Controls.Add(websiteInstallModeComboBox, 1, 0);

        websiteInstallModeDescriptionLabel.AutoSize = true;
        websiteInstallModeDescriptionLabel.MaximumSize = new Size(700, 0);
        websiteInstallModeDescriptionLabel.ForeColor = Color.FromArgb(72, 79, 96);
        websiteInstallModeDescriptionLabel.Margin = new Padding(0, 6, 0, 0);
        installModePanel.Controls.Add(websiteInstallModeDescriptionLabel, 1, 1);
        panel.Controls.Add(installModePanel, 0, 2);

        var themePanel = new TableLayoutPanel
        {
            ColumnCount = 2,
            RowCount = 1,
            Dock = DockStyle.Fill,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = new Padding(0, 0, 0, 10),
        };
        themePanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        themePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        var themeLabel = new Label
        {
            Text = "Theme",
            AutoSize = true,
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 6, 10, 0),
        };
        themePanel.Controls.Add(themeLabel, 0, 0);

        websiteThemeComboBox.DropDownStyle = ComboBoxStyle.DropDownList;
        websiteThemeComboBox.Width = 360;
        websiteThemeComboBox.Margin = new Padding(0, 2, 10, 0);
        themePanel.Controls.Add(websiteThemeComboBox, 1, 0);
        panel.Controls.Add(themePanel, 0, 3);

        var brandingPanel = new TableLayoutPanel
        {
            ColumnCount = 4,
            RowCount = 4,
            Dock = DockStyle.Fill,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = new Padding(0, 0, 0, 10),
        };
        brandingPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        brandingPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        brandingPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        brandingPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        for (var i = 0; i < 4; i++)
        {
            brandingPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        }

        var globalIconLabel = new Label
        {
            Text = "Global site icon (.svg/.png)",
            AutoSize = true,
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 8, 10, 0),
        };
        brandingPanel.Controls.Add(globalIconLabel, 0, 0);

        websiteGlobalIconPathTextBox.ReadOnly = true;
        websiteGlobalIconPathTextBox.PlaceholderText = "Optional icon used for logo, favicon, and social card by default...";
        websiteGlobalIconPathTextBox.Margin = new Padding(0, 4, 10, 0);
        websiteGlobalIconPathTextBox.Width = 420;
        brandingPanel.Controls.Add(websiteGlobalIconPathTextBox, 1, 0);

        browseWebsiteGlobalIconButton.Text = "Browse...";
        browseWebsiteGlobalIconButton.AutoSize = true;
        browseWebsiteGlobalIconButton.Margin = new Padding(0, 3, 6, 0);
        browseWebsiteGlobalIconButton.Click += (_, _) => BrowseForWebsiteGlobalIcon();
        brandingPanel.Controls.Add(browseWebsiteGlobalIconButton, 2, 0);

        clearWebsiteGlobalIconButton.Text = "Clear";
        clearWebsiteGlobalIconButton.AutoSize = true;
        clearWebsiteGlobalIconButton.Margin = new Padding(0, 3, 0, 0);
        clearWebsiteGlobalIconButton.Click += (_, _) =>
        {
            websiteGlobalIconPathTextBox.Text = string.Empty;
            statusLabel.Text = "Ready";
        };
        brandingPanel.Controls.Add(clearWebsiteGlobalIconButton, 3, 0);

        usePerAssetBrandingOverridesCheckBox.Text = "Use per-asset overrides";
        usePerAssetBrandingOverridesCheckBox.AutoSize = true;
        usePerAssetBrandingOverridesCheckBox.Margin = new Padding(0, 8, 0, 0);
        usePerAssetBrandingOverridesCheckBox.CheckedChanged += (_, _) =>
        {
            websiteBrandingOverridesPanel.Visible = usePerAssetBrandingOverridesCheckBox.Checked;
            ApplyOptionDependencies();
        };
        brandingPanel.Controls.Add(usePerAssetBrandingOverridesCheckBox, 1, 1);
        brandingPanel.SetColumnSpan(usePerAssetBrandingOverridesCheckBox, 3);

        websiteBrandingOverridesPanel.AutoSize = true;
        websiteBrandingOverridesPanel.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        websiteBrandingOverridesPanel.Dock = DockStyle.Fill;
        websiteBrandingOverridesPanel.Margin = new Padding(0, 8, 0, 0);
        websiteBrandingOverridesPanel.Padding = new Padding(12, 10, 12, 10);
        websiteBrandingOverridesPanel.BackColor = Color.FromArgb(250, 251, 253);

        var assetOverridesLayout = new TableLayoutPanel
        {
            ColumnCount = 4,
            RowCount = 4,
            Dock = DockStyle.Fill,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
        };
        assetOverridesLayout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        assetOverridesLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        assetOverridesLayout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        assetOverridesLayout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var assetOverrideNote = new Label
        {
            Text = "Only fill the assets that should differ from the global icon.",
            AutoSize = true,
            MaximumSize = new Size(700, 0),
            ForeColor = Color.FromArgb(72, 79, 96),
            Margin = new Padding(0, 0, 0, 8),
        };
        assetOverridesLayout.Controls.Add(assetOverrideNote, 0, 0);
        assetOverridesLayout.SetColumnSpan(assetOverrideNote, 4);

        var logoLabel = new Label
        {
            Text = "Logo override",
            AutoSize = true,
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 8, 10, 0),
        };
        assetOverridesLayout.Controls.Add(logoLabel, 0, 1);

        websiteLogoPathTextBox.ReadOnly = true;
        websiteLogoPathTextBox.PlaceholderText = "Optional logo override...";
        websiteLogoPathTextBox.Margin = new Padding(0, 4, 10, 0);
        websiteLogoPathTextBox.Width = 420;
        assetOverridesLayout.Controls.Add(websiteLogoPathTextBox, 1, 1);

        browseWebsiteLogoButton.Text = "Browse...";
        browseWebsiteLogoButton.AutoSize = true;
        browseWebsiteLogoButton.Margin = new Padding(0, 3, 6, 0);
        browseWebsiteLogoButton.Click += (_, _) => BrowseForWebsiteLogo();
        assetOverridesLayout.Controls.Add(browseWebsiteLogoButton, 2, 1);

        clearWebsiteLogoButton.Text = "Clear";
        clearWebsiteLogoButton.AutoSize = true;
        clearWebsiteLogoButton.Margin = new Padding(0, 3, 0, 0);
        clearWebsiteLogoButton.Click += (_, _) =>
        {
            websiteLogoPathTextBox.Text = string.Empty;
            statusLabel.Text = "Ready";
        };
        assetOverridesLayout.Controls.Add(clearWebsiteLogoButton, 3, 1);

        var faviconLabel = new Label
        {
            Text = "Favicon override",
            AutoSize = true,
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 8, 10, 0),
        };
        assetOverridesLayout.Controls.Add(faviconLabel, 0, 2);

        websiteFaviconPathTextBox.ReadOnly = true;
        websiteFaviconPathTextBox.PlaceholderText = "Optional favicon override...";
        websiteFaviconPathTextBox.Margin = new Padding(0, 4, 10, 0);
        websiteFaviconPathTextBox.Width = 420;
        assetOverridesLayout.Controls.Add(websiteFaviconPathTextBox, 1, 2);

        browseWebsiteFaviconButton.Text = "Browse...";
        browseWebsiteFaviconButton.AutoSize = true;
        browseWebsiteFaviconButton.Margin = new Padding(0, 3, 6, 0);
        browseWebsiteFaviconButton.Click += (_, _) => BrowseForWebsiteFavicon();
        assetOverridesLayout.Controls.Add(browseWebsiteFaviconButton, 2, 2);

        clearWebsiteFaviconButton.Text = "Clear";
        clearWebsiteFaviconButton.AutoSize = true;
        clearWebsiteFaviconButton.Margin = new Padding(0, 3, 0, 0);
        clearWebsiteFaviconButton.Click += (_, _) =>
        {
            websiteFaviconPathTextBox.Text = string.Empty;
            statusLabel.Text = "Ready";
        };
        assetOverridesLayout.Controls.Add(clearWebsiteFaviconButton, 3, 2);

        var socialCardLabel = new Label
        {
            Text = "Social card override",
            AutoSize = true,
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 8, 10, 0),
        };
        assetOverridesLayout.Controls.Add(socialCardLabel, 0, 3);

        websiteSocialCardPathTextBox.ReadOnly = true;
        websiteSocialCardPathTextBox.PlaceholderText = "Optional social/share card override...";
        websiteSocialCardPathTextBox.Margin = new Padding(0, 4, 10, 0);
        websiteSocialCardPathTextBox.Width = 420;
        assetOverridesLayout.Controls.Add(websiteSocialCardPathTextBox, 1, 3);

        browseWebsiteSocialCardButton.Text = "Browse...";
        browseWebsiteSocialCardButton.AutoSize = true;
        browseWebsiteSocialCardButton.Margin = new Padding(0, 3, 6, 0);
        browseWebsiteSocialCardButton.Click += (_, _) => BrowseForWebsiteSocialCard();
        assetOverridesLayout.Controls.Add(browseWebsiteSocialCardButton, 2, 3);

        clearWebsiteSocialCardButton.Text = "Clear";
        clearWebsiteSocialCardButton.AutoSize = true;
        clearWebsiteSocialCardButton.Margin = new Padding(0, 3, 0, 0);
        clearWebsiteSocialCardButton.Click += (_, _) =>
        {
            websiteSocialCardPathTextBox.Text = string.Empty;
            statusLabel.Text = "Ready";
        };
        assetOverridesLayout.Controls.Add(clearWebsiteSocialCardButton, 3, 3);

        websiteBrandingOverridesPanel.Controls.Add(assetOverridesLayout);
        websiteBrandingOverridesPanel.Visible = false;
        brandingPanel.Controls.Add(websiteBrandingOverridesPanel, 1, 2);
        brandingPanel.SetColumnSpan(websiteBrandingOverridesPanel, 3);
        panel.Controls.Add(brandingPanel, 0, 4);

        customizeWebsiteOverridesCheckBox.Text = "Customize file ownership overrides";
        customizeWebsiteOverridesCheckBox.AutoSize = true;
        customizeWebsiteOverridesCheckBox.Margin = new Padding(0, 0, 0, 0);
        customizeWebsiteOverridesCheckBox.CheckedChanged += (_, _) =>
        {
            websiteOverridesPanel.Visible = customizeWebsiteOverridesCheckBox.Checked;
            ApplyOptionDependencies();
        };
        panel.Controls.Add(customizeWebsiteOverridesCheckBox, 0, 5);

        websiteOverridesPanel.AutoSize = true;
        websiteOverridesPanel.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        websiteOverridesPanel.Dock = DockStyle.Fill;
        websiteOverridesPanel.Margin = new Padding(0, 8, 0, 0);
        websiteOverridesPanel.Padding = new Padding(12, 10, 12, 10);
        websiteOverridesPanel.BackColor = Color.FromArgb(250, 251, 253);

        var overridesLayout = new TableLayoutPanel
        {
            ColumnCount = 1,
            RowCount = 4,
            Dock = DockStyle.Fill,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
        };
        overridesLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        var overrideLabel = new Label
        {
            Text = "Per-file ownership overrides",
            AutoSize = true,
            Font = new Font("Segoe UI", 9.5F, FontStyle.Bold),
            ForeColor = Color.FromArgb(26, 31, 44),
            Margin = new Padding(0, 0, 0, 4),
        };
        overridesLayout.Controls.Add(overrideLabel, 0, 0);

        websiteOverrideHelpLabel.AutoSize = true;
        websiteOverrideHelpLabel.MaximumSize = new Size(760, 0);
        websiteOverrideHelpLabel.ForeColor = Color.FromArgb(72, 79, 96);
        websiteOverrideHelpLabel.Margin = new Padding(0, 0, 0, 8);
        websiteOverrideHelpLabel.Text = "Auto uses the suite default policy. That means the website shell stays suite-managed, while managed docs content is preserved unless you explicitly force Suite.";
        overridesLayout.Controls.Add(websiteOverrideHelpLabel, 0, 1);

        var bulkOverridePanel = new FlowLayoutPanel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Margin = new Padding(0, 0, 0, 8),
        };

        var bulkOverrideLabel = new Label
        {
            Text = "Apply to all",
            AutoSize = true,
            ForeColor = Color.FromArgb(72, 79, 96),
            Margin = new Padding(0, 6, 8, 0),
        };
        bulkOverridePanel.Controls.Add(bulkOverrideLabel);

        websiteOverridesBulkModeComboBox.DropDownStyle = ComboBoxStyle.DropDownList;
        websiteOverridesBulkModeComboBox.Width = 180;
        websiteOverridesBulkModeComboBox.Items.AddRange(new object[] { "Apply to all...", "Auto", "Suite", "Project" });
        websiteOverridesBulkModeComboBox.SelectedIndex = 0;
        websiteOverridesBulkModeComboBox.SelectedIndexChanged += (_, _) =>
        {
            var selectedMode = websiteOverridesBulkModeComboBox.SelectedItem?.ToString();
            if (string.IsNullOrWhiteSpace(selectedMode) || string.Equals(selectedMode, "Apply to all...", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            ApplyWebsiteOverrideModeToAll(selectedMode);
            websiteOverridesBulkModeComboBox.SelectedIndex = 0;
            statusLabel.Text = "Ready";
        };
        bulkOverridePanel.Controls.Add(websiteOverridesBulkModeComboBox);
        overridesLayout.Controls.Add(bulkOverridePanel, 0, 2);

        ConfigureWebsiteOverridesGrid();
        overridesLayout.Controls.Add(websiteOverridesGrid, 0, 3);
        websiteOverridesPanel.Controls.Add(overridesLayout);
        websiteOverridesPanel.Visible = false;
        panel.Controls.Add(websiteOverridesPanel, 0, 6);

        UpdateWebsiteInstallModeDescription();

        return panel;
    }

    private void LoadWebsiteInstallModeOptions()
    {
        if (websiteInstallModeOptions.Count > 0)
        {
            return;
        }

        websiteInstallModeOptions = new List<WebsiteInstallModeOption>
        {
            new("MergeExisting", "Merge existing website (Recommended)", "Updates the managed docs shell and features, keeps existing Docs content, and only overrides project-owned files when you explicitly ask for it."),
            new("PreserveExisting", "Keep current website unchanged", "Leaves the existing website shell alone. Use this if the project website is fully custom and you do not want suite website updates applied."),
            new("ReplaceExisting", "Replace website shell", "Replaces the current website shell with the suite version. Use this only when you want a hard reset of the site renderer and managed defaults.")
        };
    }

    private void BrowseForWebsiteLogo()
    {
        BrowseForAsset("Choose website logo asset", "Logo files (*.svg;*.png)|*.svg;*.png", websiteLogoPathTextBox);
    }

    private void BrowseForWebsiteGlobalIcon()
    {
        BrowseForAsset("Choose global site icon", "Icon image files (*.svg;*.png)|*.svg;*.png", websiteGlobalIconPathTextBox);
    }

    private void BrowseForWebsiteFavicon()
    {
        BrowseForAsset("Choose website favicon asset", "Favicon files (*.svg;*.png;*.ico)|*.svg;*.png;*.ico", websiteFaviconPathTextBox);
    }

    private void BrowseForWebsiteSocialCard()
    {
        BrowseForAsset("Choose website social card asset", "Image files (*.svg;*.png;*.jpg;*.jpeg;*.webp)|*.svg;*.png;*.jpg;*.jpeg;*.webp", websiteSocialCardPathTextBox);
    }

    private void BrowseForAsset(string title, string filter, TextBox targetTextBox)
    {
        using var dialog = new OpenFileDialog
        {
            Title = title,
            Filter = filter,
            CheckFileExists = true,
            Multiselect = false,
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            targetTextBox.Text = dialog.FileName;
            statusLabel.Text = "Ready";
        }
    }

    private void ConfigureWebsiteOverridesGrid()
    {
        if (websiteOverridesGrid.Columns.Count > 0)
        {
            return;
        }

        websiteOverridesGrid.AllowUserToAddRows = false;
        websiteOverridesGrid.AllowUserToDeleteRows = false;
        websiteOverridesGrid.AllowUserToResizeRows = false;
        websiteOverridesGrid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        websiteOverridesGrid.BackgroundColor = Color.White;
        websiteOverridesGrid.BorderStyle = BorderStyle.FixedSingle;
        websiteOverridesGrid.RowHeadersVisible = false;
        websiteOverridesGrid.Height = 170;
        websiteOverridesGrid.Margin = new Padding(0, 6, 0, 0);

        var pathColumn = new DataGridViewTextBoxColumn
        {
            Name = "Path",
            HeaderText = "Path",
            ReadOnly = true,
            FillWeight = 72,
        };
        var modeColumn = new DataGridViewComboBoxColumn
        {
            Name = "Mode",
            HeaderText = "Mode",
            FillWeight = 28,
            DataSource = new[] { "Auto", "Suite", "Project" },
        };

        websiteOverridesGrid.Columns.Add(pathColumn);
        websiteOverridesGrid.Columns.Add(modeColumn);

        foreach (var path in WebsiteOverrideCandidates)
        {
            websiteOverridesGrid.Rows.Add(path, "Auto");
        }
    }

    private void ApplyWebsiteOverrideModeToAll(string mode)
    {
        foreach (DataGridViewRow row in websiteOverridesGrid.Rows)
        {
            if (!row.IsNewRow)
            {
                row.Cells[1].Value = mode;
            }
        }
    }

    private void UpdateWebsiteInstallModeDescription()
    {
        if (websiteInstallModeComboBox.SelectedItem is WebsiteInstallModeOption option)
        {
            websiteInstallModeDescriptionLabel.Text = option.Description;
            return;
        }

        websiteInstallModeDescriptionLabel.Text = string.Empty;
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
        ConfigureOptionCheckBox(skipTestsCheckBox, "Skip payload test scripts", false);
        ConfigureOptionCheckBox(skipAiToolsCheckBox, "Skip AI docs/tooling payload", false);
        ConfigureOptionCheckBox(skipArtSourceToolsCheckBox, "Skip ArtSource tooling payload", false);
        ConfigureOptionCheckBox(skipCodingStandardsToolsCheckBox, "Skip coding standards payload", false);
        payloadColumn.Controls.Add(skipDocsCheckBox);
        payloadColumn.Controls.Add(skipWebsiteCheckBox);
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
        websiteInstallModeComboBox.Enabled = websiteEnabled;
        websiteThemeComboBox.Enabled = websiteEnabled;
        websiteGlobalIconPathTextBox.Enabled = websiteEnabled;
        websiteLogoPathTextBox.Enabled = websiteEnabled;
        websiteFaviconPathTextBox.Enabled = websiteEnabled;
        websiteSocialCardPathTextBox.Enabled = websiteEnabled;
        browseWebsiteGlobalIconButton.Enabled = websiteEnabled;
        clearWebsiteGlobalIconButton.Enabled = websiteEnabled;
        browseWebsiteLogoButton.Enabled = websiteEnabled;
        browseWebsiteFaviconButton.Enabled = websiteEnabled;
        browseWebsiteSocialCardButton.Enabled = websiteEnabled;
        clearWebsiteLogoButton.Enabled = websiteEnabled;
        clearWebsiteFaviconButton.Enabled = websiteEnabled;
        clearWebsiteSocialCardButton.Enabled = websiteEnabled;
        usePerAssetBrandingOverridesCheckBox.Enabled = websiteEnabled;
        websiteBrandingOverridesPanel.Enabled = websiteEnabled && usePerAssetBrandingOverridesCheckBox.Checked;
        customizeWebsiteOverridesCheckBox.Enabled = websiteEnabled;
        websiteOverridesPanel.Enabled = websiteEnabled && customizeWebsiteOverridesCheckBox.Checked;
        websiteOverridesGrid.Enabled = websiteEnabled && customizeWebsiteOverridesCheckBox.Checked;
        websiteOverridesBulkModeComboBox.Enabled = websiteEnabled && customizeWebsiteOverridesCheckBox.Checked;

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
            var targetRoot = Path.GetDirectoryName(dialog.FileName);
            if (!string.IsNullOrWhiteSpace(targetRoot))
            {
                TryLoadExistingWebsiteOverrides(targetRoot);
            }
            statusLabel.Text = "Ready";
        }
    }

    private void TryLoadExistingWebsiteOverrides(string targetRoot)
    {
        try
        {
            var overridesPath = Path.Combine(targetRoot, "website", ".ue-tools", "site-overrides.json");
            if (!File.Exists(overridesPath))
            {
                return;
            }

            var parsed = JsonSerializer.Deserialize<WebsiteOverridesDocument>(File.ReadAllText(overridesPath, Encoding.UTF8), new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
            });

            if (!string.IsNullOrWhiteSpace(parsed?.Theme?.ThemeId))
            {
                var selectedTheme = websiteThemeOptions.FirstOrDefault(option => option.Id.Equals(parsed.Theme.ThemeId, StringComparison.OrdinalIgnoreCase));
                if (selectedTheme is not null)
                {
                    websiteThemeComboBox.SelectedItem = selectedTheme;
                }
            }

            var storedLogoPath = parsed?.Theme?.LogoPath ?? string.Empty;
            var storedFaviconPath = parsed?.Theme?.FaviconPath ?? string.Empty;
            var storedSocialCardPath = parsed?.Theme?.SocialCardPath ?? string.Empty;
            var hasSpecificOverrides =
                !string.IsNullOrWhiteSpace(storedFaviconPath) ||
                !string.IsNullOrWhiteSpace(storedSocialCardPath);

            websiteGlobalIconPathTextBox.Text = !string.IsNullOrWhiteSpace(storedLogoPath)
                ? storedLogoPath
                : (!string.IsNullOrWhiteSpace(storedFaviconPath) ? storedFaviconPath : storedSocialCardPath);

            usePerAssetBrandingOverridesCheckBox.Checked = hasSpecificOverrides;
            websiteLogoPathTextBox.Text = hasSpecificOverrides ? storedLogoPath : string.Empty;
            websiteFaviconPathTextBox.Text = hasSpecificOverrides ? storedFaviconPath : string.Empty;
            websiteSocialCardPathTextBox.Text = hasSpecificOverrides ? storedSocialCardPath : string.Empty;

            foreach (DataGridViewRow row in websiteOverridesGrid.Rows)
            {
                row.Cells[1].Value = "Auto";
            }

            var hasExplicitFileOverrides = false;
            foreach (var entry in parsed?.FileOverrides ?? Enumerable.Empty<WebsiteFileOverrideEntry>())
            {
                if (entry is null || string.IsNullOrWhiteSpace(entry.Path) || string.IsNullOrWhiteSpace(entry.Mode))
                {
                    continue;
                }

                foreach (DataGridViewRow row in websiteOverridesGrid.Rows)
                {
                    if (string.Equals(row.Cells[0].Value?.ToString(), entry.Path, StringComparison.OrdinalIgnoreCase))
                    {
                        hasExplicitFileOverrides = true;
                        row.Cells[1].Value = string.Equals(entry.Mode, "project", StringComparison.OrdinalIgnoreCase) ? "Project" : "Suite";
                        break;
                    }
                }
            }

            customizeWebsiteOverridesCheckBox.Checked = hasExplicitFileOverrides;
        }
        catch
        {
            // Keep installer UI usable even if the overrides file is malformed.
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

        TryLoadExistingWebsiteOverrides(targetRoot);

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
        var selectedInstallMode = (websiteInstallModeComboBox.SelectedItem as WebsiteInstallModeOption)?.Id ?? "MergeExisting";
        var selectedTheme = (websiteThemeComboBox.SelectedItem as WebsiteThemeOption)?.Id ?? DefaultWebsiteThemeId;
        var globalIconPath = string.IsNullOrWhiteSpace(websiteGlobalIconPathTextBox.Text) ? null : websiteGlobalIconPathTextBox.Text.Trim();
        var logoPath = usePerAssetBrandingOverridesCheckBox.Checked && !string.IsNullOrWhiteSpace(websiteLogoPathTextBox.Text) ? websiteLogoPathTextBox.Text.Trim() : null;
        var faviconPath = usePerAssetBrandingOverridesCheckBox.Checked && !string.IsNullOrWhiteSpace(websiteFaviconPathTextBox.Text) ? websiteFaviconPathTextBox.Text.Trim() : null;
        var socialCardPath = usePerAssetBrandingOverridesCheckBox.Checked && !string.IsNullOrWhiteSpace(websiteSocialCardPathTextBox.Text) ? websiteSocialCardPathTextBox.Text.Trim() : null;
        var forceSuitePaths = new List<string>();
        var forceProjectPaths = new List<string>();
        foreach (DataGridViewRow row in websiteOverridesGrid.Rows)
        {
            if (row.Cells[0].Value is not string path || string.IsNullOrWhiteSpace(path))
            {
                continue;
            }

            var mode = row.Cells[1].Value?.ToString()?.Trim();
            if (string.Equals(mode, "Suite", StringComparison.OrdinalIgnoreCase))
            {
                forceSuitePaths.Add(path);
            }
            else if (string.Equals(mode, "Project", StringComparison.OrdinalIgnoreCase))
            {
                forceProjectPaths.Add(path);
            }
        }

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
            SkipTests: skipTestsCheckBox.Checked,
            SkipAITools: skipAiToolsCheckBox.Checked,
            SkipArtSourceTools: skipArtSourceToolsCheckBox.Checked,
            SkipCodingStandardsTools: skipCodingStandardsToolsCheckBox.Checked,
            NoBackup: noBackupCheckBox.Checked,
            WebsiteInstallMode: selectedInstallMode,
            WebsiteTheme: selectedTheme,
            WebsiteGlobalIconPath: globalIconPath,
            WebsiteLogoPath: logoPath,
            WebsiteFaviconPath: faviconPath,
            WebsiteSocialCardPath: socialCardPath,
            WebsiteForceSuitePaths: forceSuitePaths,
            WebsiteForceProjectPaths: forceProjectPaths);
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
            args.Add("-WebsiteInstallMode");
            args.Add(string.IsNullOrWhiteSpace(options.WebsiteInstallMode) ? "MergeExisting" : options.WebsiteInstallMode!);
            args.Add("-WebsiteTheme");
            args.Add(string.IsNullOrWhiteSpace(options.WebsiteTheme) ? DefaultWebsiteThemeId : options.WebsiteTheme!);
            if (!string.IsNullOrWhiteSpace(options.WebsiteGlobalIconPath))
            {
                args.Add("-WebsiteGlobalIconPath");
                args.Add(options.WebsiteGlobalIconPath!);
            }
            if (!string.IsNullOrWhiteSpace(options.WebsiteLogoPath))
            {
                args.Add("-WebsiteLogoPath");
                args.Add(options.WebsiteLogoPath!);
            }
            if (!string.IsNullOrWhiteSpace(options.WebsiteFaviconPath))
            {
                args.Add("-WebsiteFaviconPath");
                args.Add(options.WebsiteFaviconPath!);
            }
            if (!string.IsNullOrWhiteSpace(options.WebsiteSocialCardPath))
            {
                args.Add("-WebsiteSocialCardPath");
                args.Add(options.WebsiteSocialCardPath!);
            }
            if (options.WebsiteForceSuitePaths.Count > 0)
            {
                args.Add("-WebsiteForceSuitePath");
                args.Add(string.Join(",", options.WebsiteForceSuitePaths));
            }
            if (options.WebsiteForceProjectPaths.Count > 0)
            {
                args.Add("-WebsiteForceProjectPath");
                args.Add(string.Join(",", options.WebsiteForceProjectPaths));
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

        if (line.Contains("[Init] Installing docs site dependencies with npm", StringComparison.OrdinalIgnoreCase))
        {
            if (line.Contains("npm ci", StringComparison.OrdinalIgnoreCase))
            {
                SetProgress(93, "Installing docs dependencies (npm ci)...");
            }
            else
            {
                SetProgress(93, "Installing docs dependencies (npm install)...");
            }
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
            websiteInstallModeComboBox.Enabled = false;
            websiteThemeComboBox.Enabled = false;
            websiteGlobalIconPathTextBox.Enabled = false;
            websiteLogoPathTextBox.Enabled = false;
            websiteFaviconPathTextBox.Enabled = false;
            websiteSocialCardPathTextBox.Enabled = false;
            browseWebsiteGlobalIconButton.Enabled = false;
            clearWebsiteGlobalIconButton.Enabled = false;
            browseWebsiteLogoButton.Enabled = false;
            browseWebsiteFaviconButton.Enabled = false;
            browseWebsiteSocialCardButton.Enabled = false;
            clearWebsiteLogoButton.Enabled = false;
            clearWebsiteFaviconButton.Enabled = false;
            clearWebsiteSocialCardButton.Enabled = false;
            usePerAssetBrandingOverridesCheckBox.Enabled = false;
            customizeWebsiteOverridesCheckBox.Enabled = false;
            websiteOverridesGrid.Enabled = false;
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
        websiteGlobalIconPathTextBox.Clear();
        websiteLogoPathTextBox.Clear();
        websiteFaviconPathTextBox.Clear();
        websiteSocialCardPathTextBox.Clear();
        usePerAssetBrandingOverridesCheckBox.Checked = false;
        customizeWebsiteOverridesCheckBox.Checked = false;
        websiteOverridesBulkModeComboBox.SelectedIndex = 0;
        var defaultTheme = websiteThemeOptions.FirstOrDefault(option => option.Id.Equals(DefaultWebsiteThemeId, StringComparison.OrdinalIgnoreCase));
        if (defaultTheme is not null)
        {
            websiteThemeComboBox.SelectedItem = defaultTheme;
        }
        websiteInstallModeComboBox.SelectedItem = websiteInstallModeOptions.FirstOrDefault(option => option.Id.Equals("MergeExisting", StringComparison.OrdinalIgnoreCase));
        foreach (DataGridViewRow row in websiteOverridesGrid.Rows)
        {
            row.Cells[1].Value = "Auto";
        }
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

internal sealed class WebsiteOverridesDocument
{
    public WebsiteOverridesTheme? Theme { get; set; }
    public List<WebsiteFileOverrideEntry>? FileOverrides { get; set; }
}

internal sealed class WebsiteOverridesTheme
{
    public string? ThemeId { get; set; }
    public string? LogoPath { get; set; }
    public string? FaviconPath { get; set; }
    public string? SocialCardPath { get; set; }
}

internal sealed class WebsiteFileOverrideEntry
{
    public string? Path { get; set; }
    public string? Mode { get; set; }
}

internal sealed record WebsiteThemeOption(string Id, string Label, string Description)
{
    public override string ToString()
    {
        return $"{Label} ({Id})";
    }
}

internal sealed record WebsiteInstallModeOption(string Id, string Label, string Description)
{
    public override string ToString()
    {
        return Label;
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
    bool SkipTests,
    bool SkipAITools,
    bool SkipArtSourceTools,
    bool SkipCodingStandardsTools,
    bool NoBackup,
    string WebsiteInstallMode,
    string WebsiteTheme,
    string? WebsiteGlobalIconPath,
    string? WebsiteLogoPath,
    string? WebsiteFaviconPath,
    string? WebsiteSocialCardPath,
    List<string> WebsiteForceSuitePaths,
    List<string> WebsiteForceProjectPaths);
