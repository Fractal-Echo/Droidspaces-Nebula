package io.droidspaces.nebula.core;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.TimeUnit;

public final class NebulaCoreClient {
    private static final String ROOT_SHELL = "/system/bin/su";
    private static final String ROOT_MOUNT_MASTER_ARG = "-mm";
    private static final String ACTIVE_MODULE_CLI =
            "/data/adb/modules/nebula_core/bin/nebula-core";
    private static final String PENDING_MODULE_CLI =
            "/data/adb/modules_update/nebula_core/bin/nebula-core";
    private static final String MODULE_CLI_DISPATCH =
            "NEBULA_CORE_CLI=''; "
                    + "if [ -x " + ACTIVE_MODULE_CLI + " ]; then NEBULA_CORE_CLI="
                    + ACTIVE_MODULE_CLI + "; "
                    + "elif [ -x " + PENDING_MODULE_CLI + " ]; then NEBULA_CORE_CLI="
                    + PENDING_MODULE_CLI + "; "
                    + "else echo 'Nebula Core module path is not visible' >&2; exit 127; fi; "
                    + "exec \"$NEBULA_CORE_CLI\"";
    private static final long TIMEOUT_MS = 2500L;
    private static final long TELEMETRY_TIMEOUT_MS = 12000L;
    private static final long SMOKE_TIMEOUT_MS = 30000L;
    private static final Set<String> STATIC_COMMANDS = new HashSet<>(Arrays.asList(
            "status --json",
            "capabilities --json",
            "profile get --json",
            "profile set safe",
            "profile set phone",
            "profile set dock",
            "profile set compatibility",
            "safe-mode get --json",
            "safe-mode enable",
            "adb-wifi status --json",
            "adb-wifi enable --json",
            "adb-wifi auto-disable --json",
            "cooling policy --json",
            "redmagic probe --json",
            "redmagic pump probe --json",
            "integrations baseline --json",
            "nubia toolkit status --json",
            "runtime waylandie status --json",
            "runtime waylandie proton-smoke --json",
            "display lanes --json",
            "display method-containers --json",
            "display lane phone preflight --json",
            "display lane anland preflight --json",
            "display lane dock preflight --json"
    ));

    public NebulaCoreStatus loadStatus() {
        CommandResult result = runFixed("status", "--json");
        if (!result.ok()) {
            return NebulaCoreStatus.absent(commandError("status", result));
        }
        return NebulaCoreProtocol.parseStatus(result.stdout);
    }

    public CommandResult capabilities() {
        return runFixed("capabilities", "--json");
    }

    public CommandResult profileGet() {
        return runFixed("profile", "get", "--json");
    }

    public CommandResult profileSet(NebulaProfile profile) {
        if (!NebulaCoreProtocol.isAllowedProfile(profile)) {
            return new CommandResult(2, "", "profile not allowlisted", false);
        }
        return runFixed("profile", "set", profile.wireName);
    }

    public CommandResult safeModeGet() {
        return runFixed("safe-mode", "get", "--json");
    }

    public CommandResult safeModeEnable() {
        return runFixed("safe-mode", "enable");
    }

    public CommandResult adbWifiStatus() {
        return runFixed("adb-wifi", "status", "--json");
    }

    public CommandResult adbWifiEnable() {
        return runFixed("adb-wifi", "enable", "--json");
    }

    public CommandResult adbWifiAutoDisable() {
        return runFixed("adb-wifi", "auto-disable", "--json");
    }

    public CommandResult logsTail(int lines) {
        return runFixed("logs", "tail", "--lines",
                String.valueOf(NebulaCoreProtocol.sanitizeTailLines(lines)));
    }

    public CommandResult coolingPolicy() {
        return runFixed("cooling", "policy", "--json");
    }

    public CommandResult redMagicProbe() {
        return runFixed("redmagic", "probe", "--json");
    }

    public CommandResult redMagicPumpProbe() {
        return runFixed("redmagic", "pump", "probe", "--json");
    }

    public CommandResult baselineIntegrations() {
        return runFixed("integrations", "baseline", "--json");
    }

    public CommandResult nubiaToolkitStatus() {
        return runFixed("nubia", "toolkit", "status", "--json");
    }

    public CommandResult waylandieRuntimeStatus() {
        return runFixed("runtime", "waylandie", "status", "--json");
    }

    public CommandResult waylandieProtonSmoke() {
        return runFixed("runtime", "waylandie", "proton-smoke", "--json");
    }

    public CommandResult displayLanes() {
        return runFixed("display", "lanes", "--json");
    }

    public CommandResult displayMethodContainers() {
        return runFixed("display", "method-containers", "--json");
    }

    public CommandResult displayLanePhonePreflight() {
        return runFixed("display", "lane", "phone", "preflight", "--json");
    }

    public CommandResult displayLaneAnlandPreflight() {
        return runFixed("display", "lane", "anland", "preflight", "--json");
    }

    public CommandResult displayLaneDockPreflight() {
        return runFixed("display", "lane", "dock", "preflight", "--json");
    }

    public String executionModeLabel() {
        return "app_uid:/system/bin/su telemetry:-mm";
    }

