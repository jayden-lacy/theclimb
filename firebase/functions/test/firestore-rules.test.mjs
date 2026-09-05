import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { after, before, beforeEach, test } from "node:test";
import {
  assertFails, assertSucceeds, initializeTestEnvironment
} from "@firebase/rules-unit-testing";
import {
  collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, Timestamp, updateDoc, where, writeBatch
} from "firebase/firestore";
import { projectID, requireEmulators } from "./emulator-safety.mjs";

requireEmulators();
let environment;
const owner = "rules-owner";
const stranger = "rules-stranger";
const partner = "rules-partner";
const db = (uid = owner) => environment.authenticatedContext(uid).firestore();
const anonymous = () => environment.unauthenticatedContext().firestore();

before(async () => {
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(":");
  environment = await initializeTestEnvironment({
    projectId: projectID,
    firestore: {
      host,
      port: Number(port),
      rules: await readFile(new URL("../../../firestore.rules", import.meta.url), "utf8")
    }
  });
});
beforeEach(async () => environment.clearFirestore());
after(async () => environment?.cleanup());

async function seed(path, value) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), value);
  });
}

test("profiles: own create/read/update/delete works; identities cannot be replaced", async () => {
  const reference = doc(db(), `users/${owner}`);
  await assertSucceeds(setDoc(reference, { id: owner, userID: owner, displayName: "Owner" }));
  await assertSucceeds(getDoc(reference));
  await assertSucceeds(updateDoc(reference, { displayName: "New name" }));
  await assertFails(updateDoc(reference, { id: stranger }));
  await assertFails(updateDoc(reference, { userID: stranger }));
  await assertSucceeds(deleteDoc(reference));
});

test("profiles: anonymous and other accounts cannot read, overwrite, delete, or enumerate", async () => {
  const path = `users/${owner}`;
  await seed(path, { id: owner, userID: owner });
  for (const client of [anonymous(), db(stranger)]) {
    await assertFails(getDoc(doc(client, path)));
    await assertFails(setDoc(doc(client, path), { id: owner, userID: owner }));
    await assertFails(deleteDoc(doc(client, path)));
    await assertFails(getDocs(collection(client, "users")));
  }
  await assertFails(getDocs(collection(db(), "users")));
  await assertFails(setDoc(doc(db(), `users/${stranger}`), { id: stranger, userID: stranger }));
});

for (const suffix of ["state/current", "preferences/focus", "journal/nested/entries/one"]) {
  test(`private nested records: only the path owner can access ${suffix}`, async () => {
    const path = `users/${owner}/${suffix}`;
    await assertSucceeds(setDoc(doc(db(), path), { value: "private fixture" }));
    await assertSucceeds(getDoc(doc(db(), path)));
    await assertSucceeds(updateDoc(doc(db(), path), { value: "changed" }));
    for (const client of [anonymous(), db(stranger)]) {
      await assertFails(getDoc(doc(client, path)));
      await assertFails(setDoc(doc(client, path), { value: "attack" }));
      await assertFails(deleteDoc(doc(client, path)));
    }
    await assertSucceeds(deleteDoc(doc(db(), path)));
  });
}

