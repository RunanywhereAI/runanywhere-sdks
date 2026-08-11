const { execFileSync } = require('node:child_process');
const {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
} = require('node:fs');
const { join } = require('node:path');

const packageRoot = join(__dirname, '..');
const binariesRoot = join(packageRoot, 'ios', 'Binaries');
const resourcesRoot = join(packageRoot, 'ios', 'Resources');
const thirdPartyNoticesRoot = join(packageRoot, 'ios', 'ThirdPartyNotices');
const requiredSlices = {
  'ios-arm64': {
    platform: 'ios',
    supportedPlatform: 'iPhoneOS',
  },
  'ios-arm64-simulator': {
    platform: 'ios',
    variant: 'simulator',
    supportedPlatform: 'iPhoneSimulator',
  },
};
const lifecycleSymbols = [
  '_ra_mlx_register_runtime',
  '_ra_mlx_unregister_runtime',
  '_ra_mlx_runtime_is_registered',
  '_ra_mlx_runtime_is_available',
];
const metalAnchorSymbol = '_ra_mlx_metal_resource_anchor';
const deviceRuntimeUndefinedSymbols = [
  '_ra_mlx_set_clear_cancel_callback',
  '_rac_backend_mlx_register',
  '_rac_backend_mlx_unregister',
  '_rac_error_message',
  '_rac_mlx_set_callbacks',
];
const simulatorForbiddenUndefinedSymbols = [
  '_ra_mlx_set_clear_cancel_callback',
  '_rac_backend_mlx_register',
  '_rac_mlx_set_callbacks',
];
const generatedBundleNames = [
  'swift-crypto_Crypto.bundle',
  'swift-transformers_Hub.bundle',
];
const requiredRuntimeBundleLookups = ['swift-transformers_Hub.bundle'];
const hostPathMarkers = [
  Buffer.from('/Users/'),
  Buffer.from('/home/'),
  Buffer.from('/var/folders/'),
  Buffer.from('\\Users\\'),
  Buffer.from('/tmp/runanywhere-mlx-runtime-'),
  Buffer.from('/private/tmp/runanywhere-mlx-runtime-'),
];

function fail(message) {
  throw new Error(message);
}

function requireDirectory(path, label) {
  if (!existsSync(path) || !statSync(path).isDirectory()) {
    fail(`Missing required ${label}: ${path}`);
  }
}

function requireNonEmptyFile(path, label) {
  if (!existsSync(path) || !statSync(path).isFile() || statSync(path).size === 0) {
    fail(`Missing or empty ${label}: ${path}`);
  }
}

function run(command, args, label) {
  try {
    return execFileSync(command, args, {
      encoding: 'utf8',
      maxBuffer: 128 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  } catch (error) {
    const detail = error.stderr?.toString().trim() || error.message;
    fail(`${label} failed: ${detail}`);
  }
}

function xcrun(tool, args, label) {
  return run('xcrun', [tool, ...args], label);
}

function loadPlist(path, label) {
  requireNonEmptyFile(path, label);
  const json = run(
    '/usr/bin/plutil',
    ['-convert', 'json', '-o', '-', path],
    `Invalid ${label}`
  );
  try {
    return JSON.parse(json);
  } catch (error) {
    fail(`Invalid ${label}: ${error.message}`);
  }
}

function assertEqual(actual, expected, label) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    fail(
      `${label} must be ${JSON.stringify(expected)}, found ${JSON.stringify(actual)}`
    );
  }
}

function validateArm64Binary(path, label) {
  requireNonEmptyFile(path, label);
  const architectures = xcrun('lipo', ['-archs', path], `${label} architecture`)
    .split(/\s+/)
    .filter(Boolean);
  assertEqual(architectures, ['arm64'], `${label} architectures`);
}

function nmSymbols(path, flags, label) {
  return xcrun('nm', [...flags, path], label)
    .split('\n')
    .map((line) => line.trim().split(/\s+/).at(-1))
    .filter((symbol) => symbol?.startsWith('_'));
}

function markerCount(payload, marker) {
  const needle = Buffer.from(marker);
  let count = 0;
  let offset = 0;
  while ((offset = payload.indexOf(needle, offset)) !== -1) {
    count += 1;
    offset += needle.length;
  }
  return count;
}

function validateNoHostPaths(payload, label) {
  for (const marker of hostPathMarkers) {
    if (payload.includes(marker)) {
      fail(`${label} exposes an absolute host build path`);
    }
  }
}

