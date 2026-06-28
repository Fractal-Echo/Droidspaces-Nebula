#!/usr/bin/env node
const { readFileSync, readdirSync } = require('fs');
const { join, resolve } = require('path');

const repoRoot = resolve(__dirname, '..');
const schemaDir = join(repoRoot, 'docs', 'integration', 'schemas');
const fixtureDir = join(repoRoot, 'tests', 'fixtures', 'dock-lease');

const allowedCommandKinds = new Set([
  'dock_lease_status',
  'dock_lease_preflight',
  'dock_lease_receiver_smoke',
  'dock_lease_test_only',
  'dock_lease_stop_revoke',
]);

const expectedFixtureValues = {
  connector: 89,
  crtc: 285,
  plane: 133,
  lease_fd: 3,
  mode: '1920x1080@75',
};

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (err) {
    throw new Error(`${path}: ${err.message}`);
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEqual(actual, expected, message) {
  assert(actual === expected, `${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

function assertObject(value, message) {
  assert(value && typeof value === 'object' && !Array.isArray(value), message);
}

function validateSchemaDocs() {
  const commandSchema = readJson(join(schemaDir, 'dock-lease-command.schema.json'));
  const resultSchema = readJson(join(schemaDir, 'dock-lease-result.schema.json'));

  assertEqual(commandSchema.additionalProperties, false, 'command schema must reject extra top-level fields');
  assertEqual(resultSchema.additionalProperties, false, 'result schema must reject extra top-level fields');
  assert(commandSchema.required.includes('execute'), 'command schema must require execute');
  assert(commandSchema.required.includes('mutation_allowed_by_policy'), 'command schema must require mutation_allowed_by_policy');
  assert(commandSchema.required.includes('dynamic_discovery_required'), 'command schema must require dynamic discovery');
  assert(resultSchema.required.includes('dynamic_discovery'), 'result schema must require dynamic discovery result');
  assert(resultSchema.required.includes('stop_revoke'), 'result schema must require stop/revoke result');
  assert(resultSchema.required.includes('crash_gate'), 'result schema must require crash gate');
  assert(resultSchema.required.includes('rollback'), 'result schema must require rollback');
}

function validateCommand(path, command) {
  assertEqual(command.schema_version, 1, `${path} schema_version`);
  assertEqual(command.lane, 'dock_drm_lease_external', `${path} lane`);
  assert(allowedCommandKinds.has(command.command_kind), `${path} command_kind is not allowed: ${command.command_kind}`);
  assertEqual(command.execute, false, `${path} must be host-only execute=false`);
  assertEqual(command.mutation_allowed_by_policy, false, `${path} must deny mutation`);
  assertEqual(command.operator_approved, false, `${path} must not pretend operator approval`);
  assertEqual(command.safe_mode_required_clear, true, `${path} must require safe-mode clear`);
  assertEqual(command.external_display_only, true, `${path} must be external-display-only`);
  assertEqual(command.dynamic_discovery_required, true, `${path} must require dynamic discovery`);
  assertObject(command.inputs, `${path} inputs must be object`);

  for (const key of [
    'allow_raw_shell',
    'allow_manual_connector_id',
    'allow_manual_crtc_id',
    'allow_manual_plane_id',
    'allow_manual_fd',
    'allow_internal_panel',
    'allow_whole_card_takeover',
  ]) {
    assertEqual(command.inputs[key], false, `${path} ${key}`);
  }

  assert(!('connector' in command.inputs), `${path} must not accept connector replay input`);
  assert(!('crtc' in command.inputs), `${path} must not accept CRTC replay input`);
  assert(!('planes' in command.inputs), `${path} must not accept plane replay input`);
  assert(!('fd' in command.inputs), `${path} must not accept fd replay input`);

  if (command.command_kind === 'dock_lease_test_only' || command.command_kind === 'dock_lease_stop_revoke') {
    assertEqual(command.test_only, true, `${path} test-only/revoke fixture must preserve test_only=true`);
  }
}

function validateResult(path, result) {
  assertEqual(result.schema_version, 1, `${path} schema_version`);
  assertEqual(result.lane, 'dock_drm_lease_external', `${path} lane`);
  assert(allowedCommandKinds.has(result.command_kind), `${path} command_kind is not allowed: ${result.command_kind}`);
  assertEqual(result.executed, false, `${path} must be host-only executed=false`);
  assertEqual(result.mutation_performed, false, `${path} must not report mutation`);
  assertEqual(result.mutation_allowed_by_policy, false, `${path} must deny mutation`);

  assertObject(result.safe_mode, `${path} safe_mode`);
  assert(typeof result.safe_mode.checked === 'boolean', `${path} safe_mode.checked must be boolean`);

  assertObject(result.external_display_only, `${path} external_display_only`);
  assertEqual(result.external_display_only.required, true, `${path} external display must be required`);
  assertEqual(result.external_display_only.internal_panel_allowed, false, `${path} internal panel must remain blocked`);
  assertEqual(result.external_display_only.whole_card_takeover_allowed, false, `${path} whole-card takeover must remain blocked`);

  assertObject(result.dynamic_discovery, `${path} dynamic_discovery`);
  assertEqual(result.dynamic_discovery.required, true, `${path} dynamic discovery required`);
  assertEqual(result.dynamic_discovery.source, 'fixture', `${path} dynamic discovery source`);
  assertEqual(result.dynamic_discovery.hardcoded_forbidden, true, `${path} hardcoded_forbidden`);
  assertEqual(result.dynamic_discovery.connector, expectedFixtureValues.connector, `${path} fixture connector`);
  assertEqual(result.dynamic_discovery.crtc, expectedFixtureValues.crtc, `${path} fixture crtc`);
  assert(Array.isArray(result.dynamic_discovery.planes), `${path} planes must be an array`);
  assert(result.dynamic_discovery.planes.includes(expectedFixtureValues.plane), `${path} fixture plane must include ${expectedFixtureValues.plane}`);
  assertEqual(result.dynamic_discovery.lease_fd, expectedFixtureValues.lease_fd, `${path} fixture lease fd`);
  assertEqual(result.dynamic_discovery.mode, expectedFixtureValues.mode, `${path} fixture mode`);

  assertObject(result.receiver_smoke, `${path} receiver_smoke`);
  assertEqual(result.receiver_smoke.required_before_start, true, `${path} receiver smoke required`);
  assertObject(result.test_only, `${path} test_only`);
  assertEqual(result.test_only.required_before_commit, true, `${path} TEST_ONLY required`);
  assertObject(result.handoff, `${path} handoff`);
  assertEqual(result.handoff.mechanism, 'SCM_RIGHTS', `${path} handoff mechanism`);
  assertObject(result.stop_revoke, `${path} stop_revoke`);
  assertEqual(result.stop_revoke.required, true, `${path} stop/revoke required`);
  assertObject(result.crash_gate, `${path} crash_gate`);
  assertEqual(result.crash_gate.counter_required, true, `${path} crash counter required`);
  assertEqual(result.crash_gate.auto_retry_allowed, false, `${path} auto retry forbidden`);
  assertObject(result.rollback, `${path} rollback`);
  assertEqual(result.rollback.required, true, `${path} rollback required`);
  assert(Array.isArray(result.errors), `${path} errors must be array`);
  assert(result.errors.includes('HOST_ONLY_FIXTURE'), `${path} must self-identify as host-only fixture`);
}

function main() {
  validateSchemaDocs();
  const files = readdirSync(fixtureDir).filter(name => name.endsWith('.json')).sort();
  assert(files.length >= 8, 'expected dock lease command/result fixtures');

  let commandCount = 0;
  let resultCount = 0;
  for (const file of files) {
    const path = join(fixtureDir, file);
    const obj = readJson(path);
    if (file.endsWith('-command.json')) {
      commandCount += 1;
      validateCommand(path, obj);
    } else if (file.endsWith('-result.json')) {
      resultCount += 1;
      validateResult(path, obj);
    } else {
      throw new Error(`${path}: fixture must end in -command.json or -result.json`);
    }
  }

  assert(commandCount >= 4, 'expected at least four command fixtures');
  assert(resultCount >= 4, 'expected at least four result fixtures');
  console.log(`Dock lease host-only schema validation passed (${commandCount} commands, ${resultCount} results).`);
}

main();