for (const name of ["missions", "devotionals", "journalEntries", "progress"]) {
  test(`${name}: own CRUD and owner-filtered queries work`, async () => {
    const client = db();
    const reference = doc(client, name, "own-record");
    await assertSucceeds(setDoc(reference, { userID: owner, value: "private" }));
    await assertSucceeds(getDoc(reference));
    await assertSucceeds(updateDoc(reference, { value: "updated" }));
    await assertSucceeds(getDocs(query(collection(client, name), where("userID", "==", owner))));
    await assertSucceeds(deleteDoc(reference));
  });

  test(`${name}: other-account CRUD, owner reassignment, and unscoped queries fail`, async () => {
    const path = `${name}/private-record`;
    await seed(path, { userID: owner, value: "private" });
    for (const client of [anonymous(), db(stranger)]) {
      await assertFails(getDoc(doc(client, path)));
      await assertFails(setDoc(doc(client, path), { userID: stranger }));
      await assertFails(updateDoc(doc(client, path), { value: "attack" }));
      await assertFails(deleteDoc(doc(client, path)));
      await assertFails(getDocs(collection(client, name)));
    }
    await assertFails(updateDoc(doc(db(), path), { userID: stranger }));
    await assertFails(setDoc(doc(db(), name, "forged"), { userID: stranger }));
    await assertFails(setDoc(doc(db(), name, "missing-owner"), { value: "bad" }));
    await assertFails(getDocs(collection(db(), name)));
    await assertFails(getDocs(query(collection(db(stranger), name), where("userID", "==", owner))));
  });
}

for (const name of ["groups", "posts", "leaderboards"]) {
  test(`${name}: signed-in reading works, but even the owner cannot mutate server-owned records`, async () => {
    const path = `${name}/server-record`;
    await seed(path, { userID: owner, ownerID: owner, authorID: owner, adminIDs: [owner] });
    await assertSucceeds(getDoc(doc(db(), path)));
    await assertSucceeds(getDocs(collection(db(stranger), name)));
    await assertFails(getDoc(doc(anonymous(), path)));
    await assertFails(getDocs(collection(anonymous(), name)));
    for (const client of [anonymous(), db(), db(stranger)]) {
      await assertFails(setDoc(doc(client, name, "new-record"), { userID: owner }));
      await assertFails(updateDoc(doc(client, path), { ovrScore: 100, adminIDs: [stranger] }));
      await assertFails(deleteDoc(doc(client, path)));
    }
  });
}

for (const name of ["userScores", "missionScoreEvents", "postAmens", "actionRateLimits", "aiUsage", "aiDailyPlans"]) {
  test(`${name}: no client can read or mutate backend-only state`, async () => {
    const path = `${name}/${owner}`;
    await seed(path, { userID: owner, uid: owner, count: 1 });
    for (const client of [anonymous(), db(), db(stranger)]) {
      await assertFails(getDoc(doc(client, path)));
      await assertFails(getDocs(collection(client, name)));
      await assertFails(setDoc(doc(client, name, "new"), { userID: owner }));
      await assertFails(updateDoc(doc(client, path), { count: 0 }));
      await assertFails(deleteDoc(doc(client, path)));
    }
  });
}

test("moderation reports: reporter can read own reports but cannot forge or modify them", async () => {
  const path = "reports/server-report";
  await seed(path, { userID: owner, reportedUserID: stranger, status: "submitted" });
  await assertSucceeds(getDoc(doc(db(), path)));
  await assertSucceeds(getDocs(query(collection(db(), "reports"), where("userID", "==", owner))));
  for (const client of [anonymous(), db(stranger)]) {
    await assertFails(getDoc(doc(client, path)));
    await assertFails(deleteDoc(doc(client, path)));
  }
  await assertFails(setDoc(doc(db(), "reports/forged"), { userID: owner }));
  await assertFails(updateDoc(doc(db(), path), { status: "resolved", severity: "urgent" }));
});

function pendingLink() {
  return {
    id: "invite", ownerID: owner, userID: owner, ownerName: "Owner", ownerFocus: "Faith",
    acceptedByID: "", acceptedByName: "", acceptedByFocus: "", status: "pending",
    ownerCheckInCount: 0, acceptedCheckInCount: 0, ownerNudgeCount: 0, acceptedNudgeCount: 0,
    ownerEncouragementCount: 0, acceptedEncouragementCount: 0, lastInteraction: "Invite created"
  };
}