function validateRootInfoPlist(name, libraryPath) {
  const artifact = join(binariesRoot, `${name}.xcframework`);
  requireDirectory(artifact, `${name} XCFramework`);
  const plist = loadPlist(
    join(artifact, 'Info.plist'),
    `${name} XCFramework Info.plist`
  );
  if (!Array.isArray(plist.AvailableLibraries)) {
    fail(`${name} XCFramework Info.plist is missing AvailableLibraries`);
  }

  const libraries = new Map();
  for (const library of plist.AvailableLibraries) {
    const identifier = library?.LibraryIdentifier;
    if (typeof identifier !== 'string' || libraries.has(identifier)) {
      fail(`${name} XCFramework has an invalid or duplicate library identifier`);
    }
    libraries.set(identifier, library);
  }

  for (const [identifier, expected] of Object.entries(requiredSlices)) {
    const library = libraries.get(identifier);
    if (!library) {
      fail(`${name} XCFramework is missing ${identifier}`);
    }
    assertEqual(
      library.SupportedArchitectures,
      ['arm64'],
      `${name} ${identifier} SupportedArchitectures`
    );
    assertEqual(
      library.SupportedPlatform,
      expected.platform,
      `${name} ${identifier} SupportedPlatform`
    );
    assertEqual(
      library.SupportedPlatformVariant,
      expected.variant,
      `${name} ${identifier} SupportedPlatformVariant`
    );
    assertEqual(
      library.LibraryPath,
      libraryPath,
      `${name} ${identifier} LibraryPath`
    );
  }
  return artifact;
}

function validateFrameworkInfoPlist(path, expected) {
  const plist = loadPlist(path, `${expected.name} framework Info.plist`);
  assertEqual(plist.CFBundlePackageType, 'FMWK', `${expected.name} package type`);
  assertEqual(
    plist.CFBundleExecutable,
    expected.name,
    `${expected.name} executable`
  );
  assertEqual(
    plist.CFBundleIdentifier,
    expected.identifier,
    `${expected.name} bundle identifier`
  );
  assertEqual(
    plist.CFBundleSupportedPlatforms,
    [expected.supportedPlatform],
    `${expected.name} supported platforms`
  );
  assertEqual(plist.MinimumOSVersion, '17.5', `${expected.name} minimum iOS`);
}

function validateStaticArchive(path, label) {
  validateArm64Binary(path, label);
  const payload = readFileSync(path);
  validateNoHostPaths(payload, label);
  const magic = payload.subarray(0, 8).toString('ascii');
  assertEqual(magic, '!<arch>\n', `${label} binary type`);
}

const backend = validateRootInfoPlist(
  'RABackendMLX',
  'librac_backend_mlx.a'
);
for (const slice of Object.keys(requiredSlices)) {
  validateStaticArchive(
    join(backend, slice, 'librac_backend_mlx.a'),
    `RABackendMLX ${slice}`
  );
}

