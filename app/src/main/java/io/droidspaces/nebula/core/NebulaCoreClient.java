package io.droidspaces.nebula.core;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.TimeUnit;

public final class NebulaCoreClient {
    private static final String MODULE_CLI = "/data/adb/modules/nebula_core/bin/nebula-core";
    private static final long TIMEOUT_MS = 2500L;
    private static final Set<String> STATIC_COMMANDS = new HashSet<>(Arrays.asList(
            "status --json",
            "capabilities --json",
            "profile get --json",
            "profile set safe",
            "profile set phone",
            "profile set dock",
            "profile set compatibility",
            "safe-mode get --json",
            "safe-mode enable"
    ));

    public NebulaCoreStatus loadStatus() {
        if (!isModulePathVisible()) {
            return NebulaCoreStatus.absent("Nebula Core module path is not visible; app is read-only.");
        }
        CommandResult result = runFixed("status", "--json");
        if (!result.ok()) {
            return NebulaCoreStatus.absent(commandError("status", result));
        }
        return NebulaCoreProtocol.parseStatus(result.stdout);
    }

    public CommandResult capabilities() {
        if (!isModulePathVisible()) {
            return new CommandResult(127, "", "Nebula Core module path is not visible", false);
        }
        return runFixed("capabilities", "--json");
    }

    public CommandResult profileGet() {
        if (!isModulePathVisible()) {
            return new CommandResult(127, "", "Nebula Core module path is not visible", false);
        }
        return runFixed("profile", "get", "--json");
    }

    public CommandResult profileSet(NebulaProfile profile) {
        if (!NebulaCoreProtocol.isAllowedProfile(profile)) {
            return new CommandResult(2, "", "profile not allowlisted", false);
        }
        if (!isModulePathVisible()) {
            return new CommandResult(127, "", "Nebula Core module path is not visible", false);
        }
        return runFixed("profile", "set", profile.wireName);
    }

    public CommandResult safeModeGet() {
        if (!isModulePathVisible()) {
            return new CommandResult(127, "", "Nebula Core module path is not visible", false);
        }
        return runFixed("safe-mode", "get", "--json");
    }

    public CommandResult safeModeEnable() {
        if (!isModulePathVisible()) {
            return new CommandResult(127, "", "Nebula Core module path is not visible", false);
        }
        return runFixed("safe-mode", "enable");
    }

    public CommandResult logsTail(int lines) {
        if (!isModulePathVisible()) {
            return new CommandResult(127, "", "Nebula Core module path is not visible", false);
        }
        return runFixed("logs", "tail", "--lines",
                String.valueOf(NebulaCoreProtocol.sanitizeTailLines(lines)));
    }

    private boolean isModulePathVisible() {
        File file = new File(MODULE_CLI);
        return file.isFile() && file.canRead();
    }

    private CommandResult runFixed(String... args) {
        String logical = joinArgs(args);
        if (!isAllowlisted(logical)) {
            return new CommandResult(2, "", "command not allowlisted", false);
        }
        return runRoot(MODULE_CLI + " " + logical);
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

    private CommandResult runRoot(String fixedCommand) {
        Process process = null;
        try {
            process = new ProcessBuilder("su", "-c", fixedCommand).start();
            StreamReader stdout = new StreamReader(process.getInputStream());
            StreamReader stderr = new StreamReader(process.getErrorStream());
            Thread outThread = new Thread(stdout, "nebula-core-stdout");
            Thread errThread = new Thread(stderr, "nebula-core-stderr");
            outThread.start();
            errThread.start();
            boolean finished = process.waitFor(TIMEOUT_MS, TimeUnit.MILLISECONDS);
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
