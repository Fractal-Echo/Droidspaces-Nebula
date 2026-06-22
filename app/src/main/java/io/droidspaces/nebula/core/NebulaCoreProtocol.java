package io.droidspaces.nebula.core;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

public final class NebulaCoreProtocol {
    public static final int NEBULA_CORE_PROTOCOL_VERSION = 1;
    public static final String BLOCKED_NOT_READY = "BLOCKED_NOT_READY";

    private NebulaCoreProtocol() {
    }

    public static NebulaCoreStatus parseStatus(String json) {
        try {
            JSONObject object = new JSONObject(json == null ? "" : json);
            int protocol = object.optInt("protocol_version", -1);
            String version = object.optString("module_version", "unknown");
            String profile = object.optString("profile", "safe");
            boolean safeMode = object.optBoolean("safe_mode", true);
            boolean daemonRunning = object.optBoolean("daemon_running", false);
            String serviceStatus = object.optString("service_status", "unknown");
            String gitCommit = object.optString("git_commit", "unknown");
            String error = object.optString("error", null);
            if (error != null && error.isEmpty()) {
                error = null;
            }
            return new NebulaCoreStatus(true, version, protocol, safeMode,
                    NebulaProfile.fromWireName(profile), daemonRunning, serviceStatus,
                    gitCommit, error);
        } catch (JSONException error) {
            return NebulaCoreStatus.absent("Invalid module JSON: " + error.getMessage());
        }
    }

    public static List<NebulaCapability> parseCapabilities(String json) {
        List<NebulaCapability> capabilities = new ArrayList<>();
        try {
            JSONObject object = new JSONObject(json == null ? "" : json);
            JSONArray array = object.optJSONArray("capabilities");
            if (array == null) {
                return capabilities;
            }
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.optJSONObject(i);
                if (item == null) {
                    continue;
                }
                capabilities.add(new NebulaCapability(
                        item.optString("id", "unknown"),
                        item.optString("title", "Unknown"),
                        item.optString("status", "unknown"),
                        item.optString("detail", ""),
                        item.optBoolean("mutating", false),
                        item.optString("source", "nebula-core")));
            }
        } catch (JSONException ignored) {
            capabilities.clear();
        }
        return capabilities;
    }

    public static RedMagicProbe parseRedMagicProbe(String json) {
        return RedMagicProbe.fromJson(json);
    }

    public static boolean isAllowedProfile(NebulaProfile profile) {
        return profile == NebulaProfile.SAFE || profile == NebulaProfile.PHONE
                || profile == NebulaProfile.DOCK || profile == NebulaProfile.COMPATIBILITY;
    }

    public static int sanitizeTailLines(int lines) {
        if (lines < 1) {
            return 1;
        }
        if (lines > 500) {
            return 500;
        }
        return lines;
    }
}