const runtime = validateRootInfoPlist(
  'RunAnywhereMLXRuntime',
  'RunAnywhereMLXRuntime.framework'
);
for (const [slice, expected] of Object.entries(requiredSlices)) {
  const framework = join(runtime, slice, 'RunAnywhereMLXRuntime.framework');
  validateFrameworkInfoPlist(join(framework, 'Info.plist'), {
    name: 'RunAnywhereMLXRuntime',
    identifier: 'ai.runanywhere.mlx.runtime',
    supportedPlatform: expected.supportedPlatform,
  });
  const binary = join(framework, 'RunAnywhereMLXRuntime');
  validateStaticArchive(binary, `RunAnywhereMLXRuntime ${slice}`);

  const defined = nmSymbols(
    binary,
    ['-gU'],
    `RunAnywhereMLXRuntime ${slice} defined symbols`
  );
  for (const symbol of lifecycleSymbols) {
    const count = defined.filter((candidate) => candidate === symbol).length;
    assertEqual(count, 1, `RunAnywhereMLXRuntime ${slice} definition ${symbol}`);
  }
  if (defined.includes('_ra_mlx_metal_resource_anchor')) {
    fail(`RunAnywhereMLXRuntime ${slice} must not define the Metal anchor`);
  }
  const ownedCommonsSymbols = defined.filter((symbol) =>
    symbol.startsWith('_rac_')
  );
  assertEqual(
    ownedCommonsSymbols,
    [],
    `RunAnywhereMLXRuntime ${slice} Commons symbol ownership`
  );

  const undefinedSymbols = nmSymbols(
    binary,
    ['-gu'],
    `RunAnywhereMLXRuntime ${slice} undefined symbols`
  );
  const requiredUndefined =
    slice === 'ios-arm64'
      ? [metalAnchorSymbol, ...deviceRuntimeUndefinedSymbols]
      : [metalAnchorSymbol];
  for (const symbol of requiredUndefined) {
    if (!undefinedSymbols.includes(symbol)) {
      fail(`RunAnywhereMLXRuntime ${slice} must leave ${symbol} undefined`);
    }
  }
  if (slice === 'ios-arm64-simulator') {
    const phantomShellSymbols = simulatorForbiddenUndefinedSymbols.filter(
      (symbol) => undefinedSymbols.includes(symbol)
    );
    assertEqual(
      phantomShellSymbols,
      [],
      `RunAnywhereMLXRuntime ${slice} unsupported shell references`
    );
  }

  const payload = readFileSync(binary);
  assertEqual(
    markerCount(payload, 'ai.runanywhere.mlx.metal'),
    1,
    `RunAnywhereMLXRuntime ${slice} Metal bundle-ID lookup count`
  );
  for (const name of requiredRuntimeBundleLookups) {
    if (markerCount(payload, name) === 0) {
      fail(`RunAnywhereMLXRuntime ${slice} is missing Bundle.module lookup ${name}`);
    }
  }
  for (const obsolete of [
    'RunAnywhereMLXMetalDevice',
    'RunAnywhereMLXMetalSimulator',
  ]) {
    if (markerCount(payload, obsolete) !== 0) {
      fail(`RunAnywhereMLXRuntime ${slice} contains obsolete lookup ${obsolete}`);
    }
  }
}

const metal = validateRootInfoPlist(
  'RunAnywhereMLXMetal',
  'RunAnywhereMLXMetal.framework'
);
for (const [slice, expected] of Object.entries(requiredSlices)) {
  const framework = join(metal, slice, 'RunAnywhereMLXMetal.framework');
  validateFrameworkInfoPlist(join(framework, 'Info.plist'), {
    name: 'RunAnywhereMLXMetal',
    identifier: 'ai.runanywhere.mlx.metal',
    supportedPlatform: expected.supportedPlatform,
  });
  const binary = join(framework, 'RunAnywhereMLXMetal');
  validateArm64Binary(binary, `RunAnywhereMLXMetal ${slice}`);
  validateNoHostPaths(
    readFileSync(binary),
    `RunAnywhereMLXMetal ${slice}`
  );
  const header = xcrun(
    'otool',
    ['-hv', binary],
    `RunAnywhereMLXMetal ${slice} Mach-O header`
  );
  if (!/\bDYLIB\b/.test(header)) {
    fail(`RunAnywhereMLXMetal ${slice} must be a dynamic framework binary`);
  }
  const loadCommands = xcrun(
    'otool',
    ['-l', binary],
    `RunAnywhereMLXMetal ${slice} load commands`
  );
  assertEqual(
    [...loadCommands.matchAll(/^\s*cmd LC_UUID\s*$/gm)].length,
    1,
    `RunAnywhereMLXMetal ${slice} LC_UUID command count`
  );
  const installNames = xcrun(
    'otool',
    ['-D', binary],
    `RunAnywhereMLXMetal ${slice} install name`
  )
    .split('\n')
    .slice(1)
    .map((line) => line.trim())
    .filter(Boolean);
  assertEqual(
    installNames,
    ['@rpath/RunAnywhereMLXMetal.framework/RunAnywhereMLXMetal'],
    `RunAnywhereMLXMetal ${slice} install names`
  );
  const defined = nmSymbols(
    binary,
    ['-gU'],
    `RunAnywhereMLXMetal ${slice} defined symbols`
  );
  assertEqual(
    defined.filter((symbol) => symbol === '_ra_mlx_metal_resource_anchor')
      .length,
    1,
    `RunAnywhereMLXMetal ${slice} anchor definition count`
  );
  const forbidden = defined.filter(
    (symbol) =>
      symbol.startsWith('_rac_') || lifecycleSymbols.includes(symbol)
  );
  assertEqual(forbidden, [], `RunAnywhereMLXMetal ${slice} forbidden exports`);

  const metallib = join(framework, 'default.metallib');
  requireNonEmptyFile(metallib, `RunAnywhereMLXMetal ${slice} default.metallib`);
  xcrun(
    'metallib',
    ['--app-store-validate', metallib],
    `RunAnywhereMLXMetal ${slice} default.metallib validation`
  );
}

