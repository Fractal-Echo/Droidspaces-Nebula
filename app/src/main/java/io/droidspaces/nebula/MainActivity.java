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
    private TextView reportView;
    private String selectedTargetProfileId = "recovery_safe";

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

    private View buildContent() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(BG);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(18), dp(20), dp(18), dp(24));
        scroll.addView(root, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView title = text("DroidSpaces Nebula", 28, TEXT, Typeface.BOLD);
        root.addView(title);

        TextView subtitle = text("Selector and doctor for RM11 Pro desktop, Wayland, and PowerDeck lanes.",
                15, MUTED, Typeface.NORMAL);
        subtitle.setPadding(0, dp(6), 0, dp(14));
        root.addView(subtitle);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        actions.setPadding(0, 0, 0, dp(14));
        root.addView(actions);

        Button refresh = actionButton("Refresh", BLUE);
        refresh.setOnClickListener(v -> refresh());
        actions.addView(refresh, weightedButtonParams());

        Button copy = actionButton("Copy report", GREEN);
        copy.setOnClickListener(v -> copyReport());
        actions.addView(copy, weightedButtonParams());

        Button share = actionButton("Share", YELLOW);
        share.setOnClickListener(v -> shareReport());
        actions.addView(share, weightedButtonParams());

        TextView targetTitle = text("DroidSpace targets", 18, TEXT, Typeface.BOLD);
        targetTitle.setPadding(0, 0, 0, dp(8));
        root.addView(targetTitle);

        targetProfileContainer = new LinearLayout(this);
        targetProfileContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(targetProfileContainer);

        TextView laneTitle = text("Proof lanes", 18, TEXT, Typeface.BOLD);
        laneTitle.setPadding(0, dp(2), 0, dp(8));
        root.addView(laneTitle);

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
        targetProfileContainer.removeAllViews();
        for (TargetProfile profile : targetProfiles) {
            targetProfileContainer.addView(buildTargetProfileCard(profile));
        }

        laneContainer.removeAllViews();
        for (Lane lane : lanes) {
            laneContainer.addView(buildLaneCard(lane));
        }
        reportView.setText(buildReport());
    }

    private View buildTargetProfileCard(TargetProfile profile) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(14), dp(14), dp(14));
        card.setBackground(round(PANEL, dp(8), LINE));

        LinearLayout.LayoutParams cardParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        cardParams.bottomMargin = dp(12);
        card.setLayoutParams(cardParams);

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
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(14), dp(14), dp(14));
        card.setBackground(round(PANEL, dp(8), LINE));

        LinearLayout.LayoutParams cardParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        cardParams.bottomMargin = dp(12);
        card.setLayoutParams(cardParams);

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
        sb.append("DroidSpaces Nebula Doctor v0.1.1\n");
        sb.append("Generated: ").append(new SimpleDateFormat(
                "yyyy-MM-dd HH:mm:ss Z", Locale.US).format(new Date())).append('\n');
        sb.append("Device: ").append(Build.MANUFACTURER).append(' ')
                .append(Build.MODEL).append('\n');
        sb.append("Build.DEVICE: ").append(Build.DEVICE).append('\n');
        sb.append("Build.BOARD: ").append(Build.BOARD).append('\n');
        sb.append("Build.HARDWARE: ").append(Build.HARDWARE).append('\n');
        sb.append("SDK: ").append(Build.VERSION.SDK_INT).append('\n');
        sb.append("ABIs: ").append(Arrays.toString(Build.SUPPORTED_ABIS)).append("\n\n");

        sb.append("[DroidSpace targets]\n");
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
