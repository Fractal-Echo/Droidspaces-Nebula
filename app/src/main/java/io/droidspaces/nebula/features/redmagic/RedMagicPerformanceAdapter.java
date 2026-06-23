package io.droidspaces.nebula.features.redmagic;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;

import io.droidspaces.nebula.core.NebulaCapability;
import io.droidspaces.nebula.core.RedMagicProbe;
import io.droidspaces.nebula.features.nubia.DeviceCapabilityProvider;

public final class RedMagicPerformanceAdapter implements DeviceCapabilityProvider {
    private static final String REDMAGIC_CONTROL_PACKAGE = "com.elitedarkkaiser.redmagic";

    @Override
    public List<NebulaCapability> discover(Context context) {
        return discover(context, RedMagicProbe.unavailable("probe not requested"));
    }

    public List<NebulaCapability> discover(Context context, RedMagicProbe probe) {
        List<NebulaCapability> capabilities = new ArrayList<>();
        boolean controlCenter = hasPackage(context, REDMAGIC_CONTROL_PACKAGE);
        boolean nx809j = isNx809j();

        capabilities.add(new NebulaCapability(
                "redmagic.control.permission",
                "RedMagic Control Center source",
                "permission_recorded",
                "User supplied author permission evidence; source remains attributed and is not copied wholesale.",
                false,
                "EliteBlackKaiser permission screenshot"));

        capabilities.add(new NebulaCapability(
                "redmagic.control.package",
                "Installed Control Center",
                controlCenter ? "installed_reference" : "not_installed",
                "Nebula does not depend on the standalone APK; it reimplements bounded status surfaces.",
                false,
                "Redmagic-Control-Center"));

        capabilities.add(new NebulaCapability(
                "redmagic.performance.nodes",
                "Hardware control nodes",
                nx809j ? "audited_blocked" : "model_unconfirmed",
                "Paths are documented from RedMagic Control Center and PowerDeck; pass 03 exposes only read-only telemetry.",
                true,
                "HardwareController.kt and RedMagicPowerDeck docs/node-map.md"));

        capabilities.add(new NebulaCapability(
                "redmagic.probe.device",
                "Device detected",
                probe.available ? "probe_available" : "read_only_unavailable",
                probe.deviceSummary,
                false,
                "nebula-core redmagic probe --json"));

        capabilities.add(new NebulaCapability(
                "redmagic.probe.fan",
                "Internal Fan telemetry",
                probe.available ? "probe_available" : "read_only_unavailable",
                probe.fanSummary,
                false,
                "nebula-core redmagic probe --json"));

        capabilities.add(new NebulaCapability(
                "redmagic.probe.pump",
                "Liquid Cooling Pump",
                pumpStatus(probe),
                probe.pumpSummary,
                false,
                "nebula-core redmagic pump probe --json"));

        capabilities.add(new NebulaCapability(
                "redmagic.probe.performance",
                "Performance mode",
                probe.available ? "probe_available" : "unsupported_or_unavailable",
                probe.performanceSummary,
                false,
                "nebula-core redmagic probe --json"));

        capabilities.add(new NebulaCapability(
                "redmagic.probe.display",
                "Refresh state",
                probe.available ? "probe_available" : "unsupported_or_unavailable",
                probe.displaySummary,
                false,
                "nebula-core redmagic probe --json"));

        capabilities.add(new NebulaCapability(
                "redmagic.probe.thermal",
                "Thermal readings",
                probe.available ? "probe_available" : "read_only_unavailable",
                probe.thermalSummary,
                false,
                "nebula-core redmagic probe --json"));

        capabilities.add(new NebulaCapability(
                "redmagic.cooling.policy",
                "Cooling Engine policy",
                coolingPolicyStatus(probe),
                coolingPolicyDetail(probe),
                false,
                "nebula-core cooling policy --json"));

        capabilities.add(new NebulaCapability(
                "redmagic.gpp.allgame",
                "GPP all-game property",
                "reference_only",
                "gpp-enable-module.zip sets vendor.gpp.allgame.enable at boot; Nebula does not copy or auto-apply it.",
                true,
                "rm11mainassets/modules/gpp-enable-module.zip"));

        return capabilities;
    }

    private boolean isNx809j() {
        return equalsIgnoreCase("NX809J", Build.MODEL)
                || equalsIgnoreCase("NX809J", Build.DEVICE)
                || equalsIgnoreCase("NX809J", Build.PRODUCT);
    }

    private boolean hasPackage(Context context, String packageName) {
        try {
            context.getPackageManager().getPackageInfo(packageName, 0);
            return true;
        } catch (PackageManager.NameNotFoundException ignored) {
            return false;
        }
    }

    private boolean equalsIgnoreCase(String expected, String actual) {
        return actual != null && expected.equalsIgnoreCase(actual);
    }

    private String pumpStatus(RedMagicProbe probe) {
        if (!probe.available) {
            return "read_only_unavailable";
        }
        if (probe.pumpSupported) {
            return "probe_available";
        }
        if (probe.pumpPresent) {
            return "present_no_readable_telemetry";
        }
        return "unsupported_or_unavailable";
    }

    private String coolingPolicyStatus(RedMagicProbe probe) {
        if (!probe.available || probe.coolingPolicy == null || !probe.coolingPolicy.available) {
            return "read_only_unavailable";
        }
        if (!probe.coolingPolicy.configured) {
            return "calibration_required";
        }
        if (probe.coolingPolicy.safeMode) {
            return "safe_mode_preview";
        }
        String state = probe.coolingPolicy.state == null ? "unavailable" : probe.coolingPolicy.state;
        return "preview_" + state.toLowerCase();
    }

    private String coolingPolicyDetail(RedMagicProbe probe) {
        if (probe.coolingPolicy == null) {
            return "cooling policy unavailable";
        }
        RedMagicProbe.CoolingPolicy policy = probe.coolingPolicy;
        return "state=" + policy.state
                + ", previewOnly=" + policy.previewOnly
                + ", fanIntent=" + policy.fanIntent
                + ", pumpIntent=" + policy.pumpIntent
                + ", applied=" + (policy.fanApplied || policy.pumpApplied)
                + ", reason=" + policy.reasonSummary;
    }
}