requireDirectory(resourcesRoot, 'MLX runtime resources directory');
const actualBundles = readdirSync(resourcesRoot, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && entry.name.endsWith('.bundle'))
  .map((entry) => entry.name)
  .sort();
assertEqual(
  actualBundles,
  [...generatedBundleNames].sort(),
  'RunAnywhereMLX app-root resource bundles'
);
const requiredResources = [
  ['swift-transformers_Hub.bundle', 'gpt2_tokenizer_config.json'],
  ['swift-transformers_Hub.bundle', 't5_tokenizer_config.json'],
  ['swift-crypto_Crypto.bundle', 'PrivacyInfo.xcprivacy'],
];
for (const resource of requiredResources) {
  requireNonEmptyFile(
    join(resourcesRoot, ...resource),
    `MLX runtime resource ${resource.join('/')}`
  );
}
requireDirectory(thirdPartyNoticesRoot, 'MLX runtime third-party notices');
const noticeFiles = readdirSync(thirdPartyNoticesRoot, { withFileTypes: true })
  .filter((entry) => entry.isFile())
  .map((entry) => entry.name);
if (noticeFiles.length === 0) {
  fail('MLX runtime third-party notices must contain at least one file');
}
for (const notice of noticeFiles) {
  requireNonEmptyFile(
    join(thirdPartyNoticesRoot, notice),
    `MLX runtime third-party notice ${notice}`
  );
}

const podspecPath = join(packageRoot, 'RunAnywhereMLX.podspec');
requireNonEmptyFile(podspecPath, 'RunAnywhereMLX podspec');
const podspec = readFileSync(podspecPath, 'utf8');
const requiredPodspecMarkers = [
  'RABackendMLX.xcframework',
  'RunAnywhereMLXRuntime.xcframework',
  'RunAnywhereMLXMetal.xcframework',
  'ios/Resources/swift-crypto_Crypto.bundle',
  'ios/Resources/swift-transformers_Hub.bundle',
  's.homepage      = "https://runanywhere.ai"',
  's.license       = { type: "RunAnywhere License", file: "LICENSE" }',
  's.swift_version = "6.2"',
  '"Accelerate", "AVFoundation", "CoreGraphics", "CoreImage", "CoreML"',
  '"Foundation", "Metal", "MetalKit", "NaturalLanguage", "UIKit"',
  's.libraries = "c++"',
  's.user_target_xcconfig',
  '-Wl,-u,_ra_mlx_runtime_is_available',
];
for (const marker of requiredPodspecMarkers) {
  if (!podspec.includes(marker)) {
    fail(`RunAnywhereMLX podspec is missing required wiring: ${marker}`);
  }
}
for (const forbidden of [
  'ios/Resources/*.bundle',
  'RunAnywhereMLXMetalDevice.bundle',
  'RunAnywhereMLXMetalSimulator.bundle',
  '-all_load',
  '-force_load',
]) {
  if (podspec.includes(forbidden)) {
    fail(`RunAnywhereMLX podspec contains forbidden broad or obsolete wiring: ${forbidden}`);
  }
}

const manifestPath = join(packageRoot, 'package.json');
requireNonEmptyFile(manifestPath, 'RunAnywhereMLX package manifest');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
assertEqual(
  manifest.license,
  'SEE LICENSE IN LICENSE',
  'RunAnywhereMLX npm license metadata'
);
if (!Array.isArray(manifest.files) || !manifest.files.includes('LICENSE')) {
  fail('RunAnywhereMLX package manifest must include LICENSE in published files');
}
const packageLicensePath = join(packageRoot, 'LICENSE');
const repositoryLicensePath = join(packageRoot, '..', '..', '..', '..', 'LICENSE');
requireNonEmptyFile(packageLicensePath, 'RunAnywhereMLX package license');
requireNonEmptyFile(repositoryLicensePath, 'repository license');
if (!readFileSync(packageLicensePath).equals(readFileSync(repositoryLicensePath))) {
  fail('RunAnywhereMLX package license must exactly match the repository license');
}
