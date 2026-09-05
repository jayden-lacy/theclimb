import assert from "node:assert/strict";

export const projectID = "demo-theclimb-security";

export function requireEmulators() {
  assert.equal(process.env.GCLOUD_PROJECT, projectID, "Tests require the disposable demo project.");
  for (const name of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"]) {
    assert.match(process.env[name] ?? "", /^127\.0\.0\.1:[1-9][0-9]{1,4}$/, `${name} must point to loopback.`);
  }
}

export async function clearEmulatorData() {
  requireEmulators();
  const response = await fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectID}/databases/(default)/documents`,
    { method: "DELETE", signal: AbortSignal.timeout(10000) }
  );
  assert.equal(response.status, 200, "Could not reset the disposable Firestore database.");
}
