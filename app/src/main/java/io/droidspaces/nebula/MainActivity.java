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
import android.graphics.Shader;
import android.graphics.drawable.BitmapDrawable;
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

import org.json.JSONArray;
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
    private static final int BG = 0xFF04070A;
    private static final int PANEL = 0xE8070B0F;
    private static final int PANEL_ALT = 0xDF0B1218;
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
    private static final int CLEAR = 0x00000000;

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
                    "WayLandIE bridge profile. Display proof is solved with real-buffer commits; game-client runtime remains unpromoted under the 39-bit VA constraint.",
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
                    Arrays.asList("crashdump triage", "old helper quarantine", "live safe DRM discovery", "explicit approval"),
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
                    "Current state: phone active module proves WayLandIE/Gamescope/Xwayland display, zero vkGetMemoryFdKHR failures, and two real-buffer commits; game-client runtime remains the next bounded proof.",
                    Arrays.asList(
                            new Target("WayLandIE Display", "io.droidspaces.nebula.waylandie",
                                    "0.2.0-no-root-nebula13-rootfs-vulkan-smoke",
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
    private LinearLayout displayLaneContainer;
    private LinearLayout targetProfileContainer;
    private LinearLayout coreContainer;
    private LinearLayout autoCoolingContainer;
    private LinearLayout systemTargetContainer;
    private LinearLayout deckModeContainer;
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
    private JSONObject baselineIntegrationsStatus;
    private JSONObject standaloneIntegrationsStatus;
    private JSONObject nubiaToolkitStatus;
    private JSONObject waylandieRuntimeStatus;
    private JSONObject displayLanesStatus;
    private JSONObject displayMethodContainersStatus;
    private JSONObject displayMethodProfilesStatus;
    private JSONObject displayAnlandRecipesStatus;

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
        applyScrollBackplane(root);
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

        deckModeContainer = new LinearLayout(this);
        deckModeContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(deckModeContainer);

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

        root.addView(sectionTitle("Display Lanes"));

        displayLaneContainer = new LinearLayout(this);
        displayLaneContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(displayLaneContainer);

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
        reportView.setBackground(round(PANEL_ALT, dp(6), LINE));
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
        baselineIntegrationsStatus = loadBaselineIntegrationsStatus();
        standaloneIntegrationsStatus = loadStandaloneIntegrationsStatus();
        nubiaToolkitStatus = loadNubiaToolkitStatus();
        waylandieRuntimeStatus = loadWaylandieRuntimeStatus();
        displayLanesStatus = loadDisplayLanesStatus();
        displayMethodContainersStatus = loadDisplayMethodContainersStatus();
        displayMethodProfilesStatus = loadDisplayMethodProfilesStatus();
        displayAnlandRecipesStatus = loadDisplayAnlandRecipesStatus();

        systemTargetContainer.removeAllViews();
        systemTargetContainer.addView(buildSystemTargetBar());

        deckModeContainer.removeAllViews();
        deckModeContainer.addView(buildDeckModeStrip());

        statusRailContainer.removeAllViews();
        statusRailContainer.addView(buildStatusRail());

        coreContainer.removeAllViews();
        coreContainer.addView(buildCoreCard(coreStatus));
        coreContainer.addView(buildStandaloneIntegrationsCard());
        coreContainer.addView(buildBaselineIntegrationsCard());

        autoCoolingContainer.removeAllViews();
        autoCoolingContainer.addView(buildAutoCoolingCard(redMagicProbe));

        displayLaneContainer.removeAllViews();
        displayLaneContainer.addView(buildDisplayLanesCard());
        displayLaneContainer.addView(buildAnlandRecipesCard());

        targetProfileContainer.removeAllViews();
        for (TargetProfile profile : targetProfiles) {
            targetProfileContainer.addView(buildTargetProfileCard(profile));
        }

        deviceToolsContainer.removeAllViews();
        deviceToolsContainer.addView(buildCapabilityCard(
                "Audited Nubia capability status", nubiaDeviceAdapter.discover(this)));
        deviceToolsContainer.addView(buildNubiaToolkitCard());
        deviceToolsContainer.addView(buildAdbWifiCard());

        performanceContainer.removeAllViews();
        performanceContainer.addView(buildCapabilityCard(
                "Audited RedMagic capability status",
                redMagicPerformanceAdapter.discover(this, redMagicProbe)));

        redMagicButtonContainer.removeAllViews();
        redMagicButtonContainer.addView(buildCapabilityCard(
                "Mapping disabled in pass 01", redMagicButtonAdapter.discover(this)));

        laneContainer.removeAllViews();
        laneContainer.addView(buildWaylandieRuntimeCard());
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
        art.setImageResource(R.drawable.nebula_hero_emblem_wide);
        art.setScaleType(ImageView.ScaleType.CENTER_CROP);
        art.setAlpha(0.98f);
        hero.addView(art, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(heroHeightDp()));
        params.bottomMargin = dp(12);
        hero.setLayoutParams(params);
        return hero;
    }

    private int heroHeightDp() {
        return getResources().getDisplayMetrics().widthPixels
                > getResources().getDisplayMetrics().heightPixels ? 112 : 300;
    }

    private View buildDeckModeStrip() {
        LinearLayout strip = new LinearLayout(this);
        strip.setOrientation(LinearLayout.HORIZONTAL);
        strip.setPadding(0, 0, 0, dp(12));

        strip.addView(deckTile("GAMING MODE", coreStatus.safeMode ? "safe mode" : "armed",
                coreStatus.safeMode ? BLUE : NEON), weightedButtonParams());
        strip.addView(deckTile("DISPLAY ENGINE", displayDeckLabel(), CYAN), weightedButtonParams());
        strip.addView(deckTile("PERFORMANCE", coolingPolicyLabel(redMagicProbe),
                coolingPolicyColor(redMagicProbe)), weightedButtonParams());
        return strip;
    }

    private View deckTile(String title, String detail, int color) {
        LinearLayout tile = new LinearLayout(this);
        tile.setOrientation(LinearLayout.VERTICAL);
        tile.setPadding(dp(10), dp(11), dp(10), dp(11));
        tile.setMinimumHeight(dp(72));
        tile.setBackground(round(0xE2080D10, dp(4), color));

        TextView titleView = text(title, 10, color, Typeface.BOLD);
        titleView.setLetterSpacing(0.06f);
        titleView.setSingleLine(false);
        tile.addView(titleView);

        TextView detailView = text(detail, 11, MUTED, Typeface.NORMAL);
        detailView.setPadding(0, dp(7), 0, 0);
        detailView.setSingleLine(false);
        tile.addView(detailView);
        return tile;
    }

    private String displayDeckLabel() {
        if (displayLanesStatus == null) return "read only";
        JSONArray lanes = displayLanesStatus.optJSONArray("lanes");
        if (lanes == null) return "read only";
        for (int i = 0; i < lanes.length(); i++) {
            JSONObject lane = lanes.optJSONObject(i);
            if (lane == null) continue;
            if ("phone_app_bridge".equals(lane.optString("id"))) {
                String lead = lane.optString("lead_status", "");
                if (lead.contains("proven")) return "legacy proof";
                if ("promotion_candidate".equals(lead)) return "legacy lead";
                return displayStatusLabel(lane.optString("status", "read_only"));
            }
        }
        return "read only";
    }

    private View buildSystemTargetBar() {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(12), dp(12), dp(12), dp(12));
        bar.setBackground(round(0xE80A0E13, dp(4), 0xFF29313B));

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
        rail.setOrientation(LinearLayout.VERTICAL);
        rail.setPadding(0, 0, 0, dp(12));

        LinearLayout rowOne = new LinearLayout(this);
        rowOne.setOrientation(LinearLayout.HORIZONTAL);
        rail.addView(rowOne);
        rowOne.addView(statusCell("DROIDSPACES", "runtime active", NEON), weightedButtonParams());
        rowOne.addView(statusCell("WAYLANDIE", "display proof", CYAN), weightedButtonParams());
        rowOne.addView(statusCell("ADRENO 840", "Turnip 26.2", TEXT), weightedButtonParams());

        LinearLayout rowTwo = new LinearLayout(this);
        rowTwo.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams rowTwoParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        rowTwoParams.topMargin = dp(6);
        rail.addView(rowTwo, rowTwoParams);
        rowTwo.addView(statusCell("NTSYNC", "kernel enabled", TEXT), weightedButtonParams());
        rowTwo.addView(statusCell("SELINUX", "enforcing", TEXT), weightedButtonParams());
        rowTwo.addView(statusCell("POWERDECK", coolingPolicyLabel(redMagicProbe),
                coolingPolicyColor(redMagicProbe)), weightedButtonParams());
        return rail;
    }

    private View statusCell(String title, String detail, int color) {
        LinearLayout cell = new LinearLayout(this);
        cell.setOrientation(LinearLayout.VERTICAL);
        cell.setPadding(dp(5), dp(8), dp(5), dp(8));
        cell.setBackground(round(0xDB0C1115, dp(2), 0xFF25313A));

        TextView label = text(title, 9, color, Typeface.BOLD);
        label.setSingleLine(false);
        cell.addView(label);

        TextView value = text(detail, 9, MUTED, Typeface.NORMAL);
        value.setSingleLine(false);
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

    private JSONObject loadBaselineIntegrationsStatus() {
        if (!coreStatus.installed || coreStatus.hasVisibleError()) {
            return null;
        }
        CommandResult result = coreClient.baselineIntegrations();
        if (!result.ok()) {
            return null;
        }
        try {
            return new JSONObject(result.stdout);
        } catch (JSONException error) {
            return null;
        }
    }

    private JSONObject loadStandaloneIntegrationsStatus() {
        if (!coreStatus.installed || coreStatus.hasVisibleError()) {
            return null;
        }
        CommandResult result = coreClient.standaloneIntegrations();
        if (!result.ok()) {
            return null;
        }
        try {
            return new JSONObject(result.stdout);
        } catch (JSONException error) {
            return null;
        }
    }

    private View buildStandaloneIntegrationsCard() {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        titleBox.addView(text("Standalone Control Deck", 19, TEXT, Typeface.BOLD));
        TextView detail = text(standaloneSummary(), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(4), 0, 0);
        titleBox.addView(detail);

        top.addView(chip(standaloneStatusLabel(), standaloneStatusColor()));

        JSONArray layers = standaloneIntegrationsStatus == null
                ? null : standaloneIntegrationsStatus.optJSONArray("ownership_layers");
        if (layers == null || layers.length() == 0) {
            TextView unavailable = text("standalone=module_unavailable", 12, MUTED, Typeface.NORMAL);
            unavailable.setTypeface(Typeface.MONOSPACE);
            unavailable.setPadding(0, dp(12), 0, 0);
            card.addView(unavailable);
            return card;
        }

        for (int i = 0; i < layers.length(); i++) {
            JSONObject layer = layers.optJSONObject(i);
            if (layer != null) {
                card.addView(buildStandaloneLayerRow(layer));
            }
        }
        return card;
    }

    private View buildStandaloneLayerRow(JSONObject layer) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(0, dp(10), 0, dp(4));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(top);

        TextView label = text(layer.optString("owner", layer.optString("id", "Layer")),
                15, TEXT, Typeface.BOLD);
        top.addView(label, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        top.addView(chip(layer.optBoolean("mutation_authority", false) ? "Authority" : "Observe",
                layer.optBoolean("mutation_authority", false) ? YELLOW : CYAN));

        TextView detail = text(standaloneLayerDetail(layer), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(6), 0, 0);
        row.addView(detail);
        return row;
    }

    private String standaloneSummary() {
        if (standaloneIntegrationsStatus == null) {
            return "standalone=module_unavailable\nfixedCommands=unknown";
        }
        JSONObject contract = standaloneIntegrationsStatus.optJSONObject("contract");
        return "standalone=" + standaloneIntegrationsStatus.optString("standalone_id", "unknown")
                + "\nmode=" + standaloneIntegrationsStatus.optString("mode", "unknown")
                + "\napk=" + standaloneIntegrationsStatus.optString("apk_package", "unknown")
                + "\nmodule=" + standaloneIntegrationsStatus.optString("module_id", "unknown")
                + "\nfixedCommands=" + jsonBoolLabel(contract, "fixed_commands_only")
                + "\nactiveFirst=" + jsonBoolLabel(contract, "active_module_first");
    }

    private String standaloneLayerDetail(JSONObject layer) {
        return "id=" + layer.optString("id", "unknown")
                + "\nbundledIn=" + layer.optString("bundled_in", "unknown")
                + "\nresponsibility=" + layer.optString("responsibility", "unknown")
                + "\nmutationAuthority=" + layer.optBoolean("mutation_authority", false)
                + "\npromotion=" + layer.optString("promotion_state",
                layer.optString("mutation_policy", "status_only"));
    }

    private String standaloneStatusLabel() {
        if (standaloneIntegrationsStatus == null) return "Unknown";
        JSONObject contract = standaloneIntegrationsStatus.optJSONObject("contract");
        if (contract != null
                && contract.optBoolean("single_apk", false)
                && contract.optBoolean("single_core_module", false)
                && contract.optBoolean("fixed_commands_only", false)
                && contract.optBoolean("active_module_first", false)) {
            return "Unified";
        }
        return "Check";
    }

    private int standaloneStatusColor() {
        if (standaloneIntegrationsStatus == null) return BLUE;
        return "Unified".equals(standaloneStatusLabel()) ? GREEN : YELLOW;
    }

    private View buildBaselineIntegrationsCard() {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        titleBox.addView(text("Baseline APK / Module", 19, TEXT, Typeface.BOLD));
        TextView detail = text(baselineSummary(), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(4), 0, 0);
        titleBox.addView(detail);

        top.addView(chip(baselineStatusLabel(), baselineStatusColor()));

        JSONArray integrations = baselineIntegrationsStatus == null
                ? null : baselineIntegrationsStatus.optJSONArray("integrations");
        if (integrations == null || integrations.length() == 0) {
            TextView unavailable = text("moduleStatus=unavailable", 12, MUTED, Typeface.NORMAL);
            unavailable.setTypeface(Typeface.MONOSPACE);
            unavailable.setPadding(0, dp(12), 0, 0);
            card.addView(unavailable);
            return card;
        }

        for (int i = 0; i < integrations.length(); i++) {
            JSONObject integration = integrations.optJSONObject(i);
            if (integration != null) {
                card.addView(buildBaselineIntegrationRow(integration));
            }
        }
        return card;
    }

    private View buildBaselineIntegrationRow(JSONObject integration) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(0, dp(10), 0, dp(4));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(top);

        TextView label = text(integration.optString("title", integration.optString("id", "Integration")),
                15, TEXT, Typeface.BOLD);
        top.addView(label, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        String status = integration.optString("status", "unknown");
        top.addView(chip(baselineIntegrationLabel(status), baselineIntegrationColor(integration)));

        TextView detail = text(baselineIntegrationDetail(integration),
                12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(6), 0, 0);
        row.addView(detail);
        return row;
    }

    private String baselineSummary() {
        if (baselineIntegrationsStatus == null) {
            return "baseline=module_unavailable\nmutatingControls=false";
        }
        return "baseline=" + baselineIntegrationsStatus.optString("baseline_id", "unknown")
                + "\noverall=" + baselineIntegrationsStatus.optString("overall_status", "unknown")
                + "\nsafeDefault=" + baselineIntegrationsStatus.optBoolean("safe_default", true)
                + "\nmutatingControls="
                + baselineIntegrationsStatus.optBoolean("mutating_controls_enabled", false);
    }

    private String baselineStatusLabel() {
        if (baselineIntegrationsStatus == null) return "Unknown";
        String status = baselineIntegrationsStatus.optString("overall_status", "");
        if ("baseline_export_blocked_read_only".equals(status)) return "Export";
        if (status.endsWith("_ready_read_only")) return "Ready";
        if ("baseline_bootstrap".equals(status)) return "Bootstrap";
        if ("baseline_partial".equals(status)) return "Partial";
        return "Baseline";
    }

    private int baselineStatusColor() {
        if (baselineIntegrationsStatus == null) return BLUE;
        String status = baselineIntegrationsStatus.optString("overall_status", "");
        if ("baseline_export_blocked_read_only".equals(status)) return YELLOW;
        if (status.endsWith("_ready_read_only")) return GREEN;
        if ("baseline_bootstrap".equals(status)) return YELLOW;
        if ("baseline_partial".equals(status)) return CYAN;
        return BLUE;
    }

    private String baselineIntegrationLabel(String status) {
        if (status == null || status.isEmpty()) return "Unknown";
        if ("blocked_export".equals(status)) return "Export";
        if ("blocked_real_buffer".equals(status)) return "Real buffer";
        if ("display_ready".equals(status)) return "Display";
        if ("container_runtime_ready".equals(status)) return "Runtime";
        if ("runtime_preflight_ready".equals(status)) return "Runtime";
        if ("hook_framework_ready_scope_deferred".equals(status)) return "Vector";
        if ("read_only_nodes_visible".equals(status)) return "Nodes";
        if ("nebula_preview_ready".equals(status)) return "Preview";
        if ("external_module_detected_dry_run_required".equals(status)) return "Module";
        if ("partial".equals(status)) return "Partial";
        if ("missing".equals(status) || "nodes_missing".equals(status)) return "Missing";
        return status.length() > 14 ? status.substring(0, 14) : status;
    }

    private int baselineIntegrationColor(JSONObject integration) {
        if (integration.optBoolean("ready", false)) return GREEN;
        String status = integration.optString("status", "");
        if (status.contains("blocked")) return YELLOW;
        if (status.contains("preview") || status.contains("reference")) return CYAN;
        if (status.contains("partial") || status.contains("deferred")) return YELLOW;
        if (status.contains("missing")) return RED;
        return BLUE;
    }

    private String baselineIntegrationDetail(JSONObject integration) {
        StringBuilder builder = new StringBuilder();
        builder.append("id=").append(integration.optString("id", "unknown"));
        builder.append("\nrole=").append(integration.optString("role", "unknown"));
        builder.append("\nowner=").append(integration.optString("owner", "unknown"));
        if (integration.has("method_id")) {
            builder.append("\nmethod=").append(integration.optString("method_id", "unknown"));
        }
        if (integration.has("container_ref")) {
            builder.append("  container=").append(integration.optString("container_ref", "unknown"));
        }
        if (integration.has("container_kind")) {
            builder.append("  kind=").append(integration.optString("container_kind", "unknown"));
        }
        if (integration.has("container_status")) {
            builder.append("\ncontainerStatus=").append(integration.optString("container_status", "unknown"));
        }
        if (integration.has("display_status")) {
            builder.append("  displayStatus=").append(integration.optString("display_status", "unknown"));
        }
        if (integration.has("runtime_status")) {
            builder.append("\nruntimeStatus=").append(integration.optString("runtime_status", "unknown"));
        }
        if (integration.has("requirement_status")) {
            builder.append("  requirements=").append(integration.optString("requirement_status", "unknown"));
        }
        if (integration.has("active_blocker")) {
            builder.append("\nblocker=").append(integration.optString("active_blocker", "unknown"));
        }
        if (integration.has("path_policy")) {
            builder.append("\npathPolicy=").append(integration.optString("path_policy", "unknown"));
        }
        if (integration.has("package_path")) {
            builder.append("\npackagePath=").append(integration.optString("package_path", "unknown"));
        }
        if (integration.has("native_lib_dir")) {
            builder.append("\nnativeLibDir=").append(integration.optString("native_lib_dir", "unknown"));
        }
        if (integration.has("glibc_loader")) {
            builder.append("\nglibcLoader=").append(integration.optString("glibc_loader", "unknown"));
        }
        if (integration.has("software_glx_reproduced")) {
            builder.append("\nsoftwareGlx=")
                    .append(integration.optBoolean("software_glx_reproduced", false));
        }
        if (integration.has("hardware_glx_pass")) {
            builder.append("  hardwareGlx=")
                    .append(integration.optBoolean("hardware_glx_pass", false));
        }
        if (integration.has("real_buffer_pass")) {
            builder.append("  realBuffer=")
                    .append(integration.optBoolean("real_buffer_pass", false));
        }
        if (integration.has("gl_renderer")) {
            builder.append("\nglRenderer=").append(integration.optString("gl_renderer"));
        }
        if (integration.has("vk_get_memory_fd_failures")) {
            builder.append("\nvkGetMemoryFdFailures=")
                    .append(integration.optInt("vk_get_memory_fd_failures", -1));
        }
        if (integration.has("real_buffer_commits") || integration.has("no_buffer_commits")) {
            builder.append("  realCommits=")
                    .append(integration.optInt("real_buffer_commits", -1));
            builder.append("  noBufferCommits=")
                    .append(integration.optInt("no_buffer_commits", -1));
        }
        if (integration.has("a1_fasttest_env_status")) {
            builder.append("\na1=").append(integration.optString("a1_fasttest_env_status"));
        }
        if (integration.has("hook_ready")) {
            builder.append("\nhookReady=").append(integration.optBoolean("hook_ready", false));
        }
        if (integration.has("rezygisk_provider_state")) {
            builder.append("  rezygiskProvider=")
                    .append(integration.optString("rezygisk_provider_state"));
        }
        JSONArray missingRequirements = integration.optJSONArray("missing_requirements");
        if (missingRequirements != null && missingRequirements.length() > 0) {
            builder.append("\nmissingRequirements=").append(missingRequirements);
        }
        builder.append("\ninstalled=").append(integration.optBoolean("installed", false));
        builder.append("  ready=").append(integration.optBoolean("ready", false));
        builder.append("  mutating=").append(integration.optBoolean("mutating", false));
        if (integration.has("writes_enabled")) {
            builder.append("\nwritesEnabled=").append(integration.optBoolean("writes_enabled", false));
        }
        if (integration.has("dry_run_required")) {
            builder.append("  dryRunRequired=").append(integration.optBoolean("dry_run_required", true));
        }
        JSONObject provider = integration.optJSONObject("zygisk_provider");
        if (provider != null) {
            builder.append("\nzygiskProvider=").append(providerStatus(provider));
        }
        if (integration.has("selected_container")) {
            builder.append("\nselectedContainer=").append(integration.optString("selected_container", "unknown"));
        }
        if (integration.has("container_selection_source")) {
            builder.append("  source=").append(integration.optString("container_selection_source", "unknown"));
        }
        if (integration.has("container_active")) {
            builder.append("\ncontainerActive=").append(integration.optBoolean("container_active", false));
            if (integration.has("container_pid") && !integration.isNull("container_pid")) {
                builder.append("  pid=").append(integration.optInt("container_pid"));
            }
        }
        JSONObject checks = integration.optJSONObject("checks");
        if (checks != null) {
            builder.append("\nchecks=").append(checkSummary(checks));
        }
        JSONArray errors = integration.optJSONArray("errors");
        if (errors != null && errors.length() > 0) {
            builder.append("\nerrors=").append(errors);
        }
        builder.append("\nsource=").append(integration.optString("source", "unknown"));
        return builder.toString();
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
        tile.setBackground(round(0xDB0B1014, dp(2), 0xFF25313A));

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
        track.setBackground(round(0xD9121A20, dp(1), 0xFF121A20));
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

    private View buildNubiaToolkitCard() {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        titleBox.addView(text("Nubia Toolkit compatibility", 19, TEXT, Typeface.BOLD));
        TextView detail = text(nubiaToolkitDetail(), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(4), 0, 0);
        titleBox.addView(detail);

        top.addView(chip(nubiaToolkitStatusLabel(), nubiaToolkitStatusColor()));
        return card;
    }

    private String nubiaToolkitStatusLabel() {
        JSONObject object = nubiaToolkitStatusObject();
        if (object == null) return "Unknown";
        JSONObject framework = object.optJSONObject("hook_framework");
        if (framework != null && framework.optBoolean("enabled", false)) return "Vector on";
        if (framework != null && framework.optBoolean("installed", false)) return "Vector off";
        JSONObject provider = object.optJSONObject("zygisk_provider");
        if (provider != null && provider.optBoolean("enabled", false)) return "ReZygisk";
        if (provider != null && provider.optBoolean("installed", false)) return "Provider off";
        return "Ported";
    }

    private int nubiaToolkitStatusColor() {
        JSONObject object = nubiaToolkitStatusObject();
        if (object == null) return BLUE;
        JSONObject framework = object.optJSONObject("hook_framework");
        if (framework != null && framework.optBoolean("enabled", false)) return GREEN;
        if (framework != null && framework.optBoolean("installed", false)) return YELLOW;
        JSONObject provider = object.optJSONObject("zygisk_provider");
        if (provider != null && provider.optBoolean("enabled", false)) return CYAN;
        if (provider != null && provider.optBoolean("installed", false)) return YELLOW;
        return CYAN;
    }

    private String nubiaToolkitDetail() {
        JSONObject object = nubiaToolkitStatusObject();
        if (object == null) {
            return "moduleStatus=unavailable\nintegration=ported_status_only";
        }
        JSONObject framework = object.optJSONObject("hook_framework");
        JSONObject provider = object.optJSONObject("zygisk_provider");
        JSONObject packages = object.optJSONObject("packages");
        JSONObject gameAssist = packages == null ? null : packages.optJSONObject("game_assist");
        JSONObject gameLauncher = packages == null ? null : packages.optJSONObject("game_launcher");
        JSONObject toolkit = packages == null ? null : packages.optJSONObject("toolkit_reference");
        return "integration=" + object.optString("integration", "unknown")
                + "\noldToolkitRequired=" + object.optBoolean("old_toolkit_required", false)
                + "\nlsposedRequiredForHooks=" + object.optBoolean("lsposed_required_for_hooks", true)
                + "\nhooksActive=" + object.optBoolean("lsposed_hooks_active", false)
                + "\nframework=" + frameworkStatus(framework)
                + "\nzygiskProvider=" + providerStatus(provider)
                + "\ngameAssist=" + packageVisibleLabel(gameAssist)
                + "\ngameLauncher=" + packageVisibleLabel(gameLauncher)
                + "\noldToolkitApk=" + packageVisibleLabel(toolkit);
    }

    private String frameworkStatus(JSONObject framework) {
        if (framework == null) return "unknown";
        String enabled = framework.optBoolean("enabled", false) ? "enabled" : "disabled";
        String installed = framework.optBoolean("installed", false) ? "installed" : "missing";
        return framework.optString("name", "framework") + " " + installed + "/" + enabled
                + " " + framework.optString("version", "unknown");
    }

    private String providerStatus(JSONObject provider) {
        if (provider == null) return "unknown";
        String enabled = provider.optBoolean("enabled", false) ? "enabled" : "disabled";
        String installed = provider.optBoolean("installed", false) ? "installed" : "missing";
        String note = provider.optBoolean("requires_magisk_builtin_zygisk_disabled", false)
                ? " magiskBuiltinZygisk=disabled-required"
                : "";
        return provider.optString("name", provider.optString("id", "provider")) + " "
                + installed + "/" + enabled + " " + provider.optString("version", "unknown") + note;
    }

    private String packageVisibleLabel(JSONObject object) {
        if (object == null) return "unknown";
        return object.optBoolean("visible", false) ? "visible" : "missing";
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

    private JSONObject nubiaToolkitStatusObject() {
        return nubiaToolkitStatus;
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

    private JSONObject loadNubiaToolkitStatus() {
        if (!coreStatus.installed || coreStatus.hasVisibleError()) {
            return null;
        }
        CommandResult result = coreClient.nubiaToolkitStatus();
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
        if (object == null) {
            return "unknown";
        }
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

    private View buildWaylandieRuntimeCard() {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        titleBox.addView(text("WayLandIE Proton runtime", 19, TEXT, Typeface.BOLD));
        TextView detail = text(waylandieRuntimeDetail(), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(4), 0, 0);
        titleBox.addView(detail);

        top.addView(chip(waylandieRuntimeLabel(), waylandieRuntimeColor()));

        Button smoke = smallButton("Smoke", waylandieRuntimeReady() ? NEON : PANEL_ALT);
        smoke.setEnabled(waylandieRuntimeReady() && !waylandieRuntimeSafeMode());
        smoke.setAlpha(smoke.isEnabled() ? 1f : 0.45f);
        smoke.setOnClickListener(v -> runWaylandieSmoke());
        LinearLayout.LayoutParams buttonParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        buttonParams.topMargin = dp(12);
        card.addView(smoke, buttonParams);
        return card;
    }

    private JSONObject waylandieRuntimeStatusObject() {
        return waylandieRuntimeStatus;
    }

    private JSONObject loadWaylandieRuntimeStatus() {
        if (!coreStatus.installed || coreStatus.hasVisibleError()) {
            return null;
        }
        CommandResult result = coreClient.waylandieRuntimeStatus();
        if (!result.ok()) {
            return null;
        }
        try {
            return new JSONObject(result.stdout);
        } catch (JSONException error) {
            return null;
        }
    }

    private JSONObject loadDisplayLanesStatus() {
        if (!coreStatus.installed || coreStatus.hasVisibleError()) {
            return null;
        }
        CommandResult result = coreClient.displayLanes();
        if (!result.ok()) {
            return null;
        }
        try {
            return new JSONObject(result.stdout);
        } catch (JSONException error) {
            return null;
        }
    }

    private JSONObject loadDisplayMethodContainersStatus() {
        if (!coreStatus.installed || coreStatus.hasVisibleError()) {
            return null;
        }
        CommandResult result = coreClient.displayMethodContainers();
        if (!result.ok()) {
            return null;
        }
        try {
            return new JSONObject(result.stdout);
        } catch (JSONException error) {
            return null;
        }
    }

    private JSONObject loadDisplayMethodProfilesStatus() {
        if (!coreStatus.installed || coreStatus.hasVisibleError()) {
            return null;
        }
        CommandResult result = coreClient.displayMethodProfiles();
        if (!result.ok()) {
            return null;
        }
        try {
            return new JSONObject(result.stdout);
        } catch (JSONException error) {
            return null;
        }
    }

    private JSONObject loadDisplayAnlandRecipesStatus() {
        if (!coreStatus.installed || coreStatus.hasVisibleError()) {
            return null;
        }
        CommandResult result = coreClient.displayAnlandRecipes();
        if (!result.ok()) {
            return null;
        }
        try {
            return new JSONObject(result.stdout);
        } catch (JSONException error) {
            return null;
        }
    }

    private View buildDisplayLanesCard() {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        titleBox.addView(text("Nebula Display Lanes", 19, TEXT, Typeface.BOLD));
        TextView detail = text(displayLaneSummary(), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(4), 0, 0);
        titleBox.addView(detail);

        top.addView(chip(displayLaneTopLabel(), displayLaneTopColor()));

        JSONArray lanes = displayLanesStatus == null ? null : displayLanesStatus.optJSONArray("lanes");
        if (lanes == null || lanes.length() == 0) {
            TextView unavailable = text("moduleStatus=unavailable", 12, MUTED, Typeface.NORMAL);
            unavailable.setTypeface(Typeface.MONOSPACE);
            unavailable.setPadding(0, dp(12), 0, 0);
            card.addView(unavailable);
            return card;
        }

        for (int i = 0; i < lanes.length(); i++) {
            JSONObject lane = lanes.optJSONObject(i);
            if (lane != null) {
                card.addView(buildDisplayLaneRow(lane));
            }
        }
        TextView methodContainers = text(displayMethodContainersSummary(), 12, MUTED, Typeface.NORMAL);
        methodContainers.setTypeface(Typeface.MONOSPACE);
        methodContainers.setPadding(0, dp(10), 0, 0);
        card.addView(methodContainers);
        TextView methodProfiles = text(displayMethodProfilesSummary(), 12, MUTED, Typeface.NORMAL);
        methodProfiles.setTypeface(Typeface.MONOSPACE);
        methodProfiles.setPadding(0, dp(10), 0, 0);
        card.addView(methodProfiles);
        return card;
    }

    private View buildAnlandRecipesCard() {
        LinearLayout card = baseCard();

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(top);

        LinearLayout titleBox = new LinearLayout(this);
        titleBox.setOrientation(LinearLayout.VERTICAL);
        top.addView(titleBox, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        titleBox.addView(text("Anland Desktop Recipes", 19, TEXT, Typeface.BOLD));
        TextView detail = text(anlandRecipeSummary(), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(4), 0, 0);
        titleBox.addView(detail);

        top.addView(chip(anlandRecipeTopLabel(), anlandRecipeTopColor()));

        JSONArray recipes = displayAnlandRecipesStatus == null
                ? null : displayAnlandRecipesStatus.optJSONArray("recipes");
        if (recipes == null || recipes.length() == 0) {
            TextView unavailable = text("recipes=module_unavailable", 12, MUTED, Typeface.NORMAL);
            unavailable.setTypeface(Typeface.MONOSPACE);
            unavailable.setPadding(0, dp(12), 0, 0);
            card.addView(unavailable);
            return card;
        }

        for (int i = 0; i < recipes.length(); i++) {
            JSONObject recipe = recipes.optJSONObject(i);
            if (recipe != null) {
                card.addView(buildAnlandRecipeRow(recipe));
            }
        }
        return card;
    }

    private String anlandRecipeSummary() {
        if (displayAnlandRecipesStatus == null) {
            return "recipes=module_unavailable\nexecutor=false";
        }
        JSONObject preflight = displayAnlandRecipesStatus.optJSONObject("preflight");
        JSONObject artifact = displayAnlandRecipesStatus.optJSONObject("artifact");
        String selected = preflight == null
                ? "unknown" : preflight.optString("selected_container", "unknown");
        String source = preflight == null
                ? "unknown" : preflight.optString("container_selection_source", "unknown");
        String sha = artifact == null ? "unknown" : artifact.optString("sha256", "unknown");
        return "manifestOnly=" + displayAnlandRecipesStatus.optBoolean("recipe_manifest_only", true)
                + "\nexecutor=" + displayAnlandRecipesStatus.optBoolean("executor_available", true)
                + "\nselectedContainer=" + selected
                + "  source=" + source
                + "\nartifactSha=" + sha;
    }

    private String anlandRecipeTopLabel() {
        if (displayAnlandRecipesStatus == null) return "Unknown";
        JSONObject preflight = displayAnlandRecipesStatus.optJSONObject("preflight");
        if (preflight != null && preflight.optBoolean("display_ready", false)) return "Display";
        if (preflight != null && preflight.optBoolean("runtime_ready", false)) return "Runtime";
        return "Manifest";
    }

    private int anlandRecipeTopColor() {
        if (displayAnlandRecipesStatus == null) return BLUE;
        JSONObject preflight = displayAnlandRecipesStatus.optJSONObject("preflight");
        if (preflight != null && preflight.optBoolean("display_ready", false)) return GREEN;
        if (preflight != null && preflight.optBoolean("runtime_ready", false)) return CYAN;
        return YELLOW;
    }

    private View buildAnlandRecipeRow(JSONObject recipe) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(0, dp(10), 0, dp(4));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(top);

        TextView label = text(recipe.optString("title", recipe.optString("id", "Recipe")),
                15, TEXT, Typeface.BOLD);
        top.addView(label, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        String status = recipe.optString("status", "unknown");
        int color = recipe.optBoolean("mutating", false) ? YELLOW : CYAN;
        if (status.contains("not_allowed")) color = RED;
        top.addView(chip(status.length() > 14 ? status.substring(0, 14) : status, color));

        TextView detail = text(anlandRecipeDetail(recipe), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(6), 0, 0);
        row.addView(detail);
        return row;
    }

    private String anlandRecipeDetail(JSONObject recipe) {
        StringBuilder builder = new StringBuilder();
        builder.append("id=").append(recipe.optString("id", "unknown"));
        builder.append("\nscript=").append(recipe.optString("source_script", "unknown"));
        builder.append("\nkind=").append(recipe.optString("kind", "unknown"));
        builder.append("\nmutating=").append(recipe.optBoolean("mutating", false));
        builder.append("  exposed=").append(recipe.optBoolean("exposed_by_nebula", false));
        builder.append("\ncommand=").append(recipe.optString("fixed_command_reference", "unknown"));
        builder.append("\nnote=").append(recipe.optString("note", "unknown"));
        return builder.toString();
    }

    private String displayLaneSummary() {
        if (displayLanesStatus == null) {
            return "selector=module_unavailable\nmode=read_only";
        }
        return "selector=" + displayLanesStatus.optString("selector", "unknown")
                + "\nmode=read_only"
                + "\nprofile=" + coreStatus.profile.wireName
                + "\nsafeMode=" + coreStatus.safeMode;
    }

    private String displayMethodContainersSummary() {
        if (displayMethodContainersStatus == null) {
            return "methodContainers=unavailable";
        }
        JSONArray containers = displayMethodContainersStatus.optJSONArray("containers");
        if (containers == null || containers.length() == 0) {
            return "methodContainers=empty";
        }
        StringBuilder builder = new StringBuilder("methodContainers=");
        for (int i = 0; i < containers.length(); i++) {
            JSONObject container = containers.optJSONObject(i);
            if (container == null) continue;
            if (i > 0) builder.append("\n  ");
            builder.append(container.optString("method_id", "unknown"))
                    .append(" -> ")
                    .append(container.optString("container_ref", "unknown"));
            if (container.has("recommended_container")) {
                builder.append(" recommended=")
                        .append(container.optString("recommended_container", "unknown"));
            }
            builder.append(" status=").append(container.optString("status", "unknown"));
        }
        return builder.toString();
    }

    private String displayMethodProfilesSummary() {
        if (displayMethodProfilesStatus == null) {
            return "methodProfiles=unavailable";
        }
        JSONArray profiles = displayMethodProfilesStatus.optJSONArray("profiles");
        if (profiles == null || profiles.length() == 0) {
            return "methodProfiles=empty";
        }
        StringBuilder builder = new StringBuilder("methodProfiles=");
        for (int i = 0; i < profiles.length(); i++) {
            JSONObject profile = profiles.optJSONObject(i);
            if (profile == null) continue;
            if (i > 0) builder.append("\n  ");
            builder.append(profile.optString("profile_id", "unknown"))
                    .append(" -> ")
                    .append(profile.optString("method_id", "unknown"));
            if (profile.has("container_name")) {
                builder.append(" container=")
                        .append(profile.optString("container_name", "unknown"));
            }
            if (profile.has("rootfs_mode")) {
                builder.append(" rootfs=")
                        .append(profile.optString("rootfs_mode", "unknown"));
            }
        }
        return builder.toString();
    }

    private String displayLaneTopLabel() {
        if (displayLanesStatus == null) return "Unknown";
        return "Multi-lane";
    }

    private int displayLaneTopColor() {
        return displayLanesStatus == null ? BLUE : CYAN;
    }

    private View buildDisplayLaneRow(JSONObject lane) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(0, dp(10), 0, dp(4));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(top);

        String title = lane.optString("title", lane.optString("id", "Lane"));
        String status = lane.optString("status", "unknown");
        TextView label = text(title, 15, TEXT, Typeface.BOLD);
        top.addView(label, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        top.addView(chip(displayStatusLabel(status), displayLaneColor(status)));

        TextView detail = text(displayLaneDetail(lane), 12, MUTED, Typeface.NORMAL);
        detail.setTypeface(Typeface.MONOSPACE);
        detail.setPadding(0, dp(6), 0, 0);
        row.addView(detail);
        return row;
    }

    private String displayStatusLabel(String status) {
        if (status == null || status.isEmpty()) return "Unknown";
        if ("blocked_export".equals(status)) return "Export";
        if ("blocked_real_buffer".equals(status)) return "Real buffer";
        if ("paused_crash_gated".equals(status)) return "Crash-gated";
        if ("reference_only".equals(status)) return "Reference";
        if (status.contains("wayland") && status.contains("pass")) return "Wayland";
        if ("display_preflight_incomplete".equals(status)) return "Partial";
        if ("ready_for_glx_fix".equals(status)) return "Legacy";
        if ("container_runtime_ready".equals(status)) return "Runtime";
        if ("preflight_ready".equals(status)) return "Preflight";
        if (status.contains("reference")) return "Reference";
        if ("safe_mode_blocks_start".equals(status)) return "Safe";
        if ("always_available".equals(status)) return "Ready";
        if ("not_wired".equals(status)) return "Pending";
        return status.length() > 14 ? status.substring(0, 14) : status;
    }

    private int displayLaneColor(String status) {
        if (status == null) return BLUE;
        if (status.contains("blocked") || status.contains("crash_gated")) return YELLOW;
        if (status.contains("ready") || status.contains("pass")
                || status.contains("always_available")) return GREEN;
        if (status.contains("proven")) return CYAN;
        if (status.contains("safe")) return BLUE;
        if (status.contains("partial") || status.contains("not_wired")) return YELLOW;
        if (status.contains("missing")) return RED;
        return BLUE;
    }

    private String displayLaneDetail(JSONObject lane) {
        StringBuilder builder = new StringBuilder();
        builder.append("id=").append(lane.optString("id", "unknown"));
        if (lane.has("state")) {
            builder.append("\nstate=").append(lane.optString("state"));
        }
        builder.append("\navailable=").append(lane.optBoolean("available", false));
        builder.append("  mutating=").append(lane.optBoolean("mutating", false));
        if (lane.has("start_command_available")) {
            builder.append("\nstartCommand=").append(lane.optBoolean("start_command_available", false));
        }
        if (lane.has("launch_command_available")) {
            builder.append("\nlaunchCommand=").append(lane.optBoolean("launch_command_available", false));
        }
        if (lane.has("repair_command_available")) {
            builder.append("\nrepairCommand=").append(lane.optBoolean("repair_command_available", false));
        }
        if (lane.has("active_blocker")) {
            builder.append("\nblocker=").append(lane.optString("active_blocker"));
        }
        if (lane.has("proof_classification")) {
            builder.append("\nproof=").append(lane.optString("proof_classification"));
        }
        if (lane.has("software_glx_reproduced")) {
            builder.append("\nsoftwareGlx=").append(lane.optBoolean("software_glx_reproduced", false));
        }
        if (lane.has("hardware_glx_pass")) {
            builder.append("  hardwareGlx=").append(lane.optBoolean("hardware_glx_pass", false));
        }
        if (lane.has("real_buffer_pass")) {
            builder.append("  realBuffer=").append(lane.optBoolean("real_buffer_pass", false));
        }
        if (lane.has("gl_renderer")) {
            builder.append("\nglRenderer=").append(lane.optString("gl_renderer"));
        }
        if (lane.has("vk_get_memory_fd_failures")) {
            builder.append("\nvkGetMemoryFdFailures=")
                    .append(lane.optInt("vk_get_memory_fd_failures", -1));
        }
        if (lane.has("real_buffer_commits") || lane.has("no_buffer_commits")) {
            builder.append("  realCommits=")
                    .append(lane.optInt("real_buffer_commits", -1));
            builder.append("  noBufferCommits=")
                    .append(lane.optInt("no_buffer_commits", -1));
        }
        if (lane.has("a1_fasttest_env_status")) {
            builder.append("\na1=").append(lane.optString("a1_fasttest_env_status"));
        }
        if (lane.has("dock_lease_state")) {
            builder.append("\ndockLease=").append(lane.optString("dock_lease_state"));
        }
        if (lane.has("rezygisk_provider_state")) {
            builder.append("\nrezygiskProvider=").append(lane.optString("rezygisk_provider_state"));
        }
        if (lane.has("cooling_policy_state")) {
            builder.append("\ncoolingPolicy=").append(lane.optString("cooling_policy_state"));
        }
        if (lane.has("reason")) {
            builder.append("\nreason=").append(lane.optString("reason"));
        }
        if (lane.has("unpromoted_lead")) {
            builder.append("\nlead=").append(lane.optString("unpromoted_lead"));
            builder.append("  status=").append(lane.optString("lead_status", "unknown"));
        }
        if (lane.has("proven_trick")) {
            builder.append("\ntrick=").append(lane.optString("proven_trick"));
            builder.append("  status=").append(lane.optString("lead_status", "unknown"));
        }
        if (lane.has("trick")) {
            builder.append("\ntrick=").append(lane.optString("trick"));
        }
        if (lane.has("next_reversa_action")) {
            builder.append("\nnext=").append(lane.optString("next_reversa_action"));
        }
        if (lane.has("kernel_va_bits_constraint")) {
            builder.append("\nkernelVaBitsConstraint=")
                    .append(lane.optInt("kernel_va_bits_constraint", -1));
        }
        if (lane.has("kernel_va_bits_evidence")) {
            builder.append("  evidence=").append(lane.optString("kernel_va_bits_evidence"));
        }
	        if (lane.has("runtime_blocker")) {
	            builder.append("\nruntimeBlocker=").append(lane.optString("runtime_blocker"));
	        }
	        if (lane.has("selected_icd")) {
	            builder.append("\nselectedIcd=").append(lane.optString("selected_icd"));
	        }
        if (lane.has("selected_vulkan_driver")) {
            builder.append("\nselectedDriver=").append(lane.optString("selected_vulkan_driver"));
        }
        if (lane.has("path_policy")) {
            builder.append("\npathPolicy=").append(lane.optString("path_policy"));
        }
        if (lane.has("package_path")) {
            builder.append("\npackagePath=").append(lane.optString("package_path"));
        }
        if (lane.has("native_lib_dir")) {
            builder.append("\nnativeLibDir=").append(lane.optString("native_lib_dir"));
        }
        if (lane.has("glibc_loader")) {
            builder.append("\nglibcLoader=").append(lane.optString("glibc_loader"));
        }
	    builder.append(loaderPinLines(lane));
	    if (lane.has("runtime_constraint")) {
	        builder.append("\nruntimeConstraint=").append(lane.optString("runtime_constraint"));
	    }
        if (lane.has("evidence_captured")) {
            builder.append("\nevidenceCaptured=").append(lane.optBoolean("evidence_captured", false));
            builder.append("  externalOnly=").append(lane.optBoolean("external_display_only", false));
        }
        JSONObject reported = lane.optJSONObject("reported_objects");
        if (reported != null) {
            builder.append("\nreportedObjects=connector ")
                    .append(reported.optInt("connector", -1))
                    .append(" crtc ")
                    .append(reported.optInt("crtc", -1))
                    .append(" planes ")
                    .append(reported.optJSONArray("planes"));
        }
        JSONObject checks = lane.optJSONObject("checks");
        if (checks != null) {
            builder.append("\nchecks=").append(checkSummary(checks));
        }
        JSONArray errors = lane.optJSONArray("errors");
        if (errors != null && errors.length() > 0) {
            builder.append("\nerrors=").append(errors);
        }
        builder.append("\nsource=").append(lane.optString("source", "unknown"));
        return builder.toString();
    }

    private String checkSummary(JSONObject checks) {
        StringBuilder builder = new StringBuilder();
        JSONArray names = checks.names();
        if (names == null) return "{}";
        for (int i = 0; i < names.length(); i++) {
            String name = names.optString(i);
            if (i > 0) builder.append(", ");
            builder.append(name).append('=').append(checks.optBoolean(name, false));
        }
        return builder.toString();
    }

    private boolean waylandieRuntimeReady() {
        JSONObject object = waylandieRuntimeStatusObject();
        return object != null && object.optBoolean("ready", false);
    }

    private boolean waylandieRuntimeSafeMode() {
        JSONObject object = waylandieRuntimeStatusObject();
        return object == null || object.optBoolean("safe_mode", true);
    }

    private String waylandieRuntimeLabel() {
        JSONObject object = waylandieRuntimeStatusObject();
        if (object == null) return "Unknown";
        if (object.optBoolean("safe_mode", false)) return "Safe";
        return object.optBoolean("ready", false) ? "Ready" : "Missing";
    }

    private int waylandieRuntimeColor() {
        JSONObject object = waylandieRuntimeStatusObject();
        if (object == null) return BLUE;
        if (object.optBoolean("safe_mode", false)) return YELLOW;
        return object.optBoolean("ready", false) ? GREEN : YELLOW;
    }

    private String waylandieRuntimeDetail() {
        JSONObject object = waylandieRuntimeStatusObject();
        if (object == null) {
            return "moduleStatus=unavailable\nmethod=root_assisted_proot";
        }
	        return "package=" + object.optString("package", "unknown")
	                + "\nmethod=" + object.optString("method", "unknown")
	                + "\npathPolicy=" + object.optString("path_policy", "unknown")
	                + "\npackagePath=" + object.optString("package_path", "unknown")
	                + "\nnativeLibDir=" + object.optString("native_lib_dir", "unknown")
	                + "\nglibcLoader=" + object.optString("glibc_loader", "unknown")
	                + "\nready=" + object.optBoolean("ready", false)
	                + "\nsafeMode=" + object.optBoolean("safe_mode", false)
	                + "\nimagefs=" + jsonBoolLabel(object, "imagefs_present")
	                + "\nproton=" + jsonBoolLabel(object, "proton_present")
	                + "\nwine=" + jsonBoolLabel(object, "wine_present")
	                + "\nselectedIcd=" + object.optString("selected_icd", "unknown")
	                + "\nselectedDriver=" + object.optString("selected_vulkan_driver", "unknown")
	                + loaderPinLines(object)
	                + "\nerrors=" + object.optJSONArray("errors");
	    }

	    private String loaderPinLines(JSONObject object) {
	        JSONObject loaderPin = object.optJSONObject("loader_pin");
	        if (loaderPin == null) {
	            return "";
	        }
	        return "\nVK_ICD_FILENAMES=" + loaderPin.optString("VK_ICD_FILENAMES", "unknown")
	                + "\nVK_DRIVER_FILES=" + loaderPin.optString("VK_DRIVER_FILES", "unknown");
	    }

    private void runWaylandieSmoke() {
        CommandResult result = coreClient.waylandieProtonSmoke();
        if (result.ok()) {
            toast("WayLandIE Proton smoke passed");
        } else {
            toast(commandMessage("WayLandIE smoke", result));
        }
        refresh();
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

        Button select = smallButton(profile.enabled ? "Preview" : "Blocked",
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
        toast(profile.label + " previewed");
        refresh();
    }

    private String profileStatusLabel(TargetProfile profile) {
        if (profile.id.equals(selectedTargetProfileId)) return "Preview";
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

        appendStandaloneIntegrationsReport(sb);
        appendBaselineIntegrationsReport(sb);

        sb.append("[Display Lanes]\n");
        if (displayLanesStatus == null) {
            sb.append("  status=unavailable\n\n");
        } else {
            sb.append("  selector=").append(displayLanesStatus.optString("selector", "unknown")).append('\n');
            JSONArray lanes = displayLanesStatus.optJSONArray("lanes");
            if (lanes != null) {
                for (int i = 0; i < lanes.length(); i++) {
                    JSONObject lane = lanes.optJSONObject(i);
                    if (lane == null) continue;
                    sb.append("  ").append(lane.optString("title", lane.optString("id", "Lane")))
                            .append(": ").append(lane.optString("status", "unknown")).append('\n');
                    sb.append("    id=").append(lane.optString("id", "unknown")).append('\n');
                    if (lane.has("state")) {
                        sb.append("    state=").append(lane.optString("state")).append('\n');
                    }
                    sb.append("    available=").append(lane.optBoolean("available", false)).append('\n');
                    sb.append("    mutating=").append(lane.optBoolean("mutating", false)).append('\n');
                    if (lane.has("active_blocker")) {
                        sb.append("    blocker=").append(lane.optString("active_blocker")).append('\n');
                    }
                    if (lane.has("proof_classification")) {
                        sb.append("    proof=")
                                .append(lane.optString("proof_classification")).append('\n');
                    }
                    if (lane.has("software_glx_reproduced")) {
                        sb.append("    softwareGlx=")
                                .append(lane.optBoolean("software_glx_reproduced", false)).append('\n');
                    }
                    if (lane.has("hardware_glx_pass")) {
                        sb.append("    hardwareGlx=")
                                .append(lane.optBoolean("hardware_glx_pass", false)).append('\n');
                    }
                    if (lane.has("real_buffer_pass")) {
                        sb.append("    realBuffer=")
                                .append(lane.optBoolean("real_buffer_pass", false)).append('\n');
                    }
                    if (lane.has("gl_renderer")) {
                        sb.append("    glRenderer=").append(lane.optString("gl_renderer")).append('\n');
                    }
                    if (lane.has("vk_get_memory_fd_failures")) {
                        sb.append("    vkGetMemoryFdFailures=")
                                .append(lane.optInt("vk_get_memory_fd_failures", -1)).append('\n');
                    }
                    if (lane.has("real_buffer_commits") || lane.has("no_buffer_commits")) {
                        sb.append("    realCommits=")
                                .append(lane.optInt("real_buffer_commits", -1))
                                .append(" noBufferCommits=")
                                .append(lane.optInt("no_buffer_commits", -1)).append('\n');
                    }
                    if (lane.has("a1_fasttest_env_status")) {
                        sb.append("    a1=")
                                .append(lane.optString("a1_fasttest_env_status")).append('\n');
                    }
                    if (lane.has("dock_lease_state")) {
                        sb.append("    dockLease=")
                                .append(lane.optString("dock_lease_state")).append('\n');
                    }
                    if (lane.has("unpromoted_lead")) {
                        sb.append("    lead=").append(lane.optString("unpromoted_lead")).append('\n');
                        sb.append("    leadStatus=").append(lane.optString("lead_status", "unknown")).append('\n');
                    }
                    if (lane.has("proven_trick")) {
                        sb.append("    trick=").append(lane.optString("proven_trick")).append('\n');
                        sb.append("    leadStatus=").append(lane.optString("lead_status", "unknown")).append('\n');
                    }
                    if (lane.has("next_reversa_action")) {
                        sb.append("    next=").append(lane.optString("next_reversa_action")).append('\n');
                    }
                    if (lane.has("kernel_va_bits_constraint")) {
                        sb.append("    kernelVaBitsConstraint=")
                                .append(lane.optInt("kernel_va_bits_constraint", -1)).append('\n');
                    }
	                    if (lane.has("runtime_blocker")) {
	                        sb.append("    runtimeBlocker=")
	                                .append(lane.optString("runtime_blocker")).append('\n');
	                    }
	                    if (lane.has("selected_icd")) {
	                        sb.append("    selectedIcd=")
	                                .append(lane.optString("selected_icd")).append('\n');
	                    }
	                    if (lane.has("selected_vulkan_driver")) {
	                        sb.append("    selectedDriver=")
	                                .append(lane.optString("selected_vulkan_driver")).append('\n');
	                    }
	                    if (lane.has("path_policy")) {
	                        sb.append("    pathPolicy=")
	                                .append(lane.optString("path_policy")).append('\n');
	                    }
	                    if (lane.has("package_path")) {
	                        sb.append("    packagePath=")
	                                .append(lane.optString("package_path")).append('\n');
	                    }
	                    if (lane.has("native_lib_dir")) {
	                        sb.append("    nativeLibDir=")
	                                .append(lane.optString("native_lib_dir")).append('\n');
	                    }
	                    if (lane.has("glibc_loader")) {
	                        sb.append("    glibcLoader=")
	                                .append(lane.optString("glibc_loader")).append('\n');
	                    }
	                    JSONObject loaderPin = lane.optJSONObject("loader_pin");
	                    if (loaderPin != null) {
	                        sb.append("    VK_ICD_FILENAMES=")
	                                .append(loaderPin.optString("VK_ICD_FILENAMES", "unknown"))
	                                .append('\n');
	                        sb.append("    VK_DRIVER_FILES=")
	                                .append(loaderPin.optString("VK_DRIVER_FILES", "unknown"))
	                                .append('\n');
	                    }
	                    if (lane.has("evidence_captured")) {
	                        sb.append("    evidenceCaptured=").append(lane.optBoolean("evidence_captured", false)).append('\n');
	                    }
                    sb.append("    source=").append(lane.optString("source", "unknown")).append('\n');
                }
            }
            sb.append('\n');
        }

        sb.append("[Method Containers]\n");
        if (displayMethodContainersStatus == null) {
            sb.append("  status=unavailable\n\n");
        } else {
            JSONArray containers = displayMethodContainersStatus.optJSONArray("containers");
            if (containers != null) {
                for (int i = 0; i < containers.length(); i++) {
                    JSONObject container = containers.optJSONObject(i);
                    if (container == null) continue;
                    sb.append("  ").append(container.optString("method_id", "unknown"))
                            .append(": ").append(container.optString("container_ref", "unknown"))
                            .append('\n');
                    sb.append("    kind=").append(container.optString("container_kind", "unknown")).append('\n');
                    sb.append("    status=").append(container.optString("status", "unknown")).append('\n');
                    if (container.has("recommended_container")) {
                        sb.append("    recommended=")
                                .append(container.optString("recommended_container", "unknown")).append('\n');
                    }
                    JSONArray missing = container.optJSONArray("missing_requirements");
                    if (missing != null && missing.length() > 0) {
                        sb.append("    missing=").append(missing).append('\n');
                    }
                }
            }
            sb.append('\n');
        }

        sb.append("[Method Profiles]\n");
        if (displayMethodProfilesStatus == null) {
            sb.append("  status=unavailable\n\n");
        } else {
            sb.append("  rootfsPolicy=")
                    .append(displayMethodProfilesStatus.optString("rootfs_policy", "unknown"))
                    .append('\n');
            JSONArray profiles = displayMethodProfilesStatus.optJSONArray("profiles");
            if (profiles != null) {
                for (int i = 0; i < profiles.length(); i++) {
                    JSONObject profile = profiles.optJSONObject(i);
                    if (profile == null) continue;
                    sb.append("  ").append(profile.optString("profile_id", "unknown"))
                            .append(": ").append(profile.optString("method_id", "unknown"))
                            .append('\n');
                    if (profile.has("container_name")) {
                        sb.append("    container=")
                                .append(profile.optString("container_name", "unknown"))
                                .append('\n');
                    }
                    if (profile.has("config_path")) {
                        sb.append("    config=")
                                .append(profile.optString("config_path", "unknown"))
                                .append('\n');
                    }
                    if (profile.has("env_file")) {
                        sb.append("    env=")
                                .append(profile.optString("env_file", "unknown"))
                                .append('\n');
                    }
                }
            }
            sb.append('\n');
        }

        appendAnlandRecipesReport(sb);

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
        sb.append("[Nubia Toolkit]\n");
        sb.append("  status=").append(nubiaToolkitStatusLabel()).append('\n');
        sb.append("  ").append(nubiaToolkitDetail().replace("\n", "\n  ")).append('\n');
        sb.append("  hookMutation=deferred\n\n");

        sb.append("[ADB Wi-Fi]\n");
        sb.append("  status=").append(adbWifiStatus()).append('\n');
        sb.append("  ").append(adbWifiDetail().replace("\n", "\n  ")).append('\n');
        sb.append("  mutating=opt-in\n\n");

        appendCapabilities(sb, "Performance", redMagicPerformanceAdapter.discover(this, redMagicProbe));
        appendCapabilities(sb, "RedMagic Button", redMagicButtonAdapter.discover(this));

        sb.append("[WayLandIE Runtime]\n");
        sb.append("  status=").append(waylandieRuntimeLabel()).append('\n');
        sb.append("  ").append(waylandieRuntimeDetail().replace("\n", "\n  ")).append('\n');
        sb.append("  command=runtime waylandie proton-smoke --json\n\n");

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

    private void appendStandaloneIntegrationsReport(StringBuilder sb) {
        sb.append("[Standalone Control Deck]\n");
        if (standaloneIntegrationsStatus == null) {
            sb.append("  status=unavailable\n\n");
            return;
        }
        sb.append("  standalone=")
                .append(standaloneIntegrationsStatus.optString("standalone_id", "unknown"))
                .append('\n');
        sb.append("  mode=").append(standaloneIntegrationsStatus.optString("mode", "unknown")).append('\n');
        sb.append("  apk=").append(standaloneIntegrationsStatus.optString("apk_package", "unknown")).append('\n');
        sb.append("  module=").append(standaloneIntegrationsStatus.optString("module_id", "unknown")).append('\n');
        JSONObject contract = standaloneIntegrationsStatus.optJSONObject("contract");
        if (contract != null) {
            sb.append("  singleApk=").append(contract.optBoolean("single_apk", false)).append('\n');
            sb.append("  singleModule=").append(contract.optBoolean("single_core_module", false)).append('\n');
            sb.append("  fixedCommands=").append(contract.optBoolean("fixed_commands_only", false)).append('\n');
            sb.append("  activeFirst=").append(contract.optBoolean("active_module_first", false)).append('\n');
            sb.append("  pendingDefault=").append(contract.optBoolean("pending_module_default", true)).append('\n');
        }
        JSONArray layers = standaloneIntegrationsStatus.optJSONArray("ownership_layers");
        if (layers != null) {
            for (int i = 0; i < layers.length(); i++) {
                JSONObject layer = layers.optJSONObject(i);
                if (layer == null) continue;
                sb.append("  ").append(layer.optString("id", "unknown"))
                        .append(": ").append(layer.optString("bundled_in", "unknown")).append('\n');
                sb.append("    owner=").append(layer.optString("owner", "unknown")).append('\n');
                sb.append("    mutationAuthority=")
                        .append(layer.optBoolean("mutation_authority", false)).append('\n');
                sb.append("    promotion=")
                        .append(layer.optString("promotion_state",
                                layer.optString("mutation_policy", "status_only")))
                        .append('\n');
            }
        }
        sb.append("  nextUserAction=")
                .append(standaloneIntegrationsStatus.optString("next_user_action", "unknown"))
                .append('\n');
        sb.append("  nextEngineeringAction=")
                .append(standaloneIntegrationsStatus.optString("next_engineering_action", "unknown"))
                .append("\n\n");
    }

    private void appendBaselineIntegrationsReport(StringBuilder sb) {
        sb.append("[Baseline Integrations]\n");
        if (baselineIntegrationsStatus == null) {
            sb.append("  status=unavailable\n\n");
            return;
        }
        sb.append("  baseline=").append(baselineIntegrationsStatus.optString("baseline_id", "unknown")).append('\n');
        sb.append("  overall=").append(baselineIntegrationsStatus.optString("overall_status", "unknown")).append('\n');
        sb.append("  safeDefault=").append(baselineIntegrationsStatus.optBoolean("safe_default", true)).append('\n');
        sb.append("  mutatingControls=")
                .append(baselineIntegrationsStatus.optBoolean("mutating_controls_enabled", false))
                .append('\n');
        JSONArray integrations = baselineIntegrationsStatus.optJSONArray("integrations");
        if (integrations != null) {
            for (int i = 0; i < integrations.length(); i++) {
                JSONObject integration = integrations.optJSONObject(i);
                if (integration == null) continue;
                sb.append("  ").append(integration.optString("id", "unknown"))
                        .append(": ").append(integration.optString("status", "unknown")).append('\n');
                sb.append("    installed=").append(integration.optBoolean("installed", false)).append('\n');
                sb.append("    ready=").append(integration.optBoolean("ready", false)).append('\n');
                sb.append("    mutating=").append(integration.optBoolean("mutating", false)).append('\n');
                sb.append("    role=").append(integration.optString("role", "unknown")).append('\n');
                if (integration.has("selected_container")) {
                    sb.append("    selectedContainer=")
                            .append(integration.optString("selected_container", "unknown"))
                            .append('\n');
                }
                if (integration.has("container_selection_source")) {
                    sb.append("    containerSelection=")
                            .append(integration.optString("container_selection_source", "unknown"))
                            .append('\n');
                }
                sb.append("    source=").append(integration.optString("source", "unknown")).append('\n');
            }
        }
        sb.append("  nextStep=").append(baselineIntegrationsStatus.optString("next_step", "unknown")).append("\n\n");
    }

    private void appendAnlandRecipesReport(StringBuilder sb) {
        sb.append("[Anland Desktop Recipes]\n");
        if (displayAnlandRecipesStatus == null) {
            sb.append("  status=unavailable\n\n");
            return;
        }
        sb.append("  manifestOnly=")
                .append(displayAnlandRecipesStatus.optBoolean("recipe_manifest_only", true))
                .append('\n');
        sb.append("  executorAvailable=")
                .append(displayAnlandRecipesStatus.optBoolean("executor_available", true))
                .append('\n');
        JSONObject artifact = displayAnlandRecipesStatus.optJSONObject("artifact");
        if (artifact != null) {
            sb.append("  artifactSha=").append(artifact.optString("sha256", "unknown")).append('\n');
            sb.append("  payloadsCommitted=")
                    .append(artifact.optBoolean("public_repo_payloads_committed", true))
                    .append('\n');
        }
        JSONObject preflight = displayAnlandRecipesStatus.optJSONObject("preflight");
        if (preflight != null) {
            sb.append("  selectedContainer=")
                    .append(preflight.optString("selected_container", "unknown"))
                    .append('\n');
            sb.append("  selectionSource=")
                    .append(preflight.optString("container_selection_source", "unknown"))
                    .append('\n');
            sb.append("  runtimeReady=")
                    .append(preflight.optBoolean("runtime_ready", false)).append('\n');
            sb.append("  displayReady=")
                    .append(preflight.optBoolean("display_ready", false)).append('\n');
            JSONObject checks = preflight.optJSONObject("checks");
            if (checks != null) {
                sb.append("  checks=").append(checkSummary(checks)).append('\n');
            }
        }
        JSONArray drift = displayAnlandRecipesStatus.optJSONArray("source_drift");
        if (drift != null && drift.length() > 0) {
            sb.append("  sourceDrift=").append(drift).append('\n');
        }
        JSONArray recipes = displayAnlandRecipesStatus.optJSONArray("recipes");
        if (recipes != null) {
            for (int i = 0; i < recipes.length(); i++) {
                JSONObject recipe = recipes.optJSONObject(i);
                if (recipe == null) continue;
                sb.append("  ").append(recipe.optString("id", "unknown"))
                        .append(": ").append(recipe.optString("status", "unknown")).append('\n');
                sb.append("    mutating=").append(recipe.optBoolean("mutating", false)).append('\n');
                sb.append("    exposed=").append(recipe.optBoolean("exposed_by_nebula", false)).append('\n');
                sb.append("    script=").append(recipe.optString("source_script", "unknown")).append('\n');
            }
        }
        sb.append("  next=")
                .append(displayAnlandRecipesStatus.optString("safe_next_action", "unknown"))
                .append("\n\n");
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
        view.setShadowLayer(dp(2), 0, dp(1), 0xF0000000);
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

    @SuppressWarnings("deprecation")
    private void applyScrollBackplane(View view) {
        BitmapDrawable drawable = (BitmapDrawable) getResources()
                .getDrawable(R.drawable.nebula_scroll_backplane);
        drawable.setTileModeX(Shader.TileMode.CLAMP);
        drawable.setTileModeY(Shader.TileMode.CLAMP);
        drawable.setGravity(Gravity.TOP | Gravity.CENTER_HORIZONTAL);
        view.setBackground(drawable);
    }

    private LinearLayout baseCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(14), dp(14), dp(14));
        card.setBackground(round(PANEL, dp(6), LINE));

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
        button.setTextColor(color == PANEL_ALT ? TEXT : color);
        button.setTextSize(13);
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setAllCaps(false);
        button.setMinHeight(dp(42));
        button.setPadding(dp(6), 0, dp(6), 0);
        button.setBackground(round(0xE80A0E13, dp(6), color));
        return button;
    }

    private Button smallButton(String label, int color) {
        Button button = actionButton(label, color);
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
