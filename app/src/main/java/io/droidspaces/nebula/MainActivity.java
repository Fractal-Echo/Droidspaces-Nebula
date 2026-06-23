package io.droidspaces.nebula;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.List;
import java.util.Locale;

import org.json.JSONException;
import org.json.JSONObject;

import io.droidspaces.nebula.core.NebulaCapability;
import io.droidspaces.nebula.core.NebulaCoreClient;
import io.droidspaces.nebula.core.NebulaCoreProtocol;
import io.droidspaces.nebula.core.NebulaCoreStatus;
import io.droidspaces.nebula.core.NebulaVersions;
import io.droidspaces.nebula.core.CommandResult;
import io.droidspaces.nebula.core.RedMagicProbe;
import io.droidspaces.nebula.features.nubia.NubiaDeviceAdapter;
import io.droidspaces.nebula.features.redmagic.RedMagicButtonAdapter;
import io.droidspaces.nebula.features.redmagic.RedMagicPerformanceAdapter;

public final class MainActivity extends Activity {
    private static final int BG = 0xFF111417;
    private static final int PANEL = 0xFF1B2026;
    private static final int PANEL_ALT = 0xFF202A33;
    private static final int TEXT = 0xFFF3F6F8;
    private static final int MUTED = 0xFFA8B3BD;
    private static final int BLUE = 0xFF5AA6FF;
    private static final int GREEN = 0xFF4CC38A;
    private static final int YELLOW = 0xFFF2C14E;
    private static final int RED = 0xFFF07178;
    private static final int NEON = 0xFF69FF35;
    private static final int CYAN = 0xFF00D9E8;
    private static final int HOT = 0xFFFF2E4F;
    private static final int LINE = 0xFF303A44;

    private static final String SIGNER_TERMUX =
            "228fb2cfe90831c1499ec3ccaf61e96e8e1ce70766b9474672ce427334d41c42";
    private static final String SIGNER_TERMUX_X11 =
            "b6da01480eefd5fbf2cd3771b8d1021ec791304bdd6c4bf41d3faabad48ee5e1";
    private static final String SIGNER_DROIDSPACES_DEBUG =
            "ad0fbbd2b608658bab14cab931827194db97a0222f1cd383782b16896f477057";
    private static final String SIGNER_WAYLANDIE_PROOF =
            "220bb57040d05fb36fee7caa12463b595551fcdd09210b6480f30bab93713b91";

    private final List<TargetProfile> targetProfiles = Arrays.asList(
            new TargetProfile(
                    "recovery_safe",
                    "Recovery / Safe Mode",
                    "safe",
                    "none",
                    "none",
                    true,
                    "Status-only mode with every launch path disabled.",
                    Arrays.asList("boot_completed", "no_unsafe_processes"),
                    Arrays.asList("DRM", "renderer", "compositor", "root write", "reboot")),
            new TargetProfile(
                    "phone_app_bridge",
                    "Phone / App Mode",
                    "app",
                    "waylandie",
                    "app_surface",
                    true,
                    "WayLandIE bridge profile. Selection is UI-only until backend wiring lands.",
                    Arrays.asList("boot_completed", "SurfaceFlinger PID", "composer PID"),
                    Arrays.asList("CREATE_LEASE", "composer fd probing", "wlroots DRM backend")),
            new TargetProfile(
                    "dock_drm_lease_external_monitor",
                    "Dock Mode",
                    "dock",
                    "drm_lease_receiver",
                    "external_display",
                    false,
                    "Blocked after RM11 crashdump triage. Needs receiver-only safety design first.",
                    Arrays.asList("crashdump gate", "old helper quarantine", "live safe DRM discovery", "explicit approval"),
                    Arrays.asList("composer fd probing", "SET_CLIENT_CAP on composer fd", "blind CREATE_LEASE",
                            "hard-coded connector/CRTC/plane IDs")),
            new TargetProfile(
                    "compat_gamescope_xwayland",
                    "Compatibility Mode",
                    "compatibility",
                    "gamescope",
                    "compatibility_runtime",
                    false,
                    "Blocked until App Mode is stable and selected intentionally.",
                    Arrays.asList("stable App Mode", "isolated runtime", "no Dock Mode dependency"),
                    Arrays.asList("DRM lease", "composer fd probing", "external display mutation")));

    private final List<Lane> lanes = Arrays.asList(
            new Lane(
                    "Safe desktop",
                    "Termux + Termux:X11",
                    "Low-risk desktop route for XFCE/KDE while Wayland work matures.",
                    "Expected proof: overlay app-op allowed, desktop launches, no black-screen regression.",
                    Arrays.asList(
                            new Target("Termux", "com.termux", "0.118.3", SIGNER_TERMUX, true),
                            new Target("Termux:API", "com.termux.api", "0.53.0", SIGNER_TERMUX, false),
                            new Target("Termux:X11", "com.termux.x11", null, SIGNER_TERMUX_X11, true))),
            new Lane(
                    "Zero-copy display",
                    "WayLandIE proof",
                    "dmabuf/fd-passing display target for Linux apps and games.",
                    "Expected proof: bridge fd test and dmabuf metadata test pass before replacing anything.",
                    Arrays.asList(
                            new Target("WayLandIE Display", "io.waylandie.display", "0.1.0",
                                    SIGNER_WAYLANDIE_PROOF, true))),
            new Lane(
                    "DroidSpaces container",
                    "Container runtime",
                    "Current DroidSpaces app lane for real Linux containers on Android.",
                    "Expected proof: v6.3.0 runtime build and container logs are preserved.",
                    Arrays.asList(
                            new Target("DroidSpaces", "com.droidspaces.app", "6.3.0",
                                    SIGNER_DROIDSPACES_DEBUG, true))),
            new Lane(
                    "Native compositor",
                    "wlroots bridge reference",
                    "Experimental Activity/Binder/AHardwareBuffer route for direct Android surfaces.",
                    "Reference only until RedMagic/Adreno proof exists and license boundaries are documented.",
                    new ArrayList<>()),
            new Lane(
                    "Steam/Proton",
                    "Game runtime reference",
                    "WinNative, GameNative, Proton, Wine, WCP, and PulseAudio leads for the gamer edition.",
                    "Parked until the display lane is repeatable; do not vendor proprietary payloads into Nebula.",
                    new ArrayList<>()),
            new Lane(
                    "PowerDeck",
                    "Dry-run root module",
                    "RM11Pro fan, pump, display, GPU, thermal, and app-profile automation.",
                    "Nebula does not write nodes. Use PowerDeck dry-run and snapshot/restore first.",
                    new ArrayList<>()),
            new Lane(
                    "RedMagic controls",
                    "Nubia Toolkit + Control Center",
                    "Hook and hardware-control reference lane for the later PowerDeck UI.",
                    "Keep this as a reference until node behavior is proven on-device.",
                    Arrays.asList(
                            new Target("RedMagic Control Center", "com.elitedarkkaiser.redmagic", null, null, false),
                            new Target("Nubia Game Assist", "cn.nubia.gameassist", null, null, false),
                            new Target("Nubia Game Launcher", "cn.nubia.gamelauncher", null, null, false))),
            new Lane(
                    "Vower reference",
                    "Build-pass lead",
                    "Vower WayLandIE has useful diagnostics/setup ideas but conflicts with the proof package signer.",
                    "Do not install over the proof lane without an intentional uninstall/reinstall test.",
                    new ArrayList<>()));

