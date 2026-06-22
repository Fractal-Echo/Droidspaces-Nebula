package io.droidspaces.nebula.core;

public final class CommandResult {
    public final int exitCode;
    public final String stdout;
    public final String stderr;
    public final boolean timedOut;

    public CommandResult(int exitCode, String stdout, String stderr, boolean timedOut) {
        this.exitCode = exitCode;
        this.stdout = stdout == null ? "" : stdout;
        this.stderr = stderr == null ? "" : stderr;
        this.timedOut = timedOut;
    }

    public boolean ok() {
        return exitCode == 0 && !timedOut;
    }
}
