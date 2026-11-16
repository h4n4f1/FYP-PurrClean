import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const apkPath = path.join(
  projectRoot,
  'build',
  'app',
  'outputs',
  'flutter-apk',
  'app-debug.apk',
);
const appiumUrl = 'http://127.0.0.1:4723';
const emulatorBuildDefine = 'PURRCLEAN_USE_FIREBASE_EMULATORS=true';
const pollIntervalMs = 250;
const validationTimeoutMs = 10000;

function verifyEmulatorBuild() {
  if (
    process.env.PURRCLEAN_EMULATOR_BUILD_CONFIRMED !== 'true' ||
    process.env.PURRCLEAN_EMULATOR_DART_DEFINE !== emulatorBuildDefine
  ) {
    throw new Error(
      `Emulator build is not confirmed. Build with --dart-define=${emulatorBuildDefine}, then set the verification variables in the same shell before running this test.`,
    );
  }

  if (!existsSync(apkPath)) {
    throw new Error(`Debug APK not found: ${apkPath}`);
  }

  const expectedHash = process.env.PURRCLEAN_EMULATOR_APK_SHA256
    ?.trim()
    .toLowerCase();
  if (!expectedHash || !/^[a-f0-9]{64}$/.test(expectedHash)) {
    throw new Error(
      'A SHA-256 hash for the emulator-built APK is required; refusing to start Appium.',
    );
  }

  const actualHash = createHash('sha256')
    .update(readFileSync(apkPath))
    .digest('hex');
  if (actualHash !== expectedHash) {
    throw new Error(
      'The APK hash does not match the APK built with the emulator flag; refusing to start Appium.',
    );
  }
}

async function request(pathname, options) {
  const response = await fetch(`${appiumUrl}${pathname}`, options);
  const responseText = await response.text();
  if (!response.ok) {
    throw new Error(`Appium returned HTTP ${response.status}: ${responseText}`);
  }
  return responseText ? JSON.parse(responseText) : null;
}

async function findElements(sessionId, using, value) {
  const result = await request(`/session/${sessionId}/elements`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ using, value }),
  });
  return result.value;
}

function elementId(element) {
  const id =
    element['element-6066-11e4-a52e-4f735466cecf'] ?? element.ELEMENT;
  assert.ok(id, 'Appium returned an element without an ID.');
  return id;
}

async function getAttribute(sessionId, id, name) {
  const result = await request(
    `/session/${sessionId}/element/${encodeURIComponent(id)}/attribute/${name}`,
  );
  return result.value;
}

function assertSignedOutLoginScreen(source) {
  assert.match(source, /\bLogin\b/i, 'Login screen is not visible.');
  assert.match(source, /\bRegister\b/i, 'Signed-out controls are not visible.');
  assert.match(source, /Sign In/i, 'Sign In control is not visible.');
  assert.doesNotMatch(
    source,
    /\bLog out\b|\bAnalytics\b|\bToday's Visits\b/i,
    'An authenticated screen appears to be visible.',
  );
}

async function locateSignInButton(sessionId) {
  const byAccessibilityId = await findElements(
    sessionId,
    'accessibility id',
    'Sign In',
  );
  if (byAccessibilityId.length === 1) return byAccessibilityId[0];
  if (byAccessibilityId.length > 1) {
    throw new Error('Sign In accessibility ID matched more than one element.');
  }

  const byHierarchyText = await findElements(
    sessionId,
    'xpath',
    '//*[@text="Sign In" or @content-desc="Sign In"]',
  );
  if (byHierarchyText.length !== 1) {
    throw new Error(
      `Sign In was not uniquely locatable in the accessibility hierarchy (matches: ${byHierarchyText.length}).`,
    );
  }
  return byHierarchyText[0];
}

async function waitForValidationMessages(sessionId) {
  const deadline = Date.now() + validationTimeoutMs;
  let latestSource = '';

  while (Date.now() < deadline) {
    const result = await request(`/session/${sessionId}/source`);
    latestSource = result.value;
    if (
      latestSource.includes('Enter a valid email') &&
      latestSource.includes('Min 6 characters')
    ) {
      return latestSource;
    }
    await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
  }

  const missing = [
    'Enter a valid email',
    'Min 6 characters',
  ].filter((message) => !latestSource.includes(message));
  throw new Error(
    `Timed out waiting for validation message(s): ${missing.join(', ')}.`,
  );
}

let sessionId;
let testPassed = false;

try {
  verifyEmulatorBuild();

  const created = await request('/session', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      capabilities: {
        alwaysMatch: {
          platformName: 'Android',
          'appium:automationName': 'UiAutomator2',
          'appium:deviceName': 'emulator-5554',
          'appium:udid': 'emulator-5554',
          'appium:app': apkPath,
          'appium:autoGrantPermissions': true,
          'appium:noReset': true,
          'appium:newCommandTimeout': 120,
        },
      },
    }),
  });
  sessionId = created.value?.sessionId;
  assert.ok(sessionId, 'Appium did not return a session ID.');

  let source = (await request(`/session/${sessionId}/source`)).value;
  assertSignedOutLoginScreen(source);

  const fields = await findElements(
    sessionId,
    'class name',
    'android.widget.EditText',
  );
  assert.equal(
    fields.length,
    2,
    `Expected the login screen's email and password fields; found ${fields.length}.`,
  );

  for (const [index, label] of ['Email', 'Password'].entries()) {
    const text = await getAttribute(sessionId, elementId(fields[index]), 'text');
    if (text !== '') {
      throw new Error(
        `${label} field is not verifiably empty (text attribute: ${JSON.stringify(text)}); refusing to tap Sign In.`,
      );
    }
  }

  const signInButton = await locateSignInButton(sessionId);
  const enabled = await getAttribute(
    sessionId,
    elementId(signInButton),
    'enabled',
  );
  assert.ok(
    enabled === true || enabled === 'true',
    'Sign In control is not enabled.',
  );

  await request(
    `/session/${sessionId}/element/${encodeURIComponent(elementId(signInButton))}/click`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
    },
  );

  source = await waitForValidationMessages(sessionId);
  assertSignedOutLoginScreen(source);
  assert.ok(source.includes('Enter a valid email'));
  assert.ok(source.includes('Min 6 characters'));
  testPassed = true;
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`FAIL TC-AUTO-002: ${message}`);
  process.exitCode = 1;
} finally {
  if (sessionId) {
    try {
      await request(`/session/${encodeURIComponent(sessionId)}`, {
        method: 'DELETE',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(`FAIL TC-AUTO-002 cleanup: ${message}`);
      process.exitCode = 1;
    }
  }
}

if (testPassed && process.exitCode !== 1) {
  console.log(
    'PASS TC-AUTO-002: empty login fields show both validation messages; no credentials were entered.',
  );
}
