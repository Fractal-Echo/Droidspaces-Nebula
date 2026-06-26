package io.droidspaces.nebula.core;

public final class NebulaCapability {
    public final String id;
    public final String title;
    public final String status;
    public final String detail;
    public final boolean mutating;
    public final String source;

    public NebulaCapability(String id, String title, String status, String detail,
            boolean mutating, String source) {
        this.id = id;
        this.title = title;
        this.status = status;
        this.detail = detail;
        this.mutating = mutating;
        this.source = source;
    }
}
