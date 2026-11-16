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
const authEmulatorUrl = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const databaseEmulatorUrl = 'http://127.0.0.1:9000';
const databaseNamespace = 'purrclean-124-default-rtdb';
const apiKey = 'demo-key';
const password = 'PurrCleanTest123!';
const email = `purrclean-ui-${Date.now()}@example.test`;
const runId = Date.now().toString();

if (!existsSync(appPath)) {
  throw new Error(
    'Debug APK not found. Build with --dart-define=PURRCLEAN_USE_FIREBASE_EMULATORS=true first.',
  );
}

async function request(baseUrl, pathname, options) {
  const response = await fetch(`${baseUrl}${pathname}`, options);
  const responseText = await response.text();
  let payload;
  try {
    payload = responseText ? JSON.parse(responseText) : null;
  } catch {
    payload = responseText;
  }
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${responseText}`);
  }
  return payload;
}

async function appium(pathname, options) {
  return request(appiumUrl, pathname, options);
}

async function getSource(sessionId) {
  const result = await appium(`/session/${sessionId}/source`);
  return result.value;
}

async function waitForSource(sessionId, pattern, timeoutMs = 30000) {
  const end = Date.now() + timeoutMs;
  let source = '';
  while (Date.now() < end) {
    source = await getSource(sessionId);
    if (pattern.test(source)) return source;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`Timed out waiting for ${pattern}. Last source:\n${source}`);
}

async function waitForAnySource(sessionId, patterns, timeoutMs = 30000) {
  const end = Date.now() + timeoutMs;
  let source = '';
  while (Date.now() < end) {
    source = await getSource(sessionId);
    if (patterns.some((pattern) => pattern.test(source))) return source;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`Timed out waiting for an expected screen. Last source:\n${source}`);
}

async function waitForValidationMessages(sessionId, messages, baselineSource) {
  const baselineCounts = messages.map(
    (message) => baselineSource.split(message).length - 1,
  );
  const end = Date.now() + 10000;
  let source = '';
  while (Date.now() < end) {
    source = await getSource(sessionId);
    if (
      messages.every(
        (message, index) =>
          source.split(message).length - 1 > baselineCounts[index],
      )
    ) {
      return source;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`Validation messages did not appear. Last source:\n${source}`);
}

async function findElements(sessionId, using, value) {
  const result = await appium(`/session/${sessionId}/elements`, {
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

async function tap(sessionId, label) {
  const matches = await findElements(sessionId, 'accessibility id', label);
  assert.ok(matches.length, `Could not find accessible control "${label}".`);
  await appium(`/session/${sessionId}/element/${elementId(matches[0])}/click`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{}',
  });
}

async function fillFields(sessionId, values) {
  const fields = await findElements(sessionId, 'class name', 'android.widget.EditText');
  assert.equal(fields.length, values.length, `Expected ${values.length} input fields.`);
  for (let index = 0; index < fields.length; index += 1) {
    const id = elementId(fields[index]);
    await appium(`/session/${sessionId}/element/${id}/clear`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
    });
    await appium(`/session/${sessionId}/element/${id}/value`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: values[index] }),
    });
  }
}

async function hideKeyboard(sessionId) {
  await appium(`/session/${sessionId}/appium/device/hide_keyboard`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{}',
  });
}

function passed(id, name) {
  console.log(`PASS ${id}: ${name}`);
}

let sessionId;
let eventPath;

try {
  const created = await appium('/session', {
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
          'appium:fullReset': true,
          'appium:adbExecTimeout': 60000,
          'appium:uiautomator2ServerLaunchTimeout': 60000,
          'appium:newCommandTimeout': 180,
        },
      },
    }),
  });
  sessionId = created.value?.sessionId;
  assert.ok(sessionId, 'Appium did not return a session ID.');

  await waitForSource(sessionId, /Login[\s\S]*Register/);
  passed('TC-001/002', 'app opens to the login/register screen');

  let source;
  await tap(sessionId, 'Register');
  await waitForSource(sessionId, /Full Name[\s\S]*Create Account/);
  source = await getSource(sessionId);
  await tap(sessionId, 'Create Account');
  source = await waitForValidationMessages(
    sessionId,
    ['Enter your name', 'Enter a valid email', 'Min 6 characters'],
    source,
  );
  passed('TC-001-02', 'empty registration fields show validation errors');

  await tap(sessionId, 'Login');
  await tap(sessionId, 'Register');
  await waitForSource(sessionId, /Full Name[\s\S]*Create Account/);
  await fillFields(sessionId, ['Test Owner', 'bad-email', '123']);
  await hideKeyboard(sessionId);
  const malformedSource = await getSource(sessionId);
  await tap(sessionId, 'Create Account');
  await waitForValidationMessages(
    sessionId,
    ['Enter a valid email', 'Min 6 characters'],
    malformedSource,
  );
  passed('TC-001-02', 'malformed email and short password are rejected');

  await fillFields(sessionId, ['PurrClean Test', email, password]);
  await hideKeyboard(sessionId);
  await tap(sessionId, 'Create Account');
  const registrationFailure =
    /error|failed|already exists|not initialized|stronger|try again|invalid email|network|badly formatted/i;
  source = await waitForAnySource(
    sessionId,
    [
      /Device setup[\s\S]*Skip for now/i,
      /Add your cat[\s\S]*Skip for now/i,
      /Analytics[\s\S]*Profile/i,
      registrationFailure,
    ],
    60000,
  );
  assert.doesNotMatch(
    source,
    registrationFailure,
    `Registration failed:\n${source}`,
  );
  passed('TC-001-01', 'valid registration creates an emulator account and advances setup');

  if (/Device setup[\s\S]*Skip for now/i.test(source)) {
    await tap(sessionId, 'Skip for now');
    source = await waitForAnySource(sessionId, [
      /Add your cat[\s\S]*Skip for now/i,
      /Analytics[\s\S]*Profile/i,
    ]);
  }
  if (/Add your cat[\s\S]*Skip for now/i.test(source)) {
    await tap(sessionId, 'Skip for now');
  }
  source = await waitForSource(sessionId, /Analytics[\s\S]*Profile/i, 60000);
  assert.match(source, /No visits yet/i);
  passed('TC-003-02', 'empty device data displays the dashboard no-visits state');

  const timestamp = Date.now();
  eventPath = `/devices/8426/events/${timestamp}.json?ns=${databaseNamespace}`;
  await request(databaseEmulatorUrl, eventPath, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      timestamp,
      dwellTimeSeconds: 45,
      depositMassGrams: 50,
      peakAmmoniaPpm: 10,
      peakOdorIndexPct: 20,
      estimatedOutputType: 1,
      catWeightGrams: 4000,
    }),
  });
  source = await waitForSource(sessionId, /50%|10%|45s|1 visit/i, 30000);
  assert.doesNotMatch(source, /No visits yet/i);
  passed('TC-003-01/013-01', 'a new local database event syncs to the dashboard');

  await tap(sessionId, 'Profile');
  await waitForSource(sessionId, /Log out/i);
  await tap(sessionId, 'Log out');
  await waitForSource(sessionId, /Login[\s\S]*Register/);
  await fillFields(sessionId, [email, 'WrongPassword123!']);
  await hideKeyboard(sessionId);
  await tap(sessionId, 'Sign In');
  await waitForSource(sessionId, /Incorrect email or password/i);
  passed('TC-002-02', 'wrong password is rejected with an error message');

  await fillFields(sessionId, [`unknown-${runId}@example.test`, password]);
  await hideKeyboard(sessionId);
  await tap(sessionId, 'Sign In');
  await waitForSource(sessionId, /Incorrect email or password/i);
  passed('TC-002-03', 'unregistered account is denied');

  await fillFields(sessionId, [email, password]);
  await hideKeyboard(sessionId);
  await tap(sessionId, 'Sign In');
  source = await waitForSource(sessionId, /Analytics[\s\S]*Profile/i, 60000);
  passed('TC-002-01', 'valid credentials open the authenticated dashboard');

  await tap(sessionId, 'Analytics');
  source = await waitForSource(sessionId, /Today's Visits/i, 30000);
  assert.match(source, /Behavioral insights for your cat/i);
  passed('TC-004-01/006-01', 'analytics displays usage summaries and insights');

  await tap(sessionId, 'Weekly');
  source = await waitForAnySource(sessionId, [
    /No Weekly Data Recorded/i,
    /Daily Total Eliminations & Output Volume/i,
  ]);
  passed('TC-004-02', 'weekly analytics displays data or its empty state');

  await tap(sessionId, 'Monthly');
  source = await waitForAnySource(sessionId, [
    /No Monthly Data Recorded/i,
    /Daily Weight/i,
  ]);
  passed('TC-004-03', 'monthly analytics displays data or its empty state');
} finally {
  if (eventPath) {
    await request(databaseEmulatorUrl, eventPath, { method: 'DELETE' });
  }
  if (sessionId) {
    await appium(`/session/${sessionId}`, { method: 'DELETE' });
  }
}