    public String moduleDispatchLabel() {
        return "fixed_active_or_pending_nebula_core_cli";
    }

    private CommandResult runFixed(String... args) {
        String logical = joinArgs(args);
        if (!isAllowlisted(logical)) {
            return new CommandResult(2, "", "command not allowlisted", false);
        }
        long timeoutMs = timeoutFor(logical);
        return runRoot(MODULE_CLI_DISPATCH + " " + logical, timeoutMs,
                preferMountMaster(logical));
    }

    private long timeoutFor(String logical) {
        if ("runtime waylandie proton-smoke --json".equals(logical)) {
            return SMOKE_TIMEOUT_MS;
        }
        if ("redmagic probe --json".equals(logical)
                || "redmagic pump probe --json".equals(logical)
                || "cooling policy --json".equals(logical)
                || "integrations baseline --json".equals(logical)
                || "runtime waylandie status --json".equals(logical)
                || "display lanes --json".equals(logical)
                || "display method-containers --json".equals(logical)
                || "display lane phone preflight --json".equals(logical)
                || "display lane anland preflight --json".equals(logical)
                || "display lane dock preflight --json".equals(logical)) {
            return TELEMETRY_TIMEOUT_MS;
        }
        return TIMEOUT_MS;
    }

    private boolean preferMountMaster(String logical) {
        return "integrations baseline --json".equals(logical)
                || "runtime waylandie status --json".equals(logical)
                || "runtime waylandie proton-smoke --json".equals(logical)
                || "display lanes --json".equals(logical)
                || "display method-containers --json".equals(logical)
                || "display lane phone preflight --json".equals(logical)
                || "display lane anland preflight --json".equals(logical)
                || "display lane dock preflight --json".equals(logical);
    }

    private boolean isAllowlisted(String logical) {
        if (STATIC_COMMANDS.contains(logical)) {
            return true;
        }
        if (logical.startsWith("logs tail --lines ")) {
            String value = logical.substring("logs tail --lines ".length());
            try {
                int lines = Integer.parseInt(value);
                return lines >= 1 && lines <= 500;
            } catch (NumberFormatException ignored) {
                return false;
            }
        }
        return false;
    }

    private CommandResult runRoot(String fixedCommand, long timeoutMs, boolean preferMountMaster) {
        CommandResult result = runRootOnce(fixedCommand, timeoutMs, preferMountMaster);
        if (preferMountMaster && mountMasterUnsupported(result)) {
            return runRootOnce(fixedCommand, timeoutMs, false);
        }
        return result;
    }

    private boolean mountMasterUnsupported(CommandResult result) {
        if (result.ok()) {
            return false;
        }
        String output = (result.stderr + "\n" + result.stdout).toLowerCase();
        return output.contains("invalid option")
                || output.contains("unknown option")
                || output.contains("unrecognized option")
                || output.contains("usage:");
    }

    private CommandResult runRootOnce(String fixedCommand, long timeoutMs, boolean mountMaster) {
        Process process = null;
        try {
            ProcessBuilder builder = mountMaster
                    ? new ProcessBuilder(ROOT_SHELL, ROOT_MOUNT_MASTER_ARG, "-c", fixedCommand)
                    : new ProcessBuilder(ROOT_SHELL, "-c", fixedCommand);
            process = builder.start();
            StreamReader stdout = new StreamReader(process.getInputStream());
            StreamReader stderr = new StreamReader(process.getErrorStream());
            Thread outThread = new Thread(stdout, "nebula-core-stdout");
            Thread errThread = new Thread(stderr, "nebula-core-stderr");
            outThread.start();
            errThread.start();
            boolean finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS);
            if (!finished) {
                process.destroyForcibly();
                return new CommandResult(124, stdout.value(), stderr.value(), true);
            }
            outThread.join(200L);
            errThread.join(200L);
            return new CommandResult(process.exitValue(), stdout.value(), stderr.value(), false);
        } catch (IOException error) {
            return new CommandResult(127, "", error.getMessage(), false);
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            if (process != null) {
                process.destroyForcibly();
            }
            return new CommandResult(130, "", "interrupted", false);
        }
    }

    private String commandError(String command, CommandResult result) {
        if (result.timedOut) {
            return command + " timed out";
        }
        String message = result.stderr.isEmpty() ? result.stdout : result.stderr;
        if (message.isEmpty()) {
            message = "exit " + result.exitCode;
        }
        return command + " failed: " + message;
    }

    private String joinArgs(String... args) {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < args.length; i++) {
            if (i > 0) {
                builder.append(' ');
            }
            builder.append(args[i]);
        }
        return builder.toString();
    }

    private static final class StreamReader implements Runnable {
        private final InputStream input;
        private final ByteArrayOutputStream output = new ByteArrayOutputStream();

        StreamReader(InputStream input) {
            this.input = input;
        }

        @Override
        public void run() {
            byte[] buffer = new byte[2048];
            int read;
            try {
                while ((read = input.read(buffer)) != -1) {
                    output.write(buffer, 0, read);
                }
            } catch (IOException ignored) {
            }
        }

        String value() {
            return new String(output.toByteArray(), StandardCharsets.UTF_8);
        }
    }
}
