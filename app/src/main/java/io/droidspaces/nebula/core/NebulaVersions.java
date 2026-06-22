package io.droidspaces.nebula.core;

import io.droidspaces.nebula.BuildConfig;

public final class NebulaVersions {
    public static final String APP_VERSION = BuildConfig.NEBULA_APP_VERSION;
    public static final String MODULE_VERSION = BuildConfig.NEBULA_MODULE_VERSION;
    public static final int CORE_PROTOCOL_VERSION = BuildConfig.NEBULA_CORE_PROTOCOL_VERSION;
    public static final String GIT_COMMIT = BuildConfig.NEBULA_GIT_COMMIT;

    private NebulaVersions() {
    }
}
