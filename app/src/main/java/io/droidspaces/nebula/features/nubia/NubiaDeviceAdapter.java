package io.droidspaces.nebula.features.nubia;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;

import io.droidspaces.nebula.core.NebulaCapability;

public final class NubiaDeviceAdapter implements DeviceCapabilityProvider {
    private static final String TOOLKIT_PACKAGE = "com.khanhnguyen9872.nubiatoolkit";
    private static final String GAME_ASSIST_PACKAGE = "cn.nubia.gameassist";
    private static final String GAME_LAUNCHER_PACKAGE = "cn.nubia.gamelauncher";

    @Override
    public List<NebulaCapability> discover(Context context) {
        List<NebulaCapability> capabilities = new ArrayList<>();
        boolean nx809j = isNx809j();
        boolean gameAssist = hasPackage(context, GAME_ASSIST_PACKAGE);
        boolean gameLauncher = hasPackage(context, GAME_LAUNCHER_PACKAGE);
        boolean toolkit = hasPackage(context, TOOLKIT_PACKAGE);

        capabilities.add(new NebulaCapability(
                "nubia.device.nx809j",
                "NX809J relevance",
                nx809j ? "confirmed_by_build" : "unconfirmed",
                "Build model=" + Build.MODEL + ", device=" + Build.DEVICE,
                false,
                "local Build fields"));

        capabilities.add(new NebulaCapability(
                "nubia.gameassist.package",
                "Game Assist hooks",
                gameAssist ? "package_visible" : "package_missing",
                "Nubia Toolkit targets cn.nubia.gameassist for no-kill, game mode, small-window, Energy Cube, and super-resolution gates.",
                false,
                "NubiaToolkit HookEntry/SuperResolutionHook"));

        capabilities.add(new NebulaCapability(
                "nubia.gamelauncher.package",
                "Game Launcher hooks",
                gameLauncher ? "package_visible" : "package_missing",
                "Nubia Toolkit targets cn.nubia.gamelauncher for watermark and super-resolution control-panel gates.",
                false,
                "NubiaToolkit WatermarkLengthHook/SuperResolutionHook"));

        capabilities.add(new NebulaCapability(
                "nubia.toolkit.compatibility",
                "Nebula Nubia compatibility lane",
                toolkit ? "old_reference_visible" : "ported_status_only",
                "Nebula carries audited Nubia Toolkit knowledge; LSPosed hook activation remains a separate scoped lane.",
                true,
                "NubiaToolkit Apache-2.0"));

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