test("partner invites: owner creates, another user accepts, then nonmembers lose access", async () => {
  const path = "partnerLinks/invite";
  await assertSucceeds(setDoc(doc(db(), path), pendingLink()));
  await assertSucceeds(getDoc(doc(db(partner), path)));
  await assertFails(getDocs(collection(db(stranger), "partnerLinks")));
  await assertFails(updateDoc(doc(db(), path), {
    acceptedByID: owner, acceptedByName: "Owner", acceptedByFocus: "Faith", status: "accepted"
  }));
  await assertSucceeds(updateDoc(doc(db(partner), path), {
    acceptedByID: partner, acceptedByName: "Partner", acceptedByFocus: "Focus", status: "accepted"
  }));
  await assertSucceeds(getDoc(doc(db(partner), path)));
  await assertSucceeds(getDocs(query(collection(db(), "partnerLinks"), where("ownerID", "==", owner))));
  await assertFails(getDoc(doc(db(stranger), path)));
  await assertFails(updateDoc(doc(db(stranger), path), { acceptedByID: stranger }));
  await assertFails(deleteDoc(doc(db(stranger), path)));
  await assertSucceeds(deleteDoc(doc(db(partner), path)));
});

test("partner invites: cannot forge ownership, initial activity, fields, or the accepting user", async () => {
  await assertFails(setDoc(doc(db(stranger), "partnerLinks/invite"), pendingLink()));
  await assertFails(setDoc(doc(db(), "partnerLinks/invite"), { ...pendingLink(), ownerCheckInCount: 1 }));
  await assertFails(setDoc(doc(db(), "partnerLinks/invite"), { ...pendingLink(), admin: true }));
  await seed("partnerLinks/invite", pendingLink());
  await assertFails(updateDoc(doc(db(partner), "partnerLinks/invite"), {
    acceptedByID: stranger, acceptedByName: "Fake", acceptedByFocus: "Focus", status: "accepted"
  }));
});

test("partner activity: only a participant's own counter may increase, one at a time", async () => {
  const path = "partnerLinks/invite";
  await seed(path, {
    ...pendingLink(), status: "accepted", acceptedByID: partner, acceptedByName: "Partner", acceptedByFocus: "Faith"
  });
  for (const [uid, prefix] of [[owner, "owner"], [partner, "accepted"]]) {
    await assertSucceeds(updateDoc(doc(db(uid), path), {
      [`${prefix}CheckInCount`]: 1, [`${prefix}LastCheckInAt`]: Timestamp.now()
    }));
    await assertSucceeds(updateDoc(doc(db(uid), path), { [`${prefix}NudgeCount`]: 1 }));
    await assertSucceeds(updateDoc(doc(db(uid), path), { [`${prefix}EncouragementCount`]: 1 }));
    await assertFails(updateDoc(doc(db(uid), path), { [`${prefix}CheckInCount`]: 20 }));
  }
  await assertFails(updateDoc(doc(db(), path), { acceptedNudgeCount: 2 }));
  await assertFails(updateDoc(doc(db(partner), path), { ownerNudgeCount: 2 }));
  await assertFails(updateDoc(doc(db(), path), { ownerID: stranger, userID: stranger }));
  await assertFails(updateDoc(doc(db(), path), { status: "pending", acceptedByID: "" }));
});

test("mixed batches are atomic: one forbidden write rejects the whole batch", async () => {
  const client = db();
  const batch = writeBatch(client);
  batch.set(doc(client, `users/${owner}`), { id: owner, userID: owner });
  batch.set(doc(client, `leaderboards/${owner}`), { userID: owner, ovrScore: 100 });
  await assertFails(batch.commit());
  await environment.withSecurityRulesDisabled(async (context) => {
    assert.equal((await getDoc(doc(context.firestore(), `users/${owner}`))).exists(), false);
  });
});

test("unknown collections default to denied", async () => {
  await assertFails(setDoc(doc(db(), "internalSettings/maintenance"), { enabled: false }));
  await assertFails(getDoc(doc(db(), "internalSettings/maintenance")));
});