    private LinearLayout laneContainer;
    private LinearLayout targetProfileContainer;
    private LinearLayout coreContainer;
    private LinearLayout autoCoolingContainer;
    private LinearLayout systemTargetContainer;
    private LinearLayout statusRailContainer;
    private LinearLayout deviceToolsContainer;
    private LinearLayout performanceContainer;
    private LinearLayout redMagicButtonContainer;
    private TextView reportView;
    private String selectedTargetProfileId = "recovery_safe";
    private final NebulaCoreClient coreClient = new NebulaCoreClient();
    private final NubiaDeviceAdapter nubiaDeviceAdapter = new NubiaDeviceAdapter();
    private final RedMagicPerformanceAdapter redMagicPerformanceAdapter = new RedMagicPerformanceAdapter();
    private final RedMagicButtonAdapter redMagicButtonAdapter = new RedMagicButtonAdapter();
    private NebulaCoreStatus coreStatus = NebulaCoreStatus.absent("Not refreshed");
    private RedMagicProbe redMagicProbe = RedMagicProbe.unavailable("Not refreshed");
    private JSONObject adbWifiModuleStatus;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        tintLegacySystemBars();
        setContentView(buildContent());
        refresh();
    }

    @SuppressWarnings("deprecation")
    private void tintLegacySystemBars() {
        if (Build.VERSION.SDK_INT < 35) {
            getWindow().setStatusBarColor(BG);
            getWindow().setNavigationBarColor(BG);
        }
    }

    @SuppressWarnings("deprecation")
    private View buildContent() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(BG);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        final int horizontalPadding = dp(14);
        final int topPadding = dp(18);
        final int bottomPadding = dp(24);
        root.setPadding(horizontalPadding, topPadding, horizontalPadding, bottomPadding);
        scroll.setOnApplyWindowInsetsListener((view, insets) -> {
            root.setPadding(
                    horizontalPadding,
                    topPadding + insets.getSystemWindowInsetTop(),
                    horizontalPadding,
                    bottomPadding + insets.getSystemWindowInsetBottom());
            return insets;
        });
        scroll.addView(root, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        root.addView(buildDeckHeader());
        systemTargetContainer = new LinearLayout(this);
        systemTargetContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(systemTargetContainer);

        root.addView(buildHeroPanel());

        statusRailContainer = new LinearLayout(this);
        statusRailContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(statusRailContainer);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        actions.setPadding(0, 0, 0, dp(12));
        root.addView(actions);

        Button refresh = actionButton("Refresh", BLUE);
        refresh.setOnClickListener(v -> refresh());
        actions.addView(refresh, weightedButtonParams());

        Button copy = actionButton("Copy report", NEON);
        copy.setOnClickListener(v -> copyReport());
        actions.addView(copy, weightedButtonParams());

        Button share = actionButton("Share", YELLOW);
        share.setOnClickListener(v -> shareReport());
        actions.addView(share, weightedButtonParams());

        root.addView(sectionTitle("System Layer"));

        coreContainer = new LinearLayout(this);
        coreContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(coreContainer);

        root.addView(sectionTitle("Automation"));

        autoCoolingContainer = new LinearLayout(this);
        autoCoolingContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(autoCoolingContainer);

        root.addView(sectionTitle("Targets"));

        targetProfileContainer = new LinearLayout(this);
        targetProfileContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(targetProfileContainer);

        root.addView(sectionTitle("Device Tools"));

        deviceToolsContainer = new LinearLayout(this);
        deviceToolsContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(deviceToolsContainer);

        root.addView(sectionTitle("Performance"));

        performanceContainer = new LinearLayout(this);
        performanceContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(performanceContainer);

        root.addView(sectionTitle("RedMagic Button"));

        redMagicButtonContainer = new LinearLayout(this);
        redMagicButtonContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(redMagicButtonContainer);

        root.addView(sectionTitle("Runtime Lanes"));

        laneContainer = new LinearLayout(this);
        laneContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(laneContainer);

        reportView = text("", 12, MUTED, Typeface.NORMAL);
        reportView.setTypeface(Typeface.MONOSPACE);
        reportView.setTextIsSelectable(true);
        reportView.setPadding(dp(12), dp(12), dp(12), dp(12));
        reportView.setBackground(round(PANEL_ALT, dp(8), LINE));
        LinearLayout.LayoutParams reportParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        reportParams.topMargin = dp(10);
        root.addView(reportView, reportParams);

        return scroll;
    }

    private void refresh() {
        coreStatus = coreClient.loadStatus();
        redMagicProbe = loadRedMagicProbe(coreStatus);
        adbWifiModuleStatus = loadAdbWifiModuleStatus();

        systemTargetContainer.removeAllViews();
        systemTargetContainer.addView(buildSystemTargetBar());

        statusRailContainer.removeAllViews();
        statusRailContainer.addView(buildStatusRail());

        coreContainer.removeAllViews();
        coreContainer.addView(buildCoreCard(coreStatus));

        autoCoolingContainer.removeAllViews();
        autoCoolingContainer.addView(buildAutoCoolingCard(redMagicProbe));

        targetProfileContainer.removeAllViews();
        for (TargetProfile profile : targetProfiles) {
            targetProfileContainer.addView(buildTargetProfileCard(profile));
        }

        deviceToolsContainer.removeAllViews();
        deviceToolsContainer.addView(buildCapabilityCard(
                "Audited Nubia capability status", nubiaDeviceAdapter.discover(this)));
        deviceToolsContainer.addView(buildAdbWifiCard());

        performanceContainer.removeAllViews();
        performanceContainer.addView(buildCapabilityCard(
                "Audited RedMagic capability status",
                redMagicPerformanceAdapter.discover(this, redMagicProbe)));

        redMagicButtonContainer.removeAllViews();
        redMagicButtonContainer.addView(buildCapabilityCard(
                "Mapping disabled in pass 01", redMagicButtonAdapter.discover(this)));

        laneContainer.removeAllViews();
        for (Lane lane : lanes) {
            laneContainer.addView(buildLaneCard(lane));
        }
        reportView.setText(buildReport());
    }

    private RedMagicProbe loadRedMagicProbe(NebulaCoreStatus status) {
        if (!status.installed || status.hasVisibleError()) {
            return RedMagicProbe.unavailable("Module unavailable; app remains read-only.");
        }
        CommandResult result = coreClient.redMagicProbe();
        if (!result.ok()) {
            String reason = result.stderr.isEmpty() ? result.stdout : result.stderr;
            if (reason.isEmpty()) reason = "exit " + result.exitCode;
            return RedMagicProbe.unavailable(reason);
        }
        return NebulaCoreProtocol.parseRedMagicProbe(result.stdout);
    }

    private View buildDeckHeader() {
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(4), 0, dp(4), dp(12));

        TextView brand = text("REDMAGIC // NEBULA", 17, TEXT, Typeface.BOLD);
        brand.setLetterSpacing(0.08f);
        header.addView(brand, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        TextView device = text("RM11 PRO", 14, HOT, Typeface.BOLD);
        device.setGravity(Gravity.RIGHT);
        device.setLetterSpacing(0.08f);
        header.addView(device);
        return header;
    }

    private View buildHeroPanel() {
        FrameLayout hero = new FrameLayout(this);
        hero.setBackground(round(0xFF05080A, dp(4), 0xFF163027));

        ImageView art = new ImageView(this);
        art.setImageResource(R.drawable.nebula_logo_hero_v2);
        art.setScaleType(ImageView.ScaleType.CENTER_CROP);
        art.setAlpha(0.94f);
        hero.addView(art, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));

        LinearLayout overlay = new LinearLayout(this);
        overlay.setOrientation(LinearLayout.VERTICAL);
        overlay.setGravity(Gravity.BOTTOM);
        overlay.setPadding(dp(16), dp(14), dp(16), dp(14));
        hero.addView(overlay, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));

        TextView lane = text("WAYLAND // DROIDSPACES // POWERDECK", 12, CYAN, Typeface.BOLD);
        lane.setLetterSpacing(0.18f);
        overlay.addView(lane);

        TextView title = text("DROIDSPACES: NEBULA", 28, TEXT, Typeface.BOLD);
        title.setPadding(0, dp(4), 0, 0);
        overlay.addView(title);

        TextView sub = text("ONE APP. ONE CORE MODULE. AUTOMATED WHEN PROVEN.", 12, MUTED, Typeface.BOLD);
        sub.setLetterSpacing(0.1f);
        sub.setPadding(0, dp(4), 0, 0);
        overlay.addView(sub);

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(360));
        params.bottomMargin = dp(12);
        hero.setLayoutParams(params);
        return hero;
    }

    private View buildSystemTargetBar() {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(12), dp(12), dp(12), dp(12));
        bar.setBackground(round(0xFF0A0E13, dp(4), 0xFF29313B));

        bar.addView(identityBlock("SYSTEM LAYER", "NEBULA CORE",
                coreStatus.installed ? "ONLINE" : "READ-ONLY", NEON),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        TextView mark = text("N", 30, HOT, Typeface.BOLD);
        mark.setGravity(Gravity.CENTER);
        mark.setBackground(round(0x22000000, dp(18), 0x5531FF42));
        LinearLayout.LayoutParams markParams = new LinearLayout.LayoutParams(dp(58), dp(58));
        markParams.setMargins(dp(8), 0, dp(8), 0);
        bar.addView(mark, markParams);

        bar.addView(identityBlock("DEVICE TARGET", "RM11 PRO",
                Build.VERSION.RELEASE == null ? "ANDROID" : "ANDROID " + Build.VERSION.RELEASE,
                HOT), new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        params.bottomMargin = dp(12);
        bar.setLayoutParams(params);
        return bar;
    }

    private View identityBlock(String eyebrow, String title, String detail, int color) {
        LinearLayout block = new LinearLayout(this);
        block.setOrientation(LinearLayout.VERTICAL);
        block.setPadding(dp(4), 0, dp(4), 0);

        TextView eyebrowView = text(eyebrow, 10, MUTED, Typeface.BOLD);
        eyebrowView.setLetterSpacing(0.18f);
        block.addView(eyebrowView);

        TextView titleView = text(title, 18, color, Typeface.BOLD);
        titleView.setLetterSpacing(0.05f);
        titleView.setPadding(0, dp(3), 0, 0);
        block.addView(titleView);

        TextView detailView = text(detail, 11, TEXT, Typeface.BOLD);
        detailView.setLetterSpacing(0.08f);
        detailView.setPadding(0, dp(4), 0, 0);
        block.addView(detailView);
        return block;
    }

    private View buildStatusRail() {
        LinearLayout rail = new LinearLayout(this);
        rail.setOrientation(LinearLayout.HORIZONTAL);
        rail.setPadding(0, 0, 0, dp(12));
        rail.addView(statusCell("DROIDSPACES", "runtime active", NEON), weightedButtonParams());
        rail.addView(statusCell("WAYLANDIE", "bridge ready", CYAN), weightedButtonParams());
        rail.addView(statusCell("ADRENO 840", "Turnip 26.2", TEXT), weightedButtonParams());
        rail.addView(statusCell("NTSYNC", "kernel enabled", TEXT), weightedButtonParams());
        rail.addView(statusCell("SELINUX", "enforcing", TEXT), weightedButtonParams());
        rail.addView(statusCell("POWERDECK", coolingPolicyLabel(redMagicProbe),
                coolingPolicyColor(redMagicProbe)), weightedButtonParams());
        return rail;
    }

    private View statusCell(String title, String detail, int color) {
        LinearLayout cell = new LinearLayout(this);
        cell.setOrientation(LinearLayout.VERTICAL);
        cell.setPadding(dp(5), dp(8), dp(5), dp(8));
        cell.setBackground(round(0xFF0C1115, dp(2), 0xFF25313A));

        TextView label = text(title, 9, color, Typeface.BOLD);
        label.setSingleLine(true);
        cell.addView(label);

        TextView value = text(detail, 8, MUTED, Typeface.NORMAL);
        value.setSingleLine(true);
        value.setPadding(0, dp(2), 0, 0);
        cell.addView(value);
        return cell;
    }

    private TextView sectionTitle(String value) {
        TextView view = text(value.toUpperCase(Locale.US), 17, TEXT, Typeface.BOLD);
        view.setLetterSpacing(0.14f);
        view.setPadding(dp(4), dp(4), 0, dp(8));
        return view;
    }

    private View buildCoreCard(NebulaCoreStatus status) {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        titleBox.addView(text("Droidspaces: Nebula Core", 19, TEXT, Typeface.BOLD));
        TextView meta = text("app=" + NebulaVersions.APP_VERSION
                + "  expectedModule=" + NebulaVersions.MODULE_VERSION
                + "  protocol=" + NebulaVersions.CORE_PROTOCOL_VERSION,
                12, MUTED, Typeface.NORMAL);
        meta.setTypeface(Typeface.MONOSPACE);
        meta.setPadding(0, dp(4), 0, 0);
        titleBox.addView(meta);

        top.addView(chip(coreStatusLabel(status), coreStatusColor(status)));

        TextView detail = text(coreDetail(status), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(10), 0, 0);
        card.addView(detail);

        if (status.hasVisibleError()) {
            TextView error = text(status.visibleError(), 13, YELLOW, Typeface.NORMAL);
            error.setPadding(0, dp(10), 0, 0);
            card.addView(error);
        }

        return card;
    }

    private String coreStatusLabel(NebulaCoreStatus status) {
        if (!status.installed) return "Read-only";
        if (status.hasVisibleError()) return "Check";
        return status.daemonRunning ? "Running" : "State";
    }

    private int coreStatusColor(NebulaCoreStatus status) {
        if (!status.installed) return BLUE;
        if (status.hasVisibleError()) return YELLOW;
        return status.daemonRunning ? GREEN : BLUE;
    }

    private String coreDetail(NebulaCoreStatus status) {
        return "moduleInstalled=" + status.installed
                + "\nmoduleVersion=" + status.moduleVersion
                + "\nprotocolVersion=" + status.protocolVersion
                + "\nsafeMode=" + status.safeMode
                + "\nprofile=" + status.profile.wireName
                + "\ndaemonRunning=" + status.daemonRunning
                + "\nserviceStatus=" + status.serviceStatus
                + "\ngitCommit=" + status.gitCommit
                + "\nrootExecution=" + coreClient.executionModeLabel()
                + "\nmoduleDispatch=" + coreClient.moduleDispatchLabel();
    }

    private View buildAutoCoolingCard(RedMagicProbe probe) {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        TextView title = text("Cooling Engine", 19, TEXT, Typeface.BOLD);
        title.setLetterSpacing(0.04f);
        titleBox.addView(title);

        TextView subtitle = text("module policy preview: " + coolingPolicyReason(probe),
                12, MUTED, Typeface.NORMAL);
        subtitle.setTypeface(Typeface.MONOSPACE);
        subtitle.setPadding(0, dp(4), 0, 0);
        titleBox.addView(subtitle);

        top.addView(chip(coolingPolicyLabel(probe), coolingPolicyColor(probe)));

        card.addView(progressRow("policy response", coolingLoadPercent(probe),
                coolingPolicyColor(probe)));

        LinearLayout metrics = new LinearLayout(this);
        metrics.setOrientation(LinearLayout.HORIZONTAL);
        metrics.setPadding(0, dp(12), 0, 0);
        card.addView(metrics);

        metrics.addView(metricTile("Thermal Max", thermalText(probe)), weightedButtonParams());
        metrics.addView(metricTile("Internal Fan", fanText(probe)), weightedButtonParams());
        metrics.addView(metricTile("Liquid Pump", pumpText(probe)), weightedButtonParams());

        TextView source = text(coolingSourceText(probe), 12, MUTED, Typeface.NORMAL);
        source.setTypeface(Typeface.MONOSPACE);
        source.setPadding(0, dp(12), 0, 0);
        card.addView(source);

        TextView guardrail = text("PREVIEW ONLY  //  fanApplied=false  pumpApplied=false  //  no writes",
                12, YELLOW, Typeface.BOLD);
        guardrail.setTypeface(Typeface.MONOSPACE);
        guardrail.setPadding(0, dp(12), 0, 0);
        card.addView(guardrail);
        return card;
    }

    private String coolingPolicyLabel(RedMagicProbe probe) {
        if (probe == null || probe.coolingPolicy == null || !probe.coolingPolicy.available) {
            return "Unavailable";
        }
        String state = probe.coolingPolicy.state == null ? "UNAVAILABLE" : probe.coolingPolicy.state;
        if ("SAFE_MODE".equals(state)) return "Safe Mode";
        if ("COOL".equals(state)) return "Cool";
        if ("BALANCED".equals(state)) return "Balanced";
        if ("HOT".equals(state)) return "Hot";
        if ("CRITICAL".equals(state)) return "Critical";
        return "Unavailable";
    }

    private int coolingPolicyColor(RedMagicProbe probe) {
        if (probe == null || probe.coolingPolicy == null || !probe.coolingPolicy.available) {
            return BLUE;
        }
        String state = probe.coolingPolicy.state == null ? "UNAVAILABLE" : probe.coolingPolicy.state;
        if ("CRITICAL".equals(state)) return HOT;
        if ("HOT".equals(state)) return YELLOW;
        if ("BALANCED".equals(state)) return CYAN;
        if ("COOL".equals(state)) return NEON;
        if ("SAFE_MODE".equals(state)) return BLUE;
        return BLUE;
    }

    private String coolingPolicyReason(RedMagicProbe probe) {
        if (probe == null || !probe.available || probe.coolingPolicy == null
                || !probe.coolingPolicy.available) {
            return "waiting for module policy telemetry";
        }
        if (probe.coolingPolicy.errorSummary != null
                && !probe.coolingPolicy.errorSummary.isEmpty()) {
            return probe.coolingPolicy.errorSummary;
        }
        return probe.coolingPolicy.reasonSummary;
    }

    private int coolingLoadPercent(RedMagicProbe probe) {
        if (probe == null || probe.coolingPolicy == null || !probe.coolingPolicy.available) {
            return 0;
        }
        String state = probe.coolingPolicy.state == null ? "UNAVAILABLE" : probe.coolingPolicy.state;
        if ("CRITICAL".equals(state)) return 100;
        if ("HOT".equals(state)) return 75;
        if ("BALANCED".equals(state)) return 50;
        if ("COOL".equals(state)) return 25;
        if ("SAFE_MODE".equals(state)) return 15;
        return 0;
    }

    private String thermalText(RedMagicProbe probe) {
        Double temp = probe.coolingPolicy == null ? null : probe.coolingPolicy.controllingTemperatureC;
        if (temp == null) temp = probe.maxThermalC;
        if (temp == null) return "unavailable";
        int count = probe.coolingPolicy == null || !probe.coolingPolicy.available
                ? probe.thermalReadingCount : probe.coolingPolicy.validSensorCount;
        return String.format(Locale.US, "%.1f C / %d zones", temp, count);
    }

    private String fanText(RedMagicProbe probe) {
        String state = probe.fanEnabled == null ? "unknown" : (probe.fanEnabled ? "on" : "off");
        String rpm = probe.fanRpm == null ? "rpm ?" : probe.fanRpm + " rpm";
        String level = probe.fanLevel == null ? "level ?" : "level " + probe.fanLevel;
        String intent = probe.coolingPolicy == null ? "unavailable" : probe.coolingPolicy.fanIntent;
        return state + " / " + rpm + " / " + level + "\nintent " + intent;
    }

    private String pumpText(RedMagicProbe probe) {
        if (!probe.pumpPresent) return "not detected";
        String state = probe.pumpEnabled == null ? "unknown" : (probe.pumpEnabled ? "on" : "off");
        String speed = probe.pumpSpeed == null ? "speed ?" : "speed " + probe.pumpSpeed;
        String intent = probe.coolingPolicy == null ? "unavailable" : probe.coolingPolicy.pumpIntent;
        String freq = probe.coolingPolicy == null || probe.coolingPolicy.pumpFreq == null
                ? "freq ?" : "freq " + probe.coolingPolicy.pumpFreq;
        return state + " / " + speed + " / " + freq + "\nintent " + intent;
    }

    private String coolingSourceText(RedMagicProbe probe) {
        if (probe == null || probe.coolingPolicy == null || !probe.coolingPolicy.available) {
            return "source=unavailable  confidence=module_policy_missing";
        }
        RedMagicProbe.CoolingPolicy policy = probe.coolingPolicy;
        return "state=" + policy.state
                + "  previewOnly=" + policy.previewOnly
                + "  configured=" + policy.configured
                + "  safeMode=" + policy.safeMode
                + "\nsource=" + policy.thresholdSource
                + "  sensor=" + policy.controllingSensorName
                + "  rejectedSensors=" + policy.rejectedSensorCount;
    }

    private View metricTile(String label, String value) {
        LinearLayout tile = new LinearLayout(this);
        tile.setOrientation(LinearLayout.VERTICAL);
        tile.setPadding(dp(10), dp(10), dp(10), dp(10));
        tile.setBackground(round(0xFF0B1014, dp(2), 0xFF25313A));

        TextView valueView = text(value, 14, TEXT, Typeface.BOLD);
        valueView.setMinHeight(dp(42));
        tile.addView(valueView);

        TextView labelView = text(label.toUpperCase(Locale.US), 10, MUTED, Typeface.BOLD);
        labelView.setLetterSpacing(0.08f);
        tile.addView(labelView);
        return tile;
    }

    private View progressRow(String label, int percent, int color) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(0, dp(12), 0, 0);

        LinearLayout line = new LinearLayout(this);
        line.setOrientation(LinearLayout.HORIZONTAL);
        line.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(line);

        TextView name = text(label, 12, MUTED, Typeface.NORMAL);
        line.addView(name, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        line.addView(text(percent + "%", 12, TEXT, Typeface.BOLD));

        LinearLayout track = new LinearLayout(this);
        track.setOrientation(LinearLayout.HORIZONTAL);
        track.setBackground(round(0xFF121A20, dp(1), 0xFF121A20));
        LinearLayout.LayoutParams trackParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(10));
        trackParams.topMargin = dp(6);
        row.addView(track, trackParams);

        View fill = new View(this);
        fill.setBackgroundColor(color);
        track.addView(fill, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.MATCH_PARENT, Math.max(1, percent)));
        View empty = new View(this);
        track.addView(empty, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.MATCH_PARENT, Math.max(0, 100 - percent)));
        return row;
    }

    private View buildCapabilityCard(String title, List<NebulaCapability> capabilities) {
        LinearLayout card = baseCard();
        card.addView(text(title, 19, TEXT, Typeface.BOLD));
        for (NebulaCapability capability : capabilities) {
            card.addView(buildCapabilityRow(capability));
        }
        return card;
    }

    private View buildAdbWifiCard() {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        titleBox.addView(text("ADB Wi-Fi", 19, TEXT, Typeface.BOLD));
        TextView detail = text(adbWifiDetail(), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(4), 0, 0);
        titleBox.addView(detail);

        top.addView(chip(adbWifiStatus(), adbWifiColor()));

        boolean coreAvailable = coreStatus.installed && !coreStatus.hasVisibleError();
        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);

        Button enable = smallButton("Enable", NEON);
        enable.setEnabled(coreAvailable);
        enable.setOnClickListener(v -> enableAdbWifiWithNebula());
        buttons.addView(enable, weightedButtonParams());

        Button autoOff = smallButton("Auto off", PANEL_ALT);
        autoOff.setEnabled(coreAvailable);
        autoOff.setOnClickListener(v -> disableAdbWifiAutoEnable());
        buttons.addView(autoOff, weightedButtonParams());

        Button open = smallButton("Settings", CYAN);
        open.setOnClickListener(v -> openWirelessDebuggingSettings());
        buttons.addView(open, weightedButtonParams());

        LinearLayout.LayoutParams buttonParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        buttonParams.topMargin = dp(12);
        card.addView(buttons, buttonParams);

        return card;
    }

    private String adbWifiStatus() {
        JSONObject module = adbWifiModuleStatusObject();
        if (module != null) {
            String state = module.optString("activation_state", "");
            if ("live".equals(state)) return "Live";
            if ("manual_toggle_required".equals(state)) return "Manual";
            if ("disabled".equals(state)) return "Disabled";
        }
        int value = adbWifiEffectiveSetting();
        if (value == 1) return "Enabled";
        if (value == 0) return "Disabled";
        return "Android";
    }

    private int adbWifiColor() {
        JSONObject module = adbWifiModuleStatusObject();
        if (module != null) {
            String state = module.optString("activation_state", "");
            if ("live".equals(state)) return GREEN;
            if ("manual_toggle_required".equals(state)) return YELLOW;
            if ("disabled".equals(state)) return MUTED;
        }
        int value = adbWifiEffectiveSetting();
        if (value == 1) return GREEN;
        if (value == 0) return YELLOW;
        return BLUE;
    }

    private int adbWifiEffectiveSetting() {
        int uiSwitch = globalSettingInt("enable_wireless_switch", -1);
        if (uiSwitch == 1 || uiSwitch == 0) {
            return uiSwitch;
        }
        return globalSettingInt("adb_wifi_enabled", -1);
    }

    private String adbWifiDetail() {
        int wireless = globalSettingInt("adb_wifi_enabled", -1);
        int uiSwitch = globalSettingInt("enable_wireless_switch", -1);
        int adb = globalSettingInt("adb_enabled", -1);
        return "wirelessDebugging=" + settingLabel(adbWifiEffectiveSetting())
                + "\nuiWirelessSwitch=" + settingLabel(uiSwitch)
                + "\nsettingsWireless=" + settingLabel(wireless)
                + "\nadbDebugging=" + settingLabel(adb)
                + "\n" + adbWifiModuleDetail()
                + "\ncontrol=Nebula Core opt-in"
                + "\nmutation=fixed_adb_wifi_request_only";
    }

    private String adbWifiModuleDetail() {
        JSONObject object = adbWifiModuleStatusObject();
        if (object == null) {
            return "moduleAuto=unknown";
        }
        if (!object.has("auto_enable") || object.isNull("auto_enable")) {
            return "moduleAuto=unknown";
        }
        String auto = object.optBoolean("auto_enable", false) ? "enabled" : "disabled";
        String uiSwitch = jsonBoolLabel(object, "ui_wireless_switch");
        String settingsWireless = jsonBoolLabel(object, "settings_wireless_debugging");
        String requested = jsonBoolLabel(object, "settings_requested");
        String manualRequired = jsonBoolLabel(object, "manual_toggle_required");
        String port = object.isNull("wireless_port")
                ? "unknown" : String.valueOf(object.optInt("wireless_port", 0));
        return "moduleAuto=" + auto
                + "\nmoduleState=" + object.optString("activation_state", "unknown")
                + "\nmoduleUiSwitch=" + uiSwitch
                + "\nmoduleSettingsWireless=" + settingsWireless
                + "\nmoduleRequested=" + requested
                + "\nmoduleManualRequired=" + manualRequired
                + "\nmoduleWirelessPort=" + port;
    }

    private JSONObject adbWifiModuleStatusObject() {
        return adbWifiModuleStatus;
    }

    private JSONObject loadAdbWifiModuleStatus() {
        if (!coreStatus.installed || coreStatus.hasVisibleError()) {
            return null;
        }
        CommandResult result = coreClient.adbWifiStatus();
        if (!result.ok()) {
            return null;
        }
        try {
            return new JSONObject(result.stdout);
        } catch (JSONException error) {
            return null;
        }
    }

    private String jsonBoolLabel(JSONObject object, String key) {
        if (!object.has(key) || object.isNull(key)) {
            return "unknown";
        }
        return object.optBoolean(key, false) ? "enabled" : "disabled";
    }

    private void enableAdbWifiWithNebula() {
        CommandResult result = coreClient.adbWifiEnable();
        if (result.ok()) {
            toast("ADB Wi-Fi live");
        } else {
            String manual = adbWifiManualRequiredMessage(result.stdout);
            toast(manual != null ? manual : commandMessage("ADB Wi-Fi enable", result));
        }
        refresh();
    }

    private String adbWifiManualRequiredMessage(String stdout) {
        try {
            JSONObject object = new JSONObject(stdout);
            if (object.optBoolean("manual_toggle_required", false)) {
                return "ADB Wi-Fi requested; toggle Wireless debugging once";
            }
        } catch (JSONException ignored) {
            return null;
        }
        return null;
    }

    private void disableAdbWifiAutoEnable() {
        CommandResult result = coreClient.adbWifiAutoDisable();
        toast(result.ok() ? "ADB Wi-Fi auto disabled" : commandMessage("ADB Wi-Fi auto disable", result));
        refresh();
    }

    private String commandMessage(String action, CommandResult result) {
        if (result.timedOut) return action + " timed out";
        String message = result.stderr.isEmpty() ? result.stdout : result.stderr;
        if (message.isEmpty()) message = "exit " + result.exitCode;
        if (message.length() > 80) message = message.substring(0, 80);
        return action + " failed: " + message;
    }

    private int globalSettingInt(String key, int fallback) {
        try {
            return Settings.Global.getInt(getContentResolver(), key);
        } catch (Settings.SettingNotFoundException | SecurityException ignored) {
            return fallback;
        }
    }

    private String settingLabel(int value) {
        if (value == 1) return "enabled";
        if (value == 0) return "disabled";
        return "unknown";
    }

    private void openWirelessDebuggingSettings() {
        Intent wireless = new Intent("android.settings.WIRELESS_DEBUGGING_SETTINGS");
        if (tryStartSettings(wireless)) {
            return;
        }
        Intent developer = new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS);
        if (!tryStartSettings(developer)) {
            toast("Developer options unavailable");
        }
    }

    private boolean tryStartSettings(Intent intent) {
        try {
            startActivity(intent);
            return true;
        } catch (ActivityNotFoundException error) {
            return false;
        }
    }

    private View buildCapabilityRow(NebulaCapability capability) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(0, dp(10), 0, dp(4));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(top);

        TextView label = text(capability.title, 15, TEXT, Typeface.BOLD);
        top.addView(label, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        top.addView(chip(capability.status, capabilityColor(capability.status)));

        TextView detail = text(capability.detail + "\nsource=" + capability.source
                        + "  mutating=" + capability.mutating,
                12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(6), 0, 0);
        row.addView(detail);

        return row;
    }

    private int capabilityColor(String status) {
        if (status == null) return BLUE;
        if (status.contains("confirmed") || status.contains("visible")
                || status.contains("available") || status.contains("permission")) {
            return GREEN;
        }
        if (status.contains("blocked") || status.contains("BLOCKED")
                || status.contains("disabled") || status.contains("required")
                || status.contains("reference")) {
            return YELLOW;
        }
        if (status.contains("missing") || status.contains("unconfirmed")) {
            return RED;
        }
        return BLUE;
    }

    private View buildTargetProfileCard(TargetProfile profile) {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        titleBox.addView(text(profile.label, 19, TEXT, Typeface.BOLD));
        TextView meta = text("mode=" + profile.mode + "  backend=" + profile.backend
                + "  risk=" + profile.riskClass, 12, MUTED, Typeface.NORMAL);
        meta.setTypeface(Typeface.MONOSPACE);
        meta.setPadding(0, dp(4), 0, 0);
        titleBox.addView(meta);

        top.addView(chip(profileStatusLabel(profile), profileStatusColor(profile)));

        TextView summary = text(profile.summary, 14, MUTED, Typeface.NORMAL);
        summary.setPadding(0, dp(10), 0, dp(8));
        card.addView(summary);

        TextView preflight = text("preflight: " + joinInline(profile.preflight),
                12, MUTED, Typeface.NORMAL);
        preflight.setTypeface(Typeface.MONOSPACE);
        preflight.setPadding(0, 0, 0, dp(5));
        card.addView(preflight);

        TextView forbidden = text("forbidden: " + joinInline(profile.forbiddenActions),
                12, MUTED, Typeface.NORMAL);
        forbidden.setTypeface(Typeface.MONOSPACE);
        forbidden.setPadding(0, 0, 0, dp(10));
        card.addView(forbidden);

        Button select = smallButton(profile.enabled ? "Select" : "Blocked",
                profile.enabled ? BLUE : PANEL_ALT);
        select.setEnabled(profile.enabled);
        select.setAlpha(profile.enabled ? 1f : 0.45f);
        select.setOnClickListener(v -> selectProfile(profile));
        card.addView(select, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        return card;
    }

    private void selectProfile(TargetProfile profile) {
        if (!profile.enabled) {
            toast(profile.label + " is blocked");
            return;
        }
        selectedTargetProfileId = profile.id;
        toast(profile.label + " selected");
        refresh();
    }

    private String profileStatusLabel(TargetProfile profile) {
        if (profile.id.equals(selectedTargetProfileId)) return "Selected";
        return profile.enabled ? "Ready" : "Blocked";
    }

    private int profileStatusColor(TargetProfile profile) {
        if (profile.id.equals(selectedTargetProfileId)) return GREEN;
        return profile.enabled ? BLUE : RED;
    }

    private View buildLaneCard(Lane lane) {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        titleBox.addView(text(lane.name, 19, TEXT, Typeface.BOLD));
        TextView mode = text(lane.mode, 13, MUTED, Typeface.NORMAL);
        mode.setPadding(0, dp(3), 0, 0);
        titleBox.addView(mode);

        LaneStatus laneStatus = evaluate(lane);
        TextView chip = chip(laneStatus.label, laneStatus.color);
        top.addView(chip);

        TextView description = text(lane.description, 14, MUTED, Typeface.NORMAL);
        description.setPadding(0, dp(10), 0, dp(8));
        card.addView(description);

        if (lane.targets.isEmpty()) {
            TextView note = text(lane.note, 13, MUTED, Typeface.NORMAL);
            note.setPadding(0, 0, 0, 0);
            card.addView(note);
            return card;
        }

        for (Target target : lane.targets) {
            card.addView(buildTargetRow(target));
        }

        TextView note = text(lane.note, 12, MUTED, Typeface.NORMAL);
        note.setPadding(0, dp(10), 0, 0);
        card.addView(note);

        return card;
    }

    private View buildTargetRow(Target target) {
        PackageState state = inspect(target);

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(0, dp(8), 0, dp(4));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(top);

        TextView label = text(target.label, 15, TEXT, Typeface.BOLD);
        top.addView(label, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        top.addView(chip(state.label, state.color));

        TextView detail = text(state.detail, 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(6), 0, dp(8));
        row.addView(detail);

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        row.addView(buttons);

        Button open = smallButton("Open", BLUE);
        open.setEnabled(state.installed);
        open.setAlpha(state.installed ? 1f : 0.45f);
        open.setOnClickListener(v -> launchPackage(target.packageName));
        buttons.addView(open, weightedButtonParams());

        Button info = smallButton("Info", PANEL_ALT);
        info.setOnClickListener(v -> openAppInfo(target.packageName));
        buttons.addView(info, weightedButtonParams());

        return row;
    }

    private LaneStatus evaluate(Lane lane) {
        if (lane.targets.isEmpty()) {
            if ("PowerDeck".equals(lane.name)) {
                return new LaneStatus("Manual", YELLOW);
            }
            return new LaneStatus("Reference", BLUE);
        }

        boolean requiredMissing = false;
        boolean mismatch = false;
        boolean anyInstalled = false;
        for (Target target : lane.targets) {
            PackageState state = inspect(target);
            anyInstalled |= state.installed;
            requiredMissing |= target.required && !state.installed;
            mismatch |= state.installed && state.mismatch;
        }
        if (mismatch) return new LaneStatus("Check", YELLOW);
        if (requiredMissing) return new LaneStatus(anyInstalled ? "Partial" : "Missing", requiredMissing ? RED : YELLOW);
        return new LaneStatus("Ready", GREEN);
    }

    private PackageState inspect(Target target) {
        try {
            PackageInfo info = packageInfo(target.packageName);
            String version = info.versionName == null ? "unknown" : info.versionName;
            String signer = signerSha256(info);

            boolean versionMismatch = target.expectedVersion != null
                    && !target.expectedVersion.equals(version);
            boolean signerMismatch = target.expectedSigner != null
                    && (signer == null || !target.expectedSigner.equalsIgnoreCase(signer));
            boolean mismatch = versionMismatch || signerMismatch;

            String detail = "package=" + target.packageName
                    + "\nversion=" + version
                    + "\nsigner=" + shortHash(signer);
            if (versionMismatch) {
                detail += "\nexpectedVersion=" + target.expectedVersion;
            }
            if (signerMismatch) {
                detail += "\nexpectedSigner=" + shortHash(target.expectedSigner);
            }

            return new PackageState(true, mismatch, mismatch ? "Check" : "OK",
                    mismatch ? YELLOW : GREEN, detail, version, signer);
        } catch (PackageManager.NameNotFoundException error) {
            return new PackageState(false, false, target.required ? "Missing" : "Optional",
                    target.required ? RED : BLUE,
                    "package=" + target.packageName + "\nnot installed",
                    null, null);
        }
    }

    @SuppressWarnings("deprecation")
    private PackageInfo packageInfo(String packageName) throws PackageManager.NameNotFoundException {
        PackageManager pm = getPackageManager();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return pm.getPackageInfo(packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES));
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES);
        }
        return pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES);
    }

    @SuppressWarnings("deprecation")
    private String signerSha256(PackageInfo info) {
        Signature[] signatures;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && info.signingInfo != null) {
            signatures = info.signingInfo.hasMultipleSigners()
                    ? info.signingInfo.getApkContentsSigners()
                    : info.signingInfo.getSigningCertificateHistory();
        } else {
            signatures = info.signatures;
        }
        if (signatures == null || signatures.length == 0) return null;
        return sha256(signatures[0].toByteArray());
    }

    private String sha256(byte[] bytes) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] out = digest.digest(bytes);
            StringBuilder sb = new StringBuilder(out.length * 2);
            for (byte b : out) {
                sb.append(String.format(Locale.US, "%02x", b & 0xff));
            }
            return sb.toString();
        } catch (NoSuchAlgorithmException error) {
            return null;
        }
    }

    private String buildReport() {
        StringBuilder sb = new StringBuilder();
        sb.append("DroidSpaces Nebula Doctor v").append(NebulaVersions.APP_VERSION).append('\n');
        sb.append("Expected Nebula Core module: ").append(NebulaVersions.MODULE_VERSION).append('\n');
        sb.append("Expected Nebula Core protocol: ").append(NebulaVersions.CORE_PROTOCOL_VERSION).append('\n');
        sb.append("App Git commit: ").append(NebulaVersions.GIT_COMMIT).append('\n');
        sb.append("Generated: ").append(new SimpleDateFormat(
                "yyyy-MM-dd HH:mm:ss Z", Locale.US).format(new Date())).append('\n');
        sb.append("Device: ").append(Build.MANUFACTURER).append(' ')
                .append(Build.MODEL).append('\n');
        sb.append("Build.DEVICE: ").append(Build.DEVICE).append('\n');
        sb.append("Build.BOARD: ").append(Build.BOARD).append('\n');
        sb.append("Build.HARDWARE: ").append(Build.HARDWARE).append('\n');
        sb.append("SDK: ").append(Build.VERSION.SDK_INT).append('\n');
        sb.append("ABIs: ").append(Arrays.toString(Build.SUPPORTED_ABIS)).append("\n\n");

        sb.append("[Nebula Core]\n");
        sb.append("  installed=").append(coreStatus.installed).append('\n');
        sb.append("  moduleVersion=").append(coreStatus.moduleVersion).append('\n');
        sb.append("  protocolVersion=").append(coreStatus.protocolVersion).append('\n');
        sb.append("  safeMode=").append(coreStatus.safeMode).append('\n');
        sb.append("  profile=").append(coreStatus.profile.wireName).append('\n');
        sb.append("  daemonRunning=").append(coreStatus.daemonRunning).append('\n');
        sb.append("  serviceStatus=").append(coreStatus.serviceStatus).append('\n');
        sb.append("  rootExecution=").append(coreClient.executionModeLabel()).append('\n');
        sb.append("  moduleDispatch=").append(coreClient.moduleDispatchLabel()).append('\n');
        sb.append("  shellSuDiagnostic=host_only_not_authoritative\n");
        if (coreStatus.hasVisibleError()) {
            sb.append("  error=").append(coreStatus.visibleError()).append('\n');
        }
        sb.append("  redMagicProbe=").append(redMagicProbe.available).append('\n');
        sb.append("  coolingPolicyState=").append(redMagicProbe.coolingPolicy.state).append('\n');
        sb.append("  coolingPreviewOnly=").append(redMagicProbe.coolingPolicy.previewOnly).append('\n');
        sb.append("  coolingFanIntent=").append(redMagicProbe.coolingPolicy.fanIntent).append('\n');
        sb.append("  coolingPumpIntent=").append(redMagicProbe.coolingPolicy.pumpIntent).append('\n');
        sb.append('\n');

        sb.append("[Targets]\n");
        for (TargetProfile profile : targetProfiles) {
            sb.append("  ").append(profile.label).append(": ")
                    .append(profileStatusLabel(profile)).append('\n');
            sb.append("    id=").append(profile.id).append('\n');
            sb.append("    mode=").append(profile.mode).append('\n');
            sb.append("    backend=").append(profile.backend).append('\n');
            sb.append("    risk=").append(profile.riskClass).append('\n');
            sb.append("    enabled=").append(profile.enabled).append('\n');
        }
        sb.append('\n');

        appendCapabilities(sb, "Device Tools", nubiaDeviceAdapter.discover(this));
        sb.append("[ADB Wi-Fi]\n");
        sb.append("  status=").append(adbWifiStatus()).append('\n');
        sb.append("  ").append(adbWifiDetail().replace("\n", "\n  ")).append('\n');
        sb.append("  mutating=opt-in\n\n");

        appendCapabilities(sb, "Performance", redMagicPerformanceAdapter.discover(this, redMagicProbe));
        appendCapabilities(sb, "RedMagic Button", redMagicButtonAdapter.discover(this));

        for (Lane lane : lanes) {
            LaneStatus laneStatus = evaluate(lane);
            sb.append("[").append(lane.name).append("] ").append(laneStatus.label).append('\n');
            if (lane.targets.isEmpty()) {
                sb.append("  ").append(lane.note).append('\n');
            }
            for (Target target : lane.targets) {
                PackageState state = inspect(target);
                sb.append("  ").append(target.label).append(": ").append(state.label).append('\n');
                sb.append("    package=").append(target.packageName).append('\n');
                if (state.installed) {
                    sb.append("    version=").append(state.version).append('\n');
                    sb.append("    signer=").append(state.signer).append('\n');
                }
            }
            sb.append('\n');
        }
        return sb.toString();
    }

    private void appendCapabilities(StringBuilder sb, String title, List<NebulaCapability> capabilities) {
        sb.append("[").append(title).append("]\n");
        for (NebulaCapability capability : capabilities) {
            sb.append("  ").append(capability.id).append(": ").append(capability.status).append('\n');
            sb.append("    source=").append(capability.source).append('\n');
            sb.append("    mutating=").append(capability.mutating).append('\n');
        }
        sb.append('\n');
    }

    private void copyReport() {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("Nebula doctor report", buildReport()));
        toast("Report copied");
    }

    private void shareReport() {
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_SUBJECT, "DroidSpaces Nebula doctor report");
        send.putExtra(Intent.EXTRA_TEXT, buildReport());
        startActivity(Intent.createChooser(send, "Share report"));
    }

    private void launchPackage(String packageName) {
        Intent launch = getPackageManager().getLaunchIntentForPackage(packageName);
        if (launch == null) {
            openAppInfo(packageName);
            return;
        }
        try {
            startActivity(launch);
        } catch (ActivityNotFoundException error) {
            openAppInfo(packageName);
        }
    }

    private void openAppInfo(String packageName) {
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        intent.setData(Uri.parse("package:" + packageName));
        try {
            startActivity(intent);
        } catch (ActivityNotFoundException error) {
            toast("App info unavailable");
        }
    }

    private TextView text(String value, int sp, int color, int style) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        view.setTypeface(Typeface.DEFAULT, style);
        view.setLineSpacing(dp(2), 1.0f);
        return view;
    }

    private TextView chip(String value, int color) {
        TextView view = text(value, 12, BG, Typeface.BOLD);
        view.setGravity(Gravity.CENTER);
        view.setPadding(dp(10), dp(5), dp(10), dp(5));
        view.setMinWidth(dp(72));
        view.setBackground(round(color, dp(20), color));
        return view;
    }

    private LinearLayout baseCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(14), dp(14), dp(14));
        card.setBackground(round(PANEL, dp(8), LINE));

        LinearLayout.LayoutParams cardParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        cardParams.bottomMargin = dp(12);
        card.setLayoutParams(cardParams);
        return card;
    }

    private Button actionButton(String label, int color) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(BG);
        button.setTextSize(13);
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setAllCaps(false);
        button.setMinHeight(dp(42));
        button.setPadding(dp(6), 0, dp(6), 0);
        button.setBackground(round(color, dp(8), color));
        return button;
    }

    private Button smallButton(String label, int color) {
        Button button = actionButton(label, color);
        button.setTextColor(color == PANEL_ALT ? TEXT : BG);
        button.setMinHeight(dp(36));
        return button;
    }

    private LinearLayout.LayoutParams weightedButtonParams() {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        params.setMargins(dp(3), 0, dp(3), 0);
        return params;
    }

    private GradientDrawable round(int fill, int radius, int stroke) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setShape(GradientDrawable.RECTANGLE);
        drawable.setColor(fill);
        drawable.setCornerRadius(radius);
        drawable.setStroke(dp(1), stroke);
        return drawable;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private String shortHash(String hash) {
        if (hash == null || hash.length() < 12) return "unknown";
        return hash.substring(0, 12) + "...";
    }

    private String joinInline(List<String> values) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < values.size(); i++) {
            if (i > 0) sb.append(", ");
            sb.append(values.get(i));
        }
        return sb.toString();
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    private static final class TargetProfile {
        final String id;
        final String label;
        final String mode;
        final String backend;
        final String riskClass;
        final boolean enabled;
        final String summary;
        final List<String> preflight;
        final List<String> forbiddenActions;

        TargetProfile(String id, String label, String mode, String backend,
                String riskClass, boolean enabled, String summary,
                List<String> preflight, List<String> forbiddenActions) {
            this.id = id;
            this.label = label;
            this.mode = mode;
            this.backend = backend;
            this.riskClass = riskClass;
            this.enabled = enabled;
            this.summary = summary;
            this.preflight = preflight;
            this.forbiddenActions = forbiddenActions;
        }
    }

    private static final class Lane {
        final String name;
        final String mode;
        final String description;
        final String note;
        final List<Target> targets;

        Lane(String name, String mode, String description, String note, List<Target> targets) {
            this.name = name;
            this.mode = mode;
            this.description = description;
            this.note = note;
            this.targets = targets;
        }
    }

    private static final class Target {
        final String label;
        final String packageName;
        final String expectedVersion;
        final String expectedSigner;
        final boolean required;

        Target(String label, String packageName, String expectedVersion,
                String expectedSigner, boolean required) {
            this.label = label;
            this.packageName = packageName;
            this.expectedVersion = expectedVersion;
            this.expectedSigner = expectedSigner;
            this.required = required;
        }
    }

    private static final class PackageState {
        final boolean installed;
        final boolean mismatch;
        final String label;
        final int color;
        final String detail;
        final String version;
        final String signer;

        PackageState(boolean installed, boolean mismatch, String label, int color,
                String detail, String version, String signer) {
            this.installed = installed;
            this.mismatch = mismatch;
            this.label = label;
            this.color = color;
            this.detail = detail;
            this.version = version;
            this.signer = signer;
        }
    }

    private static final class LaneStatus {
        final String label;
        final int color;

        LaneStatus(String label, int color) {
            this.label = label;
            this.color = color;
        }
    }
}
