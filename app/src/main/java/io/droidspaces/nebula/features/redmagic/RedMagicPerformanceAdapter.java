package io.droidspaces.nebula.features.redmagic;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;

import io.droidspaces.nebula.core.NebulaCapability;
import io.droidspaces.nebula.features.nubia.DeviceCapabilityProvider;

public final class RedMagicPerformanceAdapter implements DeviceCapabilityProvider {
    private static final String REDMAGIC_CONTROL_PACKAGE = "com.elitedarkkaiser.redmagic";

    @Override
    public List<NebulaCapability> discover(Context context) {
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
                "Fan, pump, LED, trigger nodes",
                nx809j ? "audited_blocked" : "model_unconfirmed",
                "Paths are documented from RedMagic Control Center and PowerDeck, but no writes are exposed in pass 01.",
                true,
                "HardwareController.kt and RedMagicPowerDeck docs/node-map.md"));

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
}
