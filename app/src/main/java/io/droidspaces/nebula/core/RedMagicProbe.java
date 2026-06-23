package io.droidspaces.nebula.core;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public final class RedMagicProbe {
    public final boolean available;
    public final boolean pumpSupported;
    public final boolean pumpPresent;
    public final Boolean fanEnabled;
    public final Integer fanRpm;
    public final Integer fanLevel;
    public final Boolean pumpEnabled;
    public final Integer pumpSpeed;
    public final Double maxThermalC;
    public final int thermalReadingCount;
    public final String deviceSummary;
    public final String fanSummary;
    public final String pumpSummary;
    public final String performanceSummary;
    public final String displaySummary;
    public final String thermalSummary;
    public final CoolingPolicy coolingPolicy;
    public final String error;

    private RedMagicProbe(boolean available, boolean pumpSupported, boolean pumpPresent,
            Boolean fanEnabled, Integer fanRpm, Integer fanLevel, Boolean pumpEnabled,
            Integer pumpSpeed, Double maxThermalC, int thermalReadingCount,
            String deviceSummary, String fanSummary, String pumpSummary,
            String performanceSummary, String displaySummary, String thermalSummary,
            CoolingPolicy coolingPolicy, String error) {
        this.available = available;
        this.pumpSupported = pumpSupported;
        this.pumpPresent = pumpPresent;
        this.fanEnabled = fanEnabled;
        this.fanRpm = fanRpm;
        this.fanLevel = fanLevel;
        this.pumpEnabled = pumpEnabled;
        this.pumpSpeed = pumpSpeed;
        this.maxThermalC = maxThermalC;
        this.thermalReadingCount = thermalReadingCount;
        this.deviceSummary = deviceSummary;
        this.fanSummary = fanSummary;
        this.pumpSummary = pumpSummary;
        this.performanceSummary = performanceSummary;
        this.displaySummary = displaySummary;
        this.thermalSummary = thermalSummary;
        this.coolingPolicy = coolingPolicy;
        this.error = error;
    }

    public static RedMagicProbe unavailable(String reason) {
        return new RedMagicProbe(false, false, false, null, null, null, null,
                null, null, 0, "unavailable", "unavailable", "unavailable",
                "unavailable", "unavailable", "unavailable",
                CoolingPolicy.unavailable(reason), reason);
    }

    public static RedMagicProbe fromJson(String json) {
        try {
            JSONObject root = new JSONObject(json == null ? "" : json);
            JSONObject device = root.optJSONObject("device");
            JSONObject fan = root.optJSONObject("fan");
            JSONObject pump = root.optJSONObject("pump");
            JSONObject performance = root.optJSONObject("performance");
            JSONObject display = root.optJSONObject("display");
            JSONObject thermal = root.optJSONObject("thermal");
            JSONObject coolingPolicy = root.optJSONObject("cooling_policy");

            String deviceSummary = "model=" + opt(device, "model")
                    + " product=" + opt(device, "product")
                    + " board=" + opt(device, "board_platform");
            String fanSummary = boolText(fan, "supported") + ", present="
                    + boolValue(fan, "present") + ", rpm=" + nullable(fan, "rpm")
                    + ", level=" + nullable(fan, "level") + errors(fan);
            String pumpSummary = pumpSummary(pump);
            String performanceSummary = boolText(performance, "supported")
                    + ", mode=" + nullable(performance, "mode") + errors(performance);
            String displaySummary = boolText(display, "supported")
                    + ", refresh=" + nullable(display, "refresh_rate_hz") + errors(display);
            String thermalSummary = thermalSummary(thermal);
            Double maxThermalC = maxThermalC(thermal);
            int thermalReadingCount = thermalReadingCount(thermal);
            CoolingPolicy parsedCoolingPolicy = CoolingPolicy.fromJson(coolingPolicy);

            return new RedMagicProbe(true, pump != null && pump.optBoolean("supported", false),
                    pump != null && pump.optBoolean("present", false),
                    optBooleanOrNull(fan, "enabled"), optIntegerOrNull(fan, "rpm"),
                    optIntegerOrNull(fan, "level"), optBooleanOrNull(pump, "enabled"),
                    optIntegerOrNull(pump, "speed"), maxThermalC, thermalReadingCount,
                    deviceSummary, fanSummary, pumpSummary, performanceSummary,
                    displaySummary, thermalSummary, parsedCoolingPolicy, null);
        } catch (JSONException error) {
            return unavailable("Invalid RedMagic probe JSON: " + error.getMessage());
        }
    }

    private static String opt(JSONObject object, String key) {
        if (object == null) return "unknown";
        String value = object.optString(key, "unknown");
        return value.isEmpty() ? "unknown" : value;
    }

    private static String boolText(JSONObject object, String key) {
        return key + "=" + boolValue(object, key);
    }

    private static String boolValue(JSONObject object, String key) {
        if (object == null || !object.has(key)) return "unknown";
        return object.optBoolean(key, false) ? "true" : "false";
    }

    private static String nullable(JSONObject object, String key) {
        if (object == null || object.isNull(key)) return "unavailable";
        Object value = object.opt(key);
        return value == null ? "unavailable" : String.valueOf(value);
    }

    private static Boolean optBooleanOrNull(JSONObject object, String key) {
        if (object == null || object.isNull(key) || !object.has(key)) return null;
        return object.optBoolean(key, false);
    }

    private static Integer optIntegerOrNull(JSONObject object, String key) {
        if (object == null || object.isNull(key) || !object.has(key)) return null;
        Object value = object.opt(key);
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static Double optDoubleOrNull(JSONObject object, String key) {
        if (object == null || object.isNull(key) || !object.has(key)) return null;
        Object value = object.opt(key);
        if (value instanceof Number) {
            return ((Number) value).doubleValue();
        }
        try {
            return Double.valueOf(String.valueOf(value));
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static String errors(JSONObject object) {
        if (object == null) return "";
        JSONArray errors = object.optJSONArray("errors");
        if (errors == null || errors.length() == 0) return "";
        return ", errors=" + errors.length();
    }

    private static String thermalSummary(JSONObject thermal) {
        if (thermal == null) return "supported=unknown";
        JSONArray readings = thermal.optJSONArray("readings");
        int count = thermalReadingCount(thermal);
        StringBuilder builder = new StringBuilder();
        builder.append("supported=").append(thermal.optBoolean("supported", false));
        builder.append(", readings=").append(count);
        if (count > 0) {
            JSONObject first = readings.optJSONObject(0);
            if (first != null) {
                builder.append(", first=").append(first.optString("temp_c", "unavailable")).append("C");
            }
        }
        builder.append(errors(thermal));
        return builder.toString();
    }

    private static int thermalReadingCount(JSONObject thermal) {
        if (thermal == null) return 0;
        JSONArray readings = thermal.optJSONArray("readings");
        return readings == null ? 0 : readings.length();
    }

    private static Double maxThermalC(JSONObject thermal) {
        if (thermal == null) return null;
        JSONArray readings = thermal.optJSONArray("readings");
        if (readings == null || readings.length() == 0) return null;
        Double max = null;
        for (int i = 0; i < readings.length(); i++) {
            JSONObject item = readings.optJSONObject(i);
            if (item == null || item.isNull("temp_c")) continue;
            double value = item.optDouble("temp_c", Double.NaN);
            if (Double.isNaN(value)) continue;
            max = max == null ? value : Math.max(max, value);
        }
        return max;
    }

    private static String pumpSummary(JSONObject pump) {
        if (pump == null) return "supported=unknown";
        JSONArray sources = pump.optJSONArray("sources");
        int sourceCount = sources == null ? 0 : sources.length();
        StringBuilder builder = new StringBuilder();
        builder.append("supported=").append(boolValue(pump, "supported"));
        builder.append(", present=").append(boolValue(pump, "present"));
        builder.append(", enabled=").append(nullable(pump, "enabled"));
        builder.append(", rpm=").append(nullable(pump, "rpm"));
        builder.append(", speed=").append(nullable(pump, "speed"));
        builder.append(", level=").append(nullable(pump, "level"));
        builder.append(", flow=").append(nullable(pump, "flow_rate"));
        builder.append(", confidence=").append(opt(pump, "confidence"));
        builder.append(", sources=").append(sourceCount);
        builder.append(errors(pump));
        return builder.toString();
    }

    private static String joinedArray(JSONObject object, String key) {
        if (object == null) return "";
        JSONArray array = object.optJSONArray(key);
        if (array == null || array.length() == 0) return "";
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < array.length(); i++) {
            if (i > 0) builder.append("; ");
            builder.append(array.optString(i, "unknown"));
        }
        return builder.toString();
    }

    public static final class CoolingPolicy {
        public final boolean available;
        public final boolean previewOnly;
        public final boolean configured;
        public final boolean safeMode;
        public final String state;
        public final String controllingSensorName;
        public final String controllingSensorSource;
        public final Double controllingTemperatureC;
        public final Double maximumTemperatureC;
        public final int validSensorCount;
        public final int rejectedSensorCount;
        public final String fanIntent;
        public final boolean fanApplied;
        public final String pumpIntent;
        public final boolean pumpApplied;
        public final Integer pumpFreq;
        public final String thresholdSource;
        public final Double hysteresisC;
        public final int minimumDwellSeconds;
        public final String reasonSummary;
        public final String errorSummary;

        private CoolingPolicy(boolean available, boolean previewOnly, boolean configured,
                boolean safeMode, String state, String controllingSensorName,
                String controllingSensorSource, Double controllingTemperatureC,
                Double maximumTemperatureC, int validSensorCount, int rejectedSensorCount,
                String fanIntent, boolean fanApplied, String pumpIntent, boolean pumpApplied,
                Integer pumpFreq, String thresholdSource, Double hysteresisC,
                int minimumDwellSeconds, String reasonSummary, String errorSummary) {
            this.available = available;
            this.previewOnly = previewOnly;
            this.configured = configured;
            this.safeMode = safeMode;
            this.state = state;
            this.controllingSensorName = controllingSensorName;
            this.controllingSensorSource = controllingSensorSource;
            this.controllingTemperatureC = controllingTemperatureC;
            this.maximumTemperatureC = maximumTemperatureC;
            this.validSensorCount = validSensorCount;
            this.rejectedSensorCount = rejectedSensorCount;
            this.fanIntent = fanIntent;
            this.fanApplied = fanApplied;
            this.pumpIntent = pumpIntent;
            this.pumpApplied = pumpApplied;
            this.pumpFreq = pumpFreq;
            this.thresholdSource = thresholdSource;
            this.hysteresisC = hysteresisC;
            this.minimumDwellSeconds = minimumDwellSeconds;
            this.reasonSummary = reasonSummary;
            this.errorSummary = errorSummary;
        }

        static CoolingPolicy unavailable(String reason) {
            return new CoolingPolicy(false, true, false, false, "UNAVAILABLE",
                    null, null, null, null, 0, 0, "unavailable", false,
                    "unavailable", false, null, "unavailable", null, 0,
                    reason == null ? "unavailable" : reason, "");
        }

        static CoolingPolicy fromJson(JSONObject object) {
            if (object == null) {
                return unavailable("missing cooling_policy");
            }
            JSONObject sensor = object.optJSONObject("controlling_sensor");
            JSONObject thermal = object.optJSONObject("thermal");
            JSONObject fan = object.optJSONObject("fan");
            JSONObject pump = object.optJSONObject("pump");
            JSONObject pumpCurrent = pump == null ? null : pump.optJSONObject("current");
            JSONObject policy = object.optJSONObject("policy");
            String reason = joinedArray(object, "reason");
            String errors = joinedArray(object, "errors");
            return new CoolingPolicy(true,
                    object.optBoolean("preview_only", true),
                    object.optBoolean("configured", false),
                    object.optBoolean("safe_mode", false),
                    object.optString("state", "UNAVAILABLE"),
                    opt(sensor, "name"),
                    opt(sensor, "source"),
                    optDoubleOrNull(sensor, "temperature_c"),
                    optDoubleOrNull(thermal, "maximum_c"),
                    thermal == null ? 0 : thermal.optInt("valid_sensor_count", 0),
                    thermal == null ? 0 : thermal.optInt("rejected_sensor_count", 0),
                    fan == null ? "unavailable" : fan.optString("intent", "unavailable"),
                    fan != null && fan.optBoolean("applied", false),
                    pump == null ? "unavailable" : pump.optString("intent", "unavailable"),
                    pump != null && pump.optBoolean("applied", false),
                    optIntegerOrNull(pumpCurrent, "freq"),
                    policy == null ? "unavailable" : policy.optString("threshold_source", "unavailable"),
                    optDoubleOrNull(policy, "hysteresis_c"),
                    policy == null ? 0 : policy.optInt("minimum_dwell_seconds", 0),
                    reason.isEmpty() ? "none" : reason,
                    errors);
        }
    }
}
