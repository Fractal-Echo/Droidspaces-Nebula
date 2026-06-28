#!/usr/bin/env node
const { execFileSync } = require('child_process');
const { mkdirSync, readFileSync, readdirSync, writeFileSync } = require('fs');
const { basename, join, relative, resolve } = require('path');

const repoRoot = resolve(__dirname, '..');
const fixtureDir = join(repoRoot, 'tests', 'fixtures', 'dock-lease');
const defaultOutDir = join(repoRoot, 'build', 'dock-lease-command-plan');

function parseArgs(argv) {
  const options = {
    outDir: defaultOutDir,
    json: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--out') {
      options.outDir = resolve(argv[index + 1]);
      index += 1;
    } else if (arg === '--json') {
      options.json = true;
    } else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }
  return options;
}

function printHelp() {
  console.log(`Usage:
  node scripts/dock-lease-command-plan-report.js --json
  node scripts/dock-lease-command-plan-report.js [--out <dir>]

Builds a host-only Dock Lease command-plan report from tracked schema fixtures.
The report is advisory and does not run ADB, stage modules, mutate DRM, or launch
compositors.`);
}

function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

function fixtureFiles(suffix) {
  return readdirSync(fixtureDir)
    .filter(name => name.endsWith(suffix))
    .sort()
    .map(name => join(fixtureDir, name));
}

function pairFixtures() {
  const results = new Map();
  for (const resultPath of fixtureFiles('-result.json')) {
    const key = basename(resultPath).replace(/-result\.json$/, '');
    results.set(key, resultPath);
  }

  return fixtureFiles('-command.json').map(commandPath => {
    const key = basename(commandPath).replace(/-command\.json$/, '');
    const resultPath = results.get(key);
    if (!resultPath) {
      throw new Error(`Missing result fixture for ${commandPath}`);
    }
    return {
      key,
      commandPath,
      resultPath,
      command: readJson(commandPath),
      result: readJson(resultPath),
    };
  });
}

function stageStatus(pair) {
  if (pair.result.stop_revoke?.passed) {
    return 'rollback_shape_proven_host_only';
  }
  if (pair.result.test_only?.passed) {
    return 'test_only_shape_proven_host_only';
  }
  if (pair.result.receiver_smoke?.passed) {
    return 'receiver_smoke_shape_proven_host_only';
  }
  return 'preflight_shape_proven_host_only';
}

function buildReport() {
  execFileSync(process.execPath, [join(repoRoot, 'scripts', 'validate-dock-lease-schema.js')], {
    cwd: repoRoot,
    stdio: 'pipe',
  });

  const pairs = pairFixtures();
  const plans = pairs.map(pair => ({
    id: pair.key,
    command_kind: pair.command.command_kind,
    command_fixture: relative(repoRoot, pair.commandPath),
    result_fixture: relative(repoRoot, pair.resultPath),
    execute: pair.command.execute,
    mutation_allowed_by_policy: pair.command.mutation_allowed_by_policy,
    operator_approved: pair.command.operator_approved,
    external_display_only: pair.command.external_display_only,
    dynamic_discovery_required: pair.command.dynamic_discovery_required,
    test_only: pair.command.test_only,
    inputs: pair.command.inputs,
    status: stageStatus(pair),
    observed_fixture_values: {
      connector: pair.result.dynamic_discovery.connector,
      crtc: pair.result.dynamic_discovery.crtc,
      planes: pair.result.dynamic_discovery.planes,
      lease_fd: pair.result.dynamic_discovery.lease_fd,
      mode: pair.result.dynamic_discovery.mode,
      hardcoded_forbidden: pair.result.dynamic_discovery.hardcoded_forbidden,
    },
    required_guards: {
      receiver_smoke_required_before_start: pair.result.receiver_smoke.required_before_start,
      test_only_required_before_commit: pair.result.test_only.required_before_commit,
      handoff_mechanism: pair.result.handoff.mechanism,
      stop_revoke_required: pair.result.stop_revoke.required,
      rollback_required: pair.result.rollback.required,
      crash_counter_required: pair.result.crash_gate.counter_required,
      auto_retry_allowed: pair.result.crash_gate.auto_retry_allowed,
    },
    result_errors: pair.result.errors,
    host_only_errors: pair.result.errors,
  }));

  return {
    protocol_version: 1,
    command: 'dock lease command-plan report',
    host_only: true,
    lane: 'dock_drm_lease_external',
    profile_set_dock: 'BLOCKED_NOT_READY',
    start_command_available: false,
    runtime_allowlists_modified: false,
    app_allowlists_modified: false,
    source: 'tests/fixtures/dock-lease',
    classification: 'DOCK_LEASE_COMMAND_PLAN_HOST_ONLY',
    schema_version: 1,
    runtime_commands_added: false,
    apk_allowlist_changed: false,
    module_command_added: false,
    mutation_allowed_by_policy: false,
    profile_set_dock_expected_error: 'BLOCKED_NOT_READY',
    safety_locks: [
      'NO_ADB',
      'NO_FASTBOOT',
      'NO_APK_INSTALL',
      'NO_MODULE_STAGE',
      'NO_REBOOT',
      'NO_DRM_MUTATION',
      'NO_CREATE_LEASE',
      'NO_COMPOSITOR_LAUNCH',
      'NO_RUNTIME_LAUNCH',
      'NO_TDP_WRITE',
    ],
    plans,
    steps: plans,
    next_gate: 'host_only_command_plan_review_before_runtime_allowlist',
  };
}

function markdown(report) {
  const lines = [
    '# Dock Lease Command Plan',
    '',
    `Classification: \`${report.classification}\``,
    '',
    'This report is generated from host-only fixtures. It does not add or run a',
    'Nebula Core command, APK allowlist command, DRM mutation, or compositor',
    'launch path.',
    '',
    '## Safety Locks',
    '',
    ...report.safety_locks.map(item => `- ${item}`),
    '',
    '## Steps',
    '',
    '| Step | Command kind | Status | Execute | Mutation allowed | Test only |',
    '| --- | --- | --- | --- | --- | --- |',
    ...report.plans.map(step => `| ${step.id} | ${step.command_kind} | ${step.status} | ${step.execute} | ${step.mutation_allowed_by_policy} | ${step.test_only} |`),
    '',
    '## Runtime Boundary',
    '',
    `- runtime commands added: \`${report.runtime_commands_added}\``,
    `- APK allowlist changed: \`${report.apk_allowlist_changed}\``,
    `- module command added: \`${report.module_command_added}\``,
    `- expected blocked Dock profile result: \`${report.profile_set_dock_expected_error}\``,
    '',
  ];
  return `${lines.join('\n')}\n`;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const report = buildReport();
  if (options.json) {
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    return;
  }
  mkdirSync(options.outDir, { recursive: true });
  writeFileSync(join(options.outDir, 'dock-lease-command-plan.json'), `${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(join(options.outDir, 'dock-lease-command-plan.md'), markdown(report));
  console.log(`Dock lease command plan written to ${options.outDir}`);
}

main();
