package io.droidspaces.nebula.core;

public enum NebulaProfile {
    SAFE("safe", "Recovery / Safe Mode", false),
    PHONE("phone", "Phone / App Mode", false),
    DOCK("dock", "Dock Mode", true),
    COMPATIBILITY("compatibility", "Compatibility Mode", true);

    public final String wireName;
    public final String label;
    public final boolean blockedInPass01;

    NebulaProfile(String wireName, String label, boolean blockedInPass01) {
        this.wireName = wireName;
        this.label = label;
        this.blockedInPass01 = blockedInPass01;
    }

    public static NebulaProfile fromWireName(String value) {
        for (NebulaProfile profile : values()) {
            if (profile.wireName.equals(value)) {
                return profile;
            }
        }
        return SAFE;
    }
}
