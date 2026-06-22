package io.droidspaces.nebula.core;

public final class NebulaCoreStatus {
    public final boolean installed;
    public final String moduleVersion;
    public final int protocolVersion;
    public final boolean safeMode;
    public final NebulaProfile profile;
    public final boolean daemonRunning;
    public final String serviceStatus;
    public final String gitCommit;
    public final String error;

    public NebulaCoreStatus(boolean installed, String moduleVersion, int protocolVersion,
            boolean safeMode, NebulaProfile profile, boolean daemonRunning,
            String serviceStatus, String gitCommit, String error) {
        this.installed = installed;
        this.moduleVersion = moduleVersion == null ? "unknown" : moduleVersion;
        this.protocolVersion = protocolVersion;
        this.safeMode = safeMode;
        this.profile = profile == null ? NebulaProfile.SAFE : profile;
        this.daemonRunning = daemonRunning;
        this.serviceStatus = serviceStatus == null ? "unknown" : serviceStatus;
        this.gitCommit = gitCommit == null ? "unknown" : gitCommit;
        this.error = error;
    }

    public static NebulaCoreStatus absent(String reason) {
        return new NebulaCoreStatus(false, "absent", NebulaVersions.CORE_PROTOCOL_VERSION,
                true, NebulaProfile.SAFE, false, "read_only", "unknown", reason);
    }

    public boolean protocolMismatch() {
        return installed && protocolVersion != NebulaVersions.CORE_PROTOCOL_VERSION;
    }

    public boolean moduleVersionMismatch() {
        return installed && !NebulaVersions.MODULE_VERSION.equals(moduleVersion);
    }

    public boolean hasVisibleError() {
        return error != null || protocolMismatch() || moduleVersionMismatch();
    }

    public String visibleError() {
        if (error != null) {
            return error;
        }
        if (protocolMismatch()) {
            return "Protocol mismatch: app expects "
                    + NebulaVersions.CORE_PROTOCOL_VERSION + ", module reports " + protocolVersion;
        }
        if (moduleVersionMismatch()) {
            return "Version mismatch: app " + NebulaVersions.APP_VERSION
                    + ", module " + moduleVersion;
        }
        return "";
    }
}
