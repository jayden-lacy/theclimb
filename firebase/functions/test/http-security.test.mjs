import assert from "node:assert/strict";
import { once } from "node:events";
import { after, before, beforeEach, test } from "node:test";
import express from "express";
import { getApps, deleteApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { clearEmulatorData, requireEmulators } from "./emulator-safety.mjs";

requireEmulators();
// Only this disposable test process may omit attestation. Test enforcement separately below.
process.env.FUNCTIONS_EMULATOR = "true";
delete process.env.ENFORCE_APP_CHECK;
const handlers = await import("../lib/index.js");
const firestore = getFirestore();
const owner = "api-owner";
const member = "api-member";
const stranger = "api-stranger";
const tokens = new Map();
let server;
let baseURL;

before(async () => {
  for (const uid of [owner, member, stranger]) tokens.set(uid, await signInFixture(uid));
  const app = express();
  app.use(express.json({ limit: "1mb" }));
  for (const [name, handler] of Object.entries(handlers)) {
    if (typeof handler === "function" && handler.__endpoint) app.all(`/${name}`, handler);
  }
  server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  baseURL = `http://127.0.0.1:${server.address().port}`;
});

beforeEach(async () => {
  await clearEmulatorData();
  for (const uid of [owner, member, stranger]) {
    await firestore.doc(`users/${uid}`).set({ id: uid, userID: uid, displayName: uid });
  }
});

after(async () => {
  if (server) await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  await clearEmulatorData();
  for (const uid of tokens.keys()) await getAuth().deleteUser(uid).catch(error => {
    if (error.code !== "auth/user-not-found") throw error;
  });
  await Promise.all(getApps().map(deleteApp));
});

async function signInFixture(uid) {
  const email = `${uid}@example.test`;
  const password = "Local-emulator-test-only-42";
  const existing = await getAuth().getUser(uid).catch(error => {
    if (error.code !== "auth/user-not-found") throw error;
  });
  if (!existing) await getAuth().createUser({ uid, email, password });
  const response = await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key`,
    {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }), signal: AbortSignal.timeout(10000)
    }
  );
  assert.equal(response.status, 200, "Fixture sign-in failed.");
  const result = await response.json();
  assert.equal(result.localId, uid);
  return result.idToken;
}

async function call(name, uid, body = {}, expectedStatus = 200, options = {}) {
  const headers = { "Content-Type": "application/json", ...options.headers };
  if (uid) headers["X-Firebase-Auth"] = tokens.get(uid);
  const response = await fetch(`${baseURL}/${name}`, {
    method: options.method ?? "POST", headers,
    body: options.method === "GET" ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000)
  });
  const result = await response.json();
  assert.equal(response.status, expectedStatus, `${name}: ${JSON.stringify(result)}`);
  return result;
}

const protectedHandlers = [
  "generateDailyPlan", "deleteAccountData", "completeMission", "failMission", "completeRecoveryMission",
  "syncLeaderboard", "createCommunityPost", "addCommunityPostAmen", "reportCommunityPost", "deleteCommunityPost",
  "createCommunityGroup", "joinCommunityGroup", "leaveCommunityGroup", "updateCommunityGroup",
  "setCommunityGroupAdmin", "removeCommunityGroupMember", "deleteCommunityGroup"
];

for (const name of protectedHandlers) {
  test(`${name}: rejects absent authentication and non-POST requests`, async () => {
    await call(name, null, {}, 401);
    await call(name, owner, {}, 405, { method: "GET" });
  });
}

test("authentication: invalid tokens and missing production App Check fail closed", async () => {
  await call("syncLeaderboard", null, {}, 401, { headers: { "X-Firebase-Auth": "not-a-token" } });
  process.env.ENFORCE_APP_CHECK = "true";
  try {
    for (const name of protectedHandlers) await call(name, owner, {}, 401);
  } finally {
    delete process.env.ENFORCE_APP_CHECK;
  }
});

test("authentication: a deleted account's still-unexpired token cannot recreate leaderboard data", async () => {
  const uid = "deleted-fixture";
  tokens.set(uid, await signInFixture(uid));
  await getAuth().deleteUser(uid);
  await call("syncLeaderboard", uid, {}, 401);
  assert.equal((await firestore.doc(`leaderboards/${uid}`).get()).exists, false);
});

test("authentication: disabled accounts cannot write with an earlier valid token", async () => {
  const uid = "disabled-fixture";
  tokens.set(uid, await signInFixture(uid));
  await getAuth().updateUser(uid, { disabled: true });
  await call("createCommunityPost", uid, { body: "Should not be posted" }, 401);
  assert.equal((await firestore.collection("posts").get()).size, 0);
});

test("leaderboard: ignores requested identity, client profile scores, and forged request scores", async () => {
  await firestore.doc(`users/${owner}`).update({ ovrScore: 100, currentStreak: 999 });
  const { entry } = await call("syncLeaderboard", owner, { userID: stranger, ovrScore: 100, streak: 999 });
  assert.equal(entry.id, owner);
  assert.equal(entry.ovrScore, 50);
  assert.equal(entry.streak, 0);
  assert.equal((await firestore.doc(`leaderboards/${stranger}`).get()).exists, false);
});

test("posts: server owns identity, reaction counts, timestamps, and duplicate IDs", async () => {
  const { post } = await call("createCommunityPost", owner, {
    id: "post", body: "Taking one faithful step today.", authorID: stranger, author: "Fake",
    amenCount: 100, createdAt: "2099-01-01T00:00:00Z"
  });
  assert.equal(post.authorID, owner);
  assert.equal(post.author, owner);
  assert.equal(post.amenCount, 0);
  assert.ok(Math.abs(new Date(post.createdAt).getTime() - Date.now()) < 10000);
  const response = await fetch(`${baseURL}/createCommunityPost`, {
    method: "POST", headers: { "Content-Type": "application/json", "X-Firebase-Auth": tokens.get(stranger) },
    body: JSON.stringify({ id: "post", body: "Attempt to replace another post." }), signal: AbortSignal.timeout(15000)
  });
  assert.ok(response.status >= 400);
  assert.equal((await firestore.doc("posts/post").get()).get("authorID"), owner);
});

test("moderation: unsafe posts and group text are rejected by the backend", async () => {
  await call("createCommunityPost", owner, { body: "go die" }, 400);
  await call("createCommunityPost", owner, { body: "https://example.test/promo" }, 400);
  await call("createCommunityGroup", owner, { name: "go die", subtitle: "Fixture", activeChallenge: "Faith" }, 400);
  assert.equal((await firestore.collection("posts").get()).size, 0);
  assert.equal((await firestore.collection("groups").get()).size, 0);
});

test("reactions: concurrent repeats count once per user; different users each count", async () => {
  await call("createCommunityPost", owner, { id: "post", body: "One step at a time." });
  await Promise.all(Array.from({ length: 5 }, () => call("addCommunityPostAmen", member, { postID: "post" })));
  await call("addCommunityPostAmen", stranger, { postID: "post" });
  assert.equal((await firestore.doc("posts/post").get()).get("amenCount"), 2);
  assert.equal((await firestore.collection("postAmens").get()).size, 2);
});

test("reports: trusted identity, evidence, status and deduplication", async () => {
  await call("createCommunityPost", owner, { id: "post", body: "One faithful step." });
  const request = {
    postID: "post", reason: "Concern about this post", reportedUserID: stranger,
    reportedByUserID: owner, category: "hate", severity: "urgent", status: "resolved", postBody: "forged"
  };
  await call("reportCommunityPost", member, request);
  await call("reportCommunityPost", member, request);
  const reports = await firestore.collection("reports").get();
  assert.equal(reports.size, 1);
  const report = reports.docs[0].data();
  assert.equal(report.reportedUserID, owner);
  assert.equal(report.reportedByUserID, member);
  assert.equal(report.status, "submitted");
  assert.equal(report.category, "other");
  assert.equal(report.postBody, "One faithful step.");
  await call("reportCommunityPost", owner, request, 400);
  await call("reportCommunityPost", stranger, { postID: "missing", reason: "Fixture" }, 404);
});

test("post deletion: only author may delete; related reactions and reports are removed", async () => {
  await call("createCommunityPost", owner, { id: "post", body: "One faithful step." });
  await call("addCommunityPostAmen", member, { postID: "post" });
  await call("reportCommunityPost", member, { postID: "post", reason: "Concern" });
  await call("deleteCommunityPost", stranger, { postID: "post", authorID: stranger }, 403);
  await call("deleteCommunityPost", owner, { postID: "post" });
  for (const collection of ["posts", "postAmens", "reports"]) {
    assert.equal((await firestore.collection(collection).get()).size, 0);
  }
});

const groupDetails = { id: "group", name: "Faithful friends", subtitle: "Daily accountability", activeChallenge: "Prayer" };

test("groups: server owns membership and administrator transitions", async () => {
  await call("createCommunityGroup", owner, { ...groupDetails, ownerID: stranger, adminIDs: [stranger] });
  await call("joinCommunityGroup", member, { groupID: "group", memberID: stranger, isAdmin: true });
  const group = (await firestore.doc("groups/group").get()).data();
  assert.equal(group.ownerID, owner);
  assert.deepEqual(group.adminIDs, [owner]);
  assert.deepEqual(new Set(group.memberIDs), new Set([owner, member]));
  await call("setCommunityGroupAdmin", member, { groupID: "group", memberID: member, isAdmin: true }, 403);
  await call("setCommunityGroupAdmin", stranger, { groupID: "group", memberID: stranger, isAdmin: true }, 403);
  await call("setCommunityGroupAdmin", owner, { groupID: "group", memberID: stranger, isAdmin: true }, 400);
  await call("setCommunityGroupAdmin", owner, { groupID: "group", memberID: member, isAdmin: true });
  await call("updateCommunityGroup", member, { ...groupDetails, groupID: "group", name: "Updated friends" });
  await call("removeCommunityGroupMember", member, { groupID: "group", memberID: owner }, 403);
  await call("deleteCommunityGroup", member, { groupID: "group" }, 403);
  await call("deleteCommunityGroup", owner, { groupID: "group" });
  assert.equal((await firestore.doc("groups/group").get()).exists, false);
});

test("groups: ordinary members cannot edit or kick; leaving removes only their own membership", async () => {
  await call("createCommunityGroup", owner, groupDetails);
  await call("joinCommunityGroup", member, { groupID: "group" });
  await call("updateCommunityGroup", member, { ...groupDetails, groupID: "group" }, 403);
  await call("removeCommunityGroupMember", stranger, { groupID: "group", memberID: member }, 403);
  await call("leaveCommunityGroup", owner, { groupID: "group" }, 403);
  await call("leaveCommunityGroup", member, { groupID: "group", memberID: owner });
  assert.deepEqual((await firestore.doc("groups/group").get()).get("memberIDs"), [owner]);
});

test("rate limits: ninth post is rejected without storing it; another user remains unaffected", async () => {
  for (let index = 0; index < 8; index++) await call("createCommunityPost", owner, { body: `Faithful step ${index}` });
  await call("createCommunityPost", owner, { body: "Over the limit" }, 429);
  await call("createCommunityPost", member, { body: "My first step" });
  assert.equal((await firestore.collection("posts").get()).size, 9);
});

const reflection = { hardestPart: "Starting", lessonLearned: "Small steps matter", effortRating: 4, improvementPlan: "Start earlier", mood: "Good" };
const mission = (id = "mission") => ({
  id, date: new Date().toISOString(), title: "Quiet prayer", summary: "Pray without distractions.",
  category: "Faith", durationMinutes: 10, difficulty: 1, status: "active"
});

async function setSnapshot(uid, missions, journalEntries = []) {
  await firestore.doc(`users/${uid}/state/current`).set({
    payload: Buffer.from(JSON.stringify({
      profile: { id: uid, displayName: uid, ovrScore: 100, currentStreak: 999 },
      missions, journalEntries, progress: [], leaderboard: []
    })).toString("base64")
  });
}

test("mission completion: concurrent retries award once and ignore client OVR", async () => {
  await setSnapshot(owner, [mission()]);
  const results = await Promise.all(Array.from({ length: 3 }, () => call("completeMission", owner, {
    ...reflection, missionID: "mission", userID: stranger, ovrScore: 100, appliedDelta: 50
  })));
  assert.equal(results.filter(result => result.appliedDelta > 0).length, 1);
  const score = (await firestore.doc(`userScores/${owner}`).get()).data();
  assert.ok(score.ovrScore > 50 && score.ovrScore < 100);
  assert.equal(score.currentStreak, 1);
  assert.equal((await firestore.doc(`userScores/${stranger}`).get()).exists, false);
  assert.equal((await firestore.collection("journalEntries").get()).size, 1);
});

test("mission persistence: a client snapshot cannot overwrite another account's mission", async () => {
  await firestore.doc("missions/victim-mission").set({ ...mission("victim-mission"), userID: stranger });
  await setSnapshot(owner, [mission("victim-mission")]);
  await call("completeMission", owner, { ...reflection, missionID: "victim-mission" }, 403);
  assert.equal((await firestore.doc("missions/victim-mission").get()).get("userID"), stranger);
  assert.equal((await firestore.doc(`userScores/${owner}`).get()).exists, false);
});

test("mission persistence: forged journal IDs cannot overwrite another account's reflection", async () => {
  await firestore.doc("journalEntries/victim-journal").set({ userID: stranger, lessonLearned: "Private" });
  await setSnapshot(owner, [mission()], [{ id: "victim-journal", missionID: "mission", failureReason: "Missed" }]);
  await call("failMission", owner, { missionID: "mission", reason: "Missed" }, 403);
  assert.equal((await firestore.doc("journalEntries/victim-journal").get()).get("userID"), stranger);
  assert.equal((await firestore.doc(`userScores/${owner}`).get()).exists, false);
});

test("mission history: resetting local status cannot turn completion into a failure", async () => {
  await setSnapshot(owner, [mission()]);
  await call("completeMission", owner, { ...reflection, missionID: "mission" });
  const beforeScore = (await firestore.doc(`userScores/${owner}`).get()).get("ovrScore");
  await setSnapshot(owner, [mission()]);
  await call("failMission", owner, { missionID: "mission", reason: "Replayed snapshot" }, 409);
  assert.equal((await firestore.doc(`userScores/${owner}`).get()).get("ovrScore"), beforeScore);
});

test("recovery: requires failure, awards once, and cannot be bypassed with a stale snapshot", async () => {
  await setSnapshot(owner, [mission()]);
  await call("completeRecoveryMission", owner, { missionID: "mission" }, 409);
  await call("failMission", owner, { missionID: "mission", reason: "Lost focus" });
  await setSnapshot(owner, [mission()]);
  await call("completeMission", owner, { ...reflection, missionID: "mission" }, 409);
  const recovered = await call("completeRecoveryMission", owner, { missionID: "mission" });
  assert.ok(recovered.appliedDelta > 0);
  const repeated = await call("completeRecoveryMission", owner, { missionID: "mission" });
  assert.equal(repeated.appliedDelta, 0);
});

test("recovery: a fabricated failed snapshot cannot award recovery points", async () => {
  await setSnapshot(owner, [{ ...mission(), status: "failed" }]);
  await call("completeRecoveryMission", owner, { missionID: "mission" }, 409);
  assert.equal((await firestore.doc(`userScores/${owner}`).get()).exists, false);
});

test("account cleanup: rejects another user's ID and preserves other users' records", async () => {
  for (const uid of [owner, stranger]) {
    for (const name of ["missions", "devotionals", "journalEntries", "progress", "leaderboards", "userScores", "missionScoreEvents"]) {
      await firestore.doc(`${name}/${uid}`).set({ userID: uid, value: "Private fixture" });
    }
    for (const name of ["aiUsage", "aiDailyPlans", "actionRateLimits"]) {
      await firestore.doc(`${name}/${uid}`).set({ uid });
    }
    await setSnapshot(uid, [mission(`${uid}-mission`)]);
  }
  await call("deleteAccountData", owner, { userID: stranger }, 403);
  await call("deleteAccountData", owner, { userID: owner });
  for (const name of ["users", "missions", "devotionals", "journalEntries", "progress", "leaderboards", "userScores", "missionScoreEvents", "aiUsage", "aiDailyPlans", "actionRateLimits"]) {
    assert.equal((await firestore.doc(`${name}/${owner}`).get()).exists, false, `${name} still contains deleted data`);
    assert.equal((await firestore.doc(`${name}/${stranger}`).get()).exists, true, `${name} lost another user's data`);
  }
  assert.equal((await firestore.doc(`users/${owner}/state/current`).get()).exists, false);
});
