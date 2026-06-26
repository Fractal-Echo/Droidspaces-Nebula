package io.droidspaces.nebula.features.redmagic;

import android.content.Context;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;

import io.droidspaces.nebula.core.NebulaCapability;
import io.droidspaces.nebula.features.nubia.DeviceCapabilityProvider;

public final class RedMagicButtonAdapter implements DeviceCapabilityProvider {
    @Override
    public List<NebulaCapability> discover(Context context) {
        List<NebulaCapability> capabilities = new ArrayList<>();
        boolean nx809j = equalsIgnoreCase("NX809J", Build.MODEL)
                || equalsIgnoreCase("NX809J", Build.DEVICE)
                || equalsIgnoreCase("NX809J", Build.PRODUCT);

        capabilities.add(new NebulaCapability(
                "redmagic.button.mapping",
                "RedMagic button mapping",
                "disabled_pass_01",
                "Preferred future short press opens target selector; long press launches last successful target.",
                true,
                "REDMAGIC button audit"));

        capabilities.add(new NebulaCapability(
                "redmagic.button.event_source",
                "Button event source",
                nx809j ? "candidate_sources_audited" : "model_unconfirmed",
                "Reference sources expose F7/F8 accessibility events and root getevent readers for nubia_tgk_aw_sar input devices.",
                true,
                "TriggerAccessibilityService.kt and TriggerRootService.kt"));

        capabilities.add(new NebulaCapability(
                "redmagic.button.fallback",
                "Stock fallback",
                "required",
                "Safe mode or module failure must preserve stock RedMagic behavior.",
                false,
                "REDMAGIC button audit"));

        return capabilities;
    }

    private boolean equalsIgnoreCase(String expected, String actual) {
        return actual != null && expected.equalsIgnoreCase(actual);
    }
}
