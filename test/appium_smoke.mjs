import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const appPath = path.join(
  projectRoot,
  'build',
  'app',
  'outputs',
  'flutter-apk',
  'app-debug.apk',
);
const appiumUrl = (process.env.APPIUM_URL ?? 'http://127.0.0.1:4723').replace(/\/+$/, '');

if (!existsSync(appPath)) {
  throw new Error('Debug APK not found. Run "flutter build apk --debug" first.');
}

async function request(pathname, options) {
  const response = await fetch(`${appiumUrl}${pathname}`, options);
  const responseText = await response.text();
  if (!response.ok) {
    throw new Error(`Appium returned HTTP ${response.status}: ${responseText}`);
  }
  return JSON.parse(responseText);
}

let sessionId;

try {
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
          'appium:app': appPath,
          'appium:autoGrantPermissions': true,
          'appium:noReset': true,
          'appium:newCommandTimeout': 120,
        },
      },
    }),
  });
  sessionId = created.value?.sessionId;
  assert.ok(sessionId, 'Appium did not return a session ID.');

  const result = await request(`/session/${encodeURIComponent(sessionId)}/source`);
  assert.match(
    result.value,
    /Log in|Login|Sign in|Welcome/i,
    'The sign-in screen was not found in the app UI.',
  );
  console.log('PASS: PurrClean launched and displayed its sign-in screen.');
} finally {
  if (sessionId) {
    await request(`/session/${encodeURIComponent(sessionId)}`, { method: 'DELETE' });
  }
}
