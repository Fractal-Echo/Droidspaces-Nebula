package io.droidspaces.nebula.features.nubia;

import android.content.Context;

import java.util.List;

import io.droidspaces.nebula.core.NebulaCapability;

public interface DeviceCapabilityProvider {
    List<NebulaCapability> discover(Context context);
}
