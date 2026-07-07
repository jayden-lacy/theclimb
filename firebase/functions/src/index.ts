import OpenAI from "openai";
import { randomUUID } from "crypto";
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp, type DocumentReference, type Query } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onRequest, type Request } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import type { Response } from "express";

const openAIKey = defineSecret("OPENAI_API_KEY");
const defaultModel = "gpt-5.4-mini";
const defaultDailyLimit = 6;
const defaultMaxOutputTokens = 1300;
const defaultOpenAITimeoutMs = 20000;
const defaultOpenAIRetryCount = 1;
const minimumMaxOutputTokens = 800;
const dailyPlanCacheVersion = "first-week-heavy-v1";
const maxRecentHistory = 8;
const maxRecentPlanMemory = 10;
const maxGoals = 5;
const maxTextLength = 600;

initializeApp();

type DailyPlanRequest = {
  profile?: {
    ageGroup?: string;
    goals?: string[];
    mainStruggle?: string;
    currentStreak?: number;
    longestStreak?: number;
    recoveryStreak?: number;
    ovrScore?: number;
    streakGoal?: number;
    notificationHour?: number;
    notificationMinute?: number;
    joinedAt?: string;
  };
  recentHistory?: Array<{
    hardestPart?: string;
    lessonLearned?: string;
    effortRating?: number;
    improvementPlan?: string;
    mood?: string;
    failureReason?: string | null;
  }>;
  contentFeedback?: Array<{
    contentKind?: string;
    rating?: string;
    titleSnapshot?: string;
    createdAt?: string;
  }>;
  generatedAt?: string;
  forceRegenerate?: boolean;
  regenerationReason?: string;
};

type DailyPlanResponse = {
  devotional: {
    title: string;
    bibleVerse: string;
    verseText: string;
    explanation: string;
    reflectionQuestion: string;
    practicalAction: string;
  };
  mission: {
    title: string;
    summary: string;
    category: "Focus" | "Faith" | "Discipline" | "Self-control" | "Social";
    durationMinutes: number;
    difficulty: number;
    fallbackTitle: string;
    fallbackSummary: string;
    extraChallenges: string[];
  };
  habits: Array<{
    id: string;
    title: string;
    cadence: string;
    isEnabled: boolean;
  }>;
  challenges: Array<{
    id: string;
    title: string;
    detail: string;
    category: "Focus" | "Faith" | "Discipline" | "Self-control" | "Social";
    daysRemaining: number;
    difficulty: number;
    targetCompletions: number;
  }>;
};

type VerseOption = {
  reference: string;
  text?: string;
};

type ResolvedVerse = Required<VerseOption> & {
  translation: "WEB";
};

type GenerationObservability = {
  requestId: string;
  model?: string;
  openAILatencyMs?: number;
  openAIRequestId?: string;
  openAIUsage?: unknown;
  fallbackReason?: string;
};

type StoredMission = {
  date?: string;
  title?: string;
  summary?: string;
  category?: string;
  durationMinutes?: number;
  difficulty?: number;
  status?: string;
};

type StoredDevotional = {
  date?: string;
  title?: string;
  bibleVerse?: string;
  reflectionQuestion?: string;
  practicalAction?: string;
};

type RecentPlanMemory = {
  missionTitles: string[];
  missionSummaries: string[];
  missionCategories: string[];
  devotionalTitles: string[];
  devotionalVerses: string[];
  reflectionQuestions: string[];
  practicalActions: string[];
};

type StoredSnapshot = {
  missions?: StoredMission[];
  devotionals?: StoredDevotional[];
};

type StoredUserProfile = {
  id?: string;
  displayName?: string;
  ovrScore?: number;
  currentStreak?: number;
};

type StoredAppSnapshot = {
  profile?: StoredUserProfile;
};

type CommunityPostResponse = {
  post: {
    id: string;
    authorID: string;
    author: string;
    body: string;
    createdAt: string;
    amenCount: number;
  };
};

type CommunityGroupResponse = {
  group: {
    id: string;
    name: string;
    subtitle: string;
    members: number;
    activeChallenge: string;
    isJoined: boolean;
    ownerID: string;
    adminIDs: string[];
    memberIDs: string[];
    memberNames: Record<string, string>;
  };
};

type CommunityGroupState = {
  id: string;
  name: string;
  subtitle: string;
  activeChallenge: string;
  ownerID: string;
  creatorID: string;
  adminIDs: string[];
  memberIDs: string[];
  memberNames: Record<string, string>;
};

type LeaderboardResponse = {
  entry: {
    id: string;
    name: string;
    ovrScore: number;
    streak: number;
  };
};

type FallbackDevotionalOption = {
  title: string;
  explanation: string;
  reflectionQuestion: string;
  practicalAction: string;
};

type FallbackMissionOption = {
  title: string;
  summary: string;
  durationMinutes: number;
  difficulty: number;
  fallbackTitle: string;
  fallbackSummary: string;
  extraChallenges: string[];
};

type OnboardingIntent = {
  primaryGoal: string;
  category: DailyPlanResponse["mission"]["category"];
  headline: string;
  planSummary: string;
  missionCue: string;
  devotionalFocus: string;
  habitTitle: string;
  challengeTitle: string;
  streakGoal: number;
  reminderTime: string;
};

type FirstWeekRampContext = {
  active: boolean;
  day?: number;
  title?: string;
  objective?: string;
  spiritualAngle?: string;
  missionMechanic?: string;
  missionCue?: string;
  practicalAction?: string;
  reflectionFocus?: string;
  habitFocus?: string;
  extraChallenge?: string;
  durationBiasMinutes?: number;
  personalizationRule?: string;
};

const verseOptionsByStruggle: Record<string, VerseOption[]> = {
  Focus: [
    { reference: "Colossians 3:23" },
    { reference: "Proverbs 4:25" },
    { reference: "Matthew 6:22" }
  ],
  Discipline: [
    { reference: "Luke 16:10" },
    { reference: "Proverbs 13:4" },
    { reference: "1 Corinthians 9:27" }
  ],
  Consistency: [
    { reference: "Galatians 6:9" },
    { reference: "1 Corinthians 15:58" },
    { reference: "Hebrews 12:1" }
  ],
  "Purity / Self-control": [
    { reference: "Psalm 51:10" },
    { reference: "1 Corinthians 10:13" },
    { reference: "2 Timothy 2:22" }
  ],
  Prayer: [
    { reference: "1 Thessalonians 5:17" },
    { reference: "Philippians 4:6" },
    { reference: "Jeremiah 33:3" }
  ],
  Scripture: [
    { reference: "Psalm 119:105" },
    { reference: "Joshua 1:8" },
    { reference: "Psalm 119:11" }
  ],
  "Social Pressure": [
    { reference: "Romans 12:2" },
    { reference: "Proverbs 29:25" },
    { reference: "Galatians 1:10" }
  ]
};

const dailyPlanSchema = {
  type: "object",
  additionalProperties: false,
  required: ["devotional", "mission", "habits", "challenges"],
  properties: {
    devotional: {
      type: "object",
      additionalProperties: false,
      required: [
        "title",
        "bibleVerse",
        "verseText",
        "explanation",
        "reflectionQuestion",
        "practicalAction"
      ],
      properties: {
        title: { type: "string" },
        bibleVerse: { type: "string" },
        verseText: { type: "string" },
        explanation: { type: "string" },
        reflectionQuestion: { type: "string" },
        practicalAction: { type: "string" }
      }
    },
    mission: {
      type: "object",
      additionalProperties: false,
      required: [
        "title",
        "summary",
        "category",
        "durationMinutes",
        "difficulty",
        "fallbackTitle",
        "fallbackSummary",
        "extraChallenges"
      ],
      properties: {
        title: { type: "string" },
        summary: { type: "string" },
        category: {
          type: "string",
          enum: ["Focus", "Faith", "Discipline", "Self-control", "Social"]
        },
        durationMinutes: { type: "integer", minimum: 5, maximum: 120 },
        difficulty: { type: "integer", minimum: 1, maximum: 5 },
        fallbackTitle: { type: "string" },
        fallbackSummary: { type: "string" },
        extraChallenges: {
          type: "array",
          items: { type: "string" }
        }
      }
    },
    habits: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "title", "cadence", "isEnabled"],
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          cadence: { type: "string" },
          isEnabled: { type: "boolean" }
        }
      }
    },
    challenges: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "title", "detail", "category", "daysRemaining", "difficulty", "targetCompletions"],
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          detail: { type: "string" },
          category: {
            type: "string",
            enum: ["Focus", "Faith", "Discipline", "Self-control", "Social"]
          },
          daysRemaining: { type: "integer", minimum: 1, maximum: 30 },
          difficulty: { type: "integer", minimum: 1, maximum: 5 },
          targetCompletions: { type: "integer", minimum: 1, maximum: 14 }
        }
      }
    }
  }
} as const;

export const generateDailyPlan = onRequest(
  {
    cors: true,
    invoker: "public",
    region: "us-central1",
    timeoutSeconds: 60,
    maxInstances: 10,
    secrets: [openAIKey]
  },
  async (request, response) => {
    const requestId = request.get("x-request-id") || randomUUID();
    const startedAt = Date.now();

    if (request.method !== "POST") {
      response.status(405).json({ error: "Use POST." });
      return;
    }

    let uid = "unknown";
    let generatedDate = new Date().toISOString().slice(0, 10);
    let fallbackReason: string | undefined;
    let servedFromCache = false;
    const observability: GenerationObservability = { requestId };

    try {
      uid = await verifyFirebaseUser(request.get("x-firebase-auth"), request.get("authorization"));
      await verifyAppCheckToken(request.get("x-firebase-appcheck"), uid);
      const body = sanitizedDailyPlanRequest(request.body as DailyPlanRequest);
      generatedDate = generatedDateKey(body);

      if (!body.forceRegenerate) {
        const cachedPlan = await getCachedDailyPlan(uid, generatedDate, requestId);
        if (cachedPlan) {
          servedFromCache = true;
          logger.info("Daily plan request completed.", {
            uid,
            requestId,
            generatedDate,
            source: "cache",
            totalLatencyMs: Date.now() - startedAt
          });
          response.status(200).json(dailyPlanResponsePayload(cachedPlan, {
            source: "cache",
            requestId,
            generatedDate,
            cacheVersion: dailyPlanCacheVersion,
            totalLatencyMs: Date.now() - startedAt
          }));
          return;
        }
      } else {
        logger.info("Daily plan cache bypass requested.", {
          uid,
          requestId,
          generatedDate,
          regenerationReason: body.regenerationReason
        });
      }

      await enforceRateLimit(uid);

      let plan: DailyPlanResponse;
      try {
        plan = await createDailyPlan(body, uid, observability);
      } catch (error) {
        fallbackReason = error instanceof Error ? error.message : String(error);
        observability.fallbackReason = fallbackReason;
        logger.error("AI daily plan generation failed; returning fallback plan.", {
          uid,
          requestId,
          generatedDate,
          model: observability.model,
          openAILatencyMs: observability.openAILatencyMs,
          fallbackReason
        });
        plan = await fallbackDailyPlan(body, uid);
      }

      await writeCachedDailyPlan(uid, generatedDate, plan, fallbackReason ? "fallback" : "generated", requestId);

      logger.info("Daily plan request completed.", {
        uid,
        requestId,
        generatedDate,
        source: fallbackReason ? "fallback" : "openai",
        model: observability.model,
        openAILatencyMs: observability.openAILatencyMs,
        openAIRequestId: observability.openAIRequestId,
        openAIUsage: observability.openAIUsage,
        fallbackReason,
        forceRegenerate: body.forceRegenerate,
        servedFromCache,
        totalLatencyMs: Date.now() - startedAt
      });

      response.status(200).json(dailyPlanResponsePayload(plan, {
        source: fallbackReason ? "fallback" : "openai",
        requestId,
        generatedDate,
        cacheVersion: dailyPlanCacheVersion,
        model: observability.model,
        openAILatencyMs: observability.openAILatencyMs,
        openAIRequestId: observability.openAIRequestId,
        openAIUsage: observability.openAIUsage,
        fallbackReason,
        forceRegenerate: body.forceRegenerate,
        totalLatencyMs: Date.now() - startedAt
      }));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const severity = status >= 500 ? logger.error : logger.warn;
      severity("generateDailyPlan request rejected.", {
        uid,
        requestId,
        generatedDate,
        status,
        totalLatencyMs: Date.now() - startedAt,
        error: error instanceof Error ? error.message : String(error)
      });
      response.status(status).json({
        error: error instanceof Error ? error.message : "Unable to generate plan."
      });
    }
  }
);

export const deleteAccountData = onRequest(
  {
    cors: true,
    invoker: "public",
    region: "us-central1",
    timeoutSeconds: 60,
    maxInstances: 10
  },
  async (request, response) => {
    const requestId = request.get("x-request-id") || randomUUID();
    const startedAt = Date.now();
    let uid = "unknown";

    if (request.method !== "POST") {
      response.status(405).json({ error: "Use POST." });
      return;
    }

    try {
      uid = await verifyFirebaseUser(
        request.get("x-firebase-auth"),
        request.get("authorization"),
        "Sign in before deleting account data."
      );
      await verifyAppCheckToken(request.get("x-firebase-appcheck"), uid);

      const requestedUserID = cleanText((request.body as { userID?: unknown } | undefined)?.userID);
      if (requestedUserID && requestedUserID !== uid) {
        throw new HTTPError(403, "You can only delete your own account data.");
      }

      const deleted = await deleteAccountDataForUser(uid);
      logger.info("Account data deletion completed.", {
        uid,
        requestId,
        deleted,
        totalLatencyMs: Date.now() - startedAt
      });
      response.status(200).json({
        ok: true,
        requestId,
        deleted
      });
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const severity = status >= 500 ? logger.error : logger.warn;
      severity("deleteAccountData request rejected.", {
        uid,
        requestId,
        status,
        totalLatencyMs: Date.now() - startedAt,
        error: error instanceof Error ? error.message : String(error)
      });
      response.status(status).json({
        error: error instanceof Error ? error.message : "Unable to delete account data."
      });
    }
  }
);

const secureHttpOptions = {
  cors: true,
  invoker: "public" as const,
  region: "us-central1",
  timeoutSeconds: 30,
  maxInstances: 10
};

export const syncLeaderboard = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "syncLeaderboard",
      "Sign in before syncing leaderboard data.",
      async ({ uid }) => {
        const entry = await buildTrustedLeaderboardEntry(uid);
        await getFirestore().collection("leaderboards").doc(uid).set(
          {
            ...entry,
            userID: uid,
            updatedAt: FieldValue.serverTimestamp()
          },
          { merge: true }
        );
        return { entry } satisfies LeaderboardResponse;
      }
    );
  }
);

export const createCommunityPost = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "createCommunityPost",
      "Sign in before posting.",
      async ({ uid }) => {
        const body = request.body as Record<string, unknown> | undefined;
        const postBody = requiredCleanText(body?.body, "Post text", 1, 500);
        enforceCommunitySafety(postBody);

        const profile = await publicUserProfile(uid);
        const postId = cleanDocumentID(body?.id) || randomUUID();
        const now = Timestamp.now();
        const post = {
          id: postId,
          authorID: uid,
          author: profile.displayName,
          body: postBody,
          createdAt: now,
          amenCount: 0,
          userID: uid,
          updatedAt: FieldValue.serverTimestamp()
        };

        await getFirestore().collection("posts").doc(postId).create(post);

        return {
          post: {
            id: post.id,
            authorID: post.authorID,
            author: post.author,
            body: post.body,
            createdAt: now.toDate().toISOString(),
            amenCount: post.amenCount
          }
        } satisfies CommunityPostResponse;
      }
    );
  }
);

export const addCommunityPostAmen = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "addCommunityPostAmen",
      "Sign in before reacting to a post.",
      async () => {
        const body = request.body as Record<string, unknown> | undefined;
        const postId = requiredDocumentID(body?.postID, "Post");
        const reference = getFirestore().collection("posts").doc(postId);

        await getFirestore().runTransaction(async (transaction) => {
          const snapshot = await transaction.get(reference);
          if (!snapshot.exists) {
            throw new HTTPError(404, "Post not found.");
          }
          transaction.update(reference, {
            amenCount: FieldValue.increment(1),
            updatedAt: FieldValue.serverTimestamp()
          });
        });

        return { ok: true };
      }
    );
  }
);

export const deleteCommunityPost = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "deleteCommunityPost",
      "Sign in before deleting a post.",
      async ({ uid }) => {
        const body = request.body as Record<string, unknown> | undefined;
        const postId = requiredDocumentID(body?.postID, "Post");
        const reference = getFirestore().collection("posts").doc(postId);

        await getFirestore().runTransaction(async (transaction) => {
          const snapshot = await transaction.get(reference);
          if (!snapshot.exists) {
            throw new HTTPError(404, "Post not found.");
          }
          if (cleanText(snapshot.get("authorID")) !== uid) {
            throw new HTTPError(403, "You can only delete your own posts.");
          }
          transaction.delete(reference);
        });

        await deleteQuery(getFirestore().collection("reports").where("postID", "==", postId));
        return { ok: true };
      }
    );
  }
);

export const createCommunityGroup = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "createCommunityGroup",
      "Sign in before creating a group.",
      async ({ uid }) => {
        const body = request.body as Record<string, unknown> | undefined;
        const profile = await publicUserProfile(uid);
        const groupId = cleanDocumentID(body?.id) || randomUUID();
        const name = requiredCleanText(body?.name, "Group name", 1, 42);
        const subtitle = requiredCleanText(body?.subtitle, "Group subtitle", 1, 96);
        const activeChallenge = requiredCleanText(body?.activeChallenge, "Group focus", 1, 40);
        enforceCommunitySafety(`${name} ${subtitle} ${activeChallenge}`);

        const memberNames = { [uid]: profile.displayName };
        const groupState: CommunityGroupState = {
          id: groupId,
          name,
          subtitle,
          activeChallenge,
          ownerID: uid,
          creatorID: uid,
          adminIDs: [uid],
          memberIDs: [uid],
          memberNames
        };
        const group = {
          ...groupState,
          members: 1,
          userID: uid,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp()
        };

        await getFirestore().collection("groups").doc(groupId).create(group);
        return { group: groupResponse(groupState, uid) } satisfies CommunityGroupResponse;
      }
    );
  }
);

export const joinCommunityGroup = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "joinCommunityGroup",
      "Sign in before joining a group.",
      async ({ uid }) => {
        const body = request.body as Record<string, unknown> | undefined;
        const groupId = requiredDocumentID(body?.groupID, "Group");
        const profile = await publicUserProfile(uid);
        const displayName = optionalCleanText(body?.displayName, 40) || profile.displayName;
        const group = await updateGroupTransaction(groupId, uid, (state) => {
          if (!state.memberIDs.includes(uid)) {
            if (state.memberIDs.length >= 5000) {
              throw new HTTPError(409, "This group is full.");
            }
            state.memberIDs.push(uid);
          }
          state.memberNames[uid] = displayName;
          return state;
        });

        return { group: groupResponse(group, uid) } satisfies CommunityGroupResponse;
      }
    );
  }
);

export const leaveCommunityGroup = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "leaveCommunityGroup",
      "Sign in before leaving a group.",
      async ({ uid }) => {
        const body = request.body as Record<string, unknown> | undefined;
        const groupId = requiredDocumentID(body?.groupID, "Group");
        const group = await updateGroupTransaction(groupId, uid, (state) => {
          if (state.ownerID === uid) {
            throw new HTTPError(403, "Group owners must delete the group instead of leaving it.");
          }
          state.memberIDs = state.memberIDs.filter((memberID) => memberID !== uid);
          state.adminIDs = state.adminIDs.filter((adminID) => adminID !== uid);
          delete state.memberNames[uid];
          return state;
        });

        return { group: groupResponse(group, uid) } satisfies CommunityGroupResponse;
      }
    );
  }
);

export const updateCommunityGroup = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "updateCommunityGroup",
      "Sign in before editing a group.",
      async ({ uid }) => {
        const body = request.body as Record<string, unknown> | undefined;
        const groupId = requiredDocumentID(body?.groupID, "Group");
        const name = requiredCleanText(body?.name, "Group name", 1, 42);
        const subtitle = requiredCleanText(body?.subtitle, "Group subtitle", 1, 96);
        const activeChallenge = requiredCleanText(body?.activeChallenge, "Group focus", 1, 40);
        enforceCommunitySafety(`${name} ${subtitle} ${activeChallenge}`);

        const group = await updateGroupTransaction(groupId, uid, (state) => {
          requireGroupAdmin(state, uid);
          state.name = name;
          state.subtitle = subtitle;
          state.activeChallenge = activeChallenge;
          return state;
        });

        return { group: groupResponse(group, uid) } satisfies CommunityGroupResponse;
      }
    );
  }
);

export const setCommunityGroupAdmin = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "setCommunityGroupAdmin",
      "Sign in before managing group admins.",
      async ({ uid }) => {
        const body = request.body as Record<string, unknown> | undefined;
        const groupId = requiredDocumentID(body?.groupID, "Group");
        const memberId = requiredUserID(body?.memberID, "Member");
        const isAdmin = body?.isAdmin === true;

        const group = await updateGroupTransaction(groupId, uid, (state) => {
          requireGroupOwner(state, uid);
          if (memberId === state.ownerID) {
            return state;
          }
          if (!state.memberIDs.includes(memberId)) {
            throw new HTTPError(400, "This person is not in the group.");
          }
          state.adminIDs = isAdmin ?
            uniqueStrings([...state.adminIDs, memberId]) :
            state.adminIDs.filter((adminID) => adminID !== memberId);
          return state;
        });

        return { group: groupResponse(group, uid) } satisfies CommunityGroupResponse;
      }
    );
  }
);

export const removeCommunityGroupMember = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "removeCommunityGroupMember",
      "Sign in before removing group members.",
      async ({ uid }) => {
        const body = request.body as Record<string, unknown> | undefined;
        const groupId = requiredDocumentID(body?.groupID, "Group");
        const memberId = requiredUserID(body?.memberID, "Member");

        const group = await updateGroupTransaction(groupId, uid, (state) => {
          requireGroupAdmin(state, uid);
          if (memberId === state.ownerID) {
            throw new HTTPError(403, "The group owner cannot be removed.");
          }
          state.memberIDs = state.memberIDs.filter((existingMemberID) => existingMemberID !== memberId);
          state.adminIDs = state.adminIDs.filter((adminID) => adminID !== memberId);
          delete state.memberNames[memberId];
          return state;
        });

        return { group: groupResponse(group, uid) } satisfies CommunityGroupResponse;
      }
    );
  }
);

export const deleteCommunityGroup = onRequest(
  secureHttpOptions,
  async (request, response) => {
    await handleAuthenticatedPost(
      request,
      response,
      "deleteCommunityGroup",
      "Sign in before deleting a group.",
      async ({ uid }) => {
        const body = request.body as Record<string, unknown> | undefined;
        const groupId = requiredDocumentID(body?.groupID, "Group");
        const reference = getFirestore().collection("groups").doc(groupId);

        await getFirestore().runTransaction(async (transaction) => {
          const snapshot = await transaction.get(reference);
          if (!snapshot.exists) {
            throw new HTTPError(404, "Group not found.");
          }
          const state = communityGroupState(snapshot.data() ?? {}, groupId);
          requireGroupOwner(state, uid);
          transaction.delete(reference);
        });

        return { ok: true };
      }
    );
  }
);

class HTTPError extends Error {
  constructor(
    readonly status: number,
    message: string
  ) {
    super(message);
  }
}

type AuthenticatedRequestContext = {
  uid: string;
  requestId: string;
  startedAt: number;
};

async function handleAuthenticatedPost(
  request: Request,
  response: Response,
  functionName: string,
  missingTokenMessage: string,
  handler: (context: AuthenticatedRequestContext) => Promise<unknown>
): Promise<void> {
  const requestId = request.get("x-request-id") || randomUUID();
  const startedAt = Date.now();
  let uid = "unknown";

  if (request.method !== "POST") {
    response.status(405).json({ error: "Use POST." });
    return;
  }

  try {
    uid = await verifyFirebaseUser(
      request.get("x-firebase-auth"),
      request.get("authorization"),
      missingTokenMessage
    );
    await verifyAppCheckToken(request.get("x-firebase-appcheck"), uid);

    const result = await handler({ uid, requestId, startedAt });
    logger.info(`${functionName} completed.`, {
      uid,
      requestId,
      totalLatencyMs: Date.now() - startedAt
    });
    response.status(200).json({
      ok: true,
      requestId,
      ...objectPayload(result)
    });
  } catch (error) {
    const status = error instanceof HTTPError ? error.status : 500;
    const severity = status >= 500 ? logger.error : logger.warn;
    severity(`${functionName} request rejected.`, {
      uid,
      requestId,
      status,
      totalLatencyMs: Date.now() - startedAt,
      error: error instanceof Error ? error.message : String(error)
    });
    response.status(status).json({
      error: error instanceof Error ? error.message : "Unable to finish that request."
    });
  }
}

function objectPayload(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return value as Record<string, unknown>;
}

async function buildTrustedLeaderboardEntry(uid: string): Promise<LeaderboardResponse["entry"]> {
  const firestore = getFirestore();
  const userReference = firestore.collection("users").doc(uid);
  const [userSnapshot, stateSnapshot] = await Promise.all([
    userReference.get(),
    userReference.collection("state").doc("current").get()
  ]);
  const storedProfile = storedProfileFromPayload(stateSnapshot.get("payload")) ??
    storedProfileFromDocument(userSnapshot.data() ?? {});
  const publicProfile = await publicUserProfile(uid);

  return {
    id: uid,
    name: resolvedDisplayName(storedProfile.displayName || publicProfile.displayName),
    ovrScore: cleanNumber(storedProfile.ovrScore, 0, 100),
    streak: cleanNumber(storedProfile.currentStreak, 0, 3650)
  };
}

async function publicUserProfile(uid: string): Promise<{ displayName: string }> {
  const userSnapshot = await getFirestore().collection("users").doc(uid).get();
  const storedName = cleanText(userSnapshot.get("displayName"));
  if (storedName) {
    return { displayName: resolvedDisplayName(storedName) };
  }

  try {
    const user = await getAuth().getUser(uid);
    return {
      displayName: resolvedDisplayName(user.displayName || user.email || "Climber")
    };
  } catch {
    return { displayName: "Climber" };
  }
}

function storedProfileFromPayload(payload: unknown): StoredUserProfile {
  if (typeof payload !== "string" || payload.length === 0) {
    return {};
  }

  try {
    const decoded = JSON.parse(Buffer.from(payload, "base64").toString("utf8")) as StoredAppSnapshot;
    return decoded.profile ?? {};
  } catch {
    return {};
  }
}

function storedProfileFromDocument(data: Record<string, unknown>): StoredUserProfile {
  return {
    displayName: cleanText(data.displayName),
    ovrScore: cleanNumber(data.ovrScore, 0, 100),
    currentStreak: cleanNumber(data.currentStreak, 0, 3650)
  };
}

function resolvedDisplayName(name: string): string {
  const cleanedName = optionalCleanText(name, 40);
  return cleanedName || "Climber";
}

function optionalCleanText(value: unknown, maxLength: number): string {
  if (typeof value !== "string") {
    return "";
  }
  return value.replace(/\s+/g, " ").trim().slice(0, maxLength);
}

function requiredCleanText(value: unknown, fieldName: string, minimumLength: number, maximumLength: number): string {
  const cleaned = optionalCleanText(value, maximumLength);
  if (cleaned.length < minimumLength) {
    throw new HTTPError(400, `${fieldName} is required.`);
  }
  return cleaned;
}

function cleanDocumentID(value: unknown): string {
  const cleaned = optionalCleanText(value, 128);
  if (!cleaned || cleaned.includes("/") || cleaned === "." || cleaned === "..") {
    return "";
  }
  return cleaned;
}

function requiredDocumentID(value: unknown, fieldName: string): string {
  const cleaned = cleanDocumentID(value);
  if (!cleaned) {
    throw new HTTPError(400, `${fieldName} ID is required.`);
  }
  return cleaned;
}

function requiredUserID(value: unknown, fieldName: string): string {
  const cleaned = requiredCleanText(value, `${fieldName} ID`, 1, 128);
  if (cleaned.includes("/")) {
    throw new HTTPError(400, `${fieldName} ID is invalid.`);
  }
  return cleaned;
}

type CommunitySafetyAssessment = {
  isAllowed: boolean;
  userMessage: string;
};

const communitySafetyRules: Array<{
  tokens: string[];
  userMessage: string;
}> = [
  {
    tokens: ["kys", "kill yourself", "go die", "end yourself", "unalive yourself"],
    userMessage: "This looks unsafe. Edit it so it supports life and immediate help."
  },
  {
    tokens: ["nigger", "faggot", "chink", "spic", "tranny"],
    userMessage: "Remove hateful or dehumanizing language before posting."
  },
  {
    tokens: ["fuck", "shit", "bitch", "asshole", "whore", "slut", "retard"],
    userMessage: "Edit the language and try again."
  },
  {
    tokens: ["onlyfans", "send nudes", "porn", "sex tape"],
    userMessage: "Sexual content is not allowed in community posts."
  },
  {
    tokens: ["http://", "https://", "cashapp", "venmo", "telegram", "crypto"],
    userMessage: "Links, payments, and promotional content are not allowed here."
  }
];

function assessCommunitySafety(text: string): CommunitySafetyAssessment {
  const normalized = text.toLowerCase().replace(/[^a-z0-9:/]+/g, " ").replace(/\s+/g, " ").trim();
  const rule = communitySafetyRules.find((candidate) =>
    candidate.tokens.some((token) => normalized.includes(token))
  );
  if (!rule) {
    return { isAllowed: true, userMessage: "" };
  }
  return { isAllowed: false, userMessage: rule.userMessage };
}

function enforceCommunitySafety(text: string): void {
  const assessment = assessCommunitySafety(text);
  if (!assessment.isAllowed) {
    throw new HTTPError(400, assessment.userMessage);
  }
}

async function updateGroupTransaction(
  groupId: string,
  uid: string,
  mutator: (state: CommunityGroupState) => CommunityGroupState
): Promise<CommunityGroupState> {
  const reference = getFirestore().collection("groups").doc(groupId);
  let updatedGroup: CommunityGroupState | null = null;

  await getFirestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      throw new HTTPError(404, "Group not found.");
    }

    const currentState = communityGroupState(snapshot.data() ?? {}, groupId);
    const nextState = normalizedGroupState(mutator({ ...currentState }));
    transaction.update(reference, {
      id: nextState.id,
      name: nextState.name,
      subtitle: nextState.subtitle,
      activeChallenge: nextState.activeChallenge,
      userID: nextState.creatorID,
      ownerID: nextState.ownerID,
      adminIDs: nextState.adminIDs,
      memberIDs: nextState.memberIDs,
      memberNames: nextState.memberNames,
      members: nextState.memberIDs.length,
      updatedAt: FieldValue.serverTimestamp()
    });
    updatedGroup = nextState;
  });

  if (!updatedGroup) {
    throw new HTTPError(500, "Unable to update group.");
  }
  return updatedGroup;
}

function communityGroupState(data: Record<string, unknown>, fallbackId: string): CommunityGroupState {
  const id = cleanDocumentID(data.id) || fallbackId;
  const name = requiredCleanText(data.name, "Group name", 1, 42);
  const subtitle = requiredCleanText(data.subtitle, "Group subtitle", 1, 96);
  const activeChallenge = requiredCleanText(data.activeChallenge, "Group focus", 1, 40);
  const ownerID = cleanText(data.ownerID) || cleanText(data.userID);
  if (!ownerID) {
    throw new HTTPError(409, "Group is missing an owner.");
  }

  return normalizedGroupState({
    id,
    name,
    subtitle,
    activeChallenge,
    ownerID,
    creatorID: cleanText(data.userID) || ownerID,
    adminIDs: uniqueStrings(data.adminIDs),
    memberIDs: uniqueStrings(data.memberIDs),
    memberNames: stringRecord(data.memberNames)
  });
}

function normalizedGroupState(state: CommunityGroupState): CommunityGroupState {
  const memberIDs = uniqueStrings([state.ownerID, ...state.memberIDs]).slice(0, 5000);
  const adminIDs = uniqueStrings([state.ownerID, ...state.adminIDs]).filter((adminID) => memberIDs.includes(adminID));
  const memberNames = stringRecord(state.memberNames);
  for (const memberID of memberIDs) {
    if (!memberNames[memberID]) {
      memberNames[memberID] = memberID === state.ownerID ? "Group Admin" : `Member ${memberID.slice(0, 6)}`;
    }
  }

  return {
    ...state,
    memberIDs,
    adminIDs,
    memberNames
  };
}

function groupResponse(state: CommunityGroupState, uid: string): CommunityGroupResponse["group"] {
  return {
    id: state.id,
    name: state.name,
    subtitle: state.subtitle,
    members: state.memberIDs.length,
    activeChallenge: state.activeChallenge,
    isJoined: state.memberIDs.includes(uid),
    ownerID: state.ownerID,
    adminIDs: state.adminIDs,
    memberIDs: state.memberIDs,
    memberNames: state.memberNames
  };
}

function requireGroupAdmin(state: CommunityGroupState, uid: string): void {
  if (state.ownerID !== uid && !state.adminIDs.includes(uid)) {
    throw new HTTPError(403, "Only group admins can do that.");
  }
}

function requireGroupOwner(state: CommunityGroupState, uid: string): void {
  if (state.ownerID !== uid) {
    throw new HTTPError(403, "Only the group owner can do that.");
  }
}

function appCheckIsRequired(): boolean {
  const rawValue = process.env.ENFORCE_APP_CHECK;
  if (rawValue === undefined || rawValue.trim() === "") {
    return process.env.FUNCTIONS_EMULATOR !== "true";
  }

  const value = rawValue.toLowerCase();
  return value === "true" || value === "1" || value === "yes";
}

function dailyLimit(): number {
  const parsed = Number.parseInt(process.env.AI_DAILY_LIMIT_PER_USER ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : defaultDailyLimit;
}

function maxOutputTokens(): number {
  const parsed = Number.parseInt(process.env.OPENAI_MAX_OUTPUT_TOKENS ?? "", 10);
  if (!Number.isFinite(parsed)) {
    return defaultMaxOutputTokens;
  }
  return Math.min(defaultMaxOutputTokens, Math.max(minimumMaxOutputTokens, parsed));
}

function openAITimeoutMs(): number {
  const parsed = Number.parseInt(process.env.OPENAI_TIMEOUT_MS ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 5000 ? parsed : defaultOpenAITimeoutMs;
}

function openAIRetryCount(): number {
  const parsed = Number.parseInt(process.env.OPENAI_RETRY_COUNT ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.min(2, parsed) : defaultOpenAIRetryCount;
}

function generatedDateKey(request: DailyPlanRequest): string {
  const requestedDate = request.generatedAt?.slice(0, 10);
  return requestedDate && /^\d{4}-\d{2}-\d{2}$/.test(requestedDate) ? requestedDate : new Date().toISOString().slice(0, 10);
}

function dailyPlanCacheDocument(uid: string, generatedDate: string) {
  return getFirestore().collection("aiDailyPlans").doc(`${uid}_${generatedDate}_${dailyPlanCacheVersion}`);
}

async function getCachedDailyPlan(uid: string, generatedDate: string, requestId: string): Promise<DailyPlanResponse | null> {
  const snapshot = await dailyPlanCacheDocument(uid, generatedDate).get();
  const plan = snapshot.get("plan");
  if (!snapshot.exists || !isDailyPlanResponse(plan)) {
    return null;
  }

  logger.info("Daily plan cache hit.", {
    uid,
    requestId,
    generatedDate,
    source: snapshot.get("source") ?? "unknown"
  });
  return plan;
}

async function writeCachedDailyPlan(
  uid: string,
  generatedDate: string,
  plan: DailyPlanResponse,
  source: "generated" | "fallback",
  requestId: string
): Promise<void> {
  await dailyPlanCacheDocument(uid, generatedDate).set(
    {
      uid,
      generatedDate,
      plan,
      source,
      requestId,
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 1000 * 60 * 60 * 24 * 45)),
      cacheVersion: dailyPlanCacheVersion
    },
    { merge: true }
  );
}

function isDailyPlanResponse(value: unknown): value is DailyPlanResponse {
  if (!value || typeof value !== "object") {
    return false;
  }
  const plan = value as DailyPlanResponse;
  return Boolean(
    plan.devotional &&
    typeof plan.devotional.title === "string" &&
    typeof plan.devotional.bibleVerse === "string" &&
    typeof plan.devotional.verseText === "string" &&
    plan.mission &&
    typeof plan.mission.title === "string" &&
    Array.isArray(plan.habits) &&
    Array.isArray(plan.challenges)
  );
}

function dailyPlanResponsePayload(plan: DailyPlanResponse, meta: Record<string, unknown>): DailyPlanResponse & { meta: Record<string, unknown> } {
  return {
    ...plan,
    meta
  };
}

async function verifyFirebaseUser(
  firebaseAuthHeader?: string,
  authorizationHeader?: string,
  missingTokenMessage = "Sign in before generating a daily plan."
): Promise<string> {
  const prefix = "Bearer ";
  const token = firebaseAuthHeader ?? (
    authorizationHeader?.startsWith(prefix) ? authorizationHeader.slice(prefix.length) : undefined
  );
  if (!token) {
    throw new HTTPError(401, missingTokenMessage);
  }

  try {
    const decodedToken = await getAuth().verifyIdToken(token);
    return decodedToken.uid;
  } catch (error) {
    if (error instanceof HTTPError) {
      throw error;
    }
    throw new HTTPError(401, "Your sign-in expired. Sign in again.");
  }
}

async function verifyAppCheckToken(appCheckHeader: string | undefined, uid: string): Promise<void> {
  const required = appCheckIsRequired();

  if (!appCheckHeader) {
    if (required) {
      logger.warn("Missing App Check token rejected.", { uid });
      throw new HTTPError(401, "Update the app before generating a daily plan.");
    }
    logger.info("Missing App Check token soft-allowed because ENFORCE_APP_CHECK is false.", { uid });
    return;
  }

  try {
    await getAppCheck().verifyToken(appCheckHeader);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (required) {
      logger.warn("Invalid App Check token rejected.", { uid, error: message });
      throw new HTTPError(401, "Unable to verify this app install.");
    }
    logger.warn("Invalid App Check token soft-allowed because ENFORCE_APP_CHECK is false.", {
      uid,
      error: message
    });
  }
}

async function enforceRateLimit(uid: string): Promise<void> {
  const dateKey = new Date().toISOString().slice(0, 10);
  const document = getFirestore().collection("aiUsage").doc(`${uid}_${dateKey}`);
  const limit = dailyLimit();

  let nextCount = 0;

  await getFirestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(document);
    const currentCount = snapshot.exists ? Number(snapshot.get("count") ?? 0) : 0;
    if (currentCount >= limit) {
      logger.warn("AI daily generation limit rejected.", {
        uid,
        dateKey,
        currentCount,
        limit
      });
      throw new HTTPError(429, "Daily AI generation limit reached. Try again tomorrow.");
    }

    nextCount = currentCount + 1;
    transaction.set(
      document,
      {
        uid,
        dateKey,
        count: FieldValue.increment(1),
        limit,
        updatedAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromDate(new Date(Date.now() + 1000 * 60 * 60 * 24 * 35))
      },
      { merge: true }
    );
  });

  logger.info("AI daily usage counted.", {
    uid,
    dateKey,
    count: nextCount,
    limit
  });
}

async function deleteAccountDataForUser(uid: string): Promise<Record<string, number>> {
  const firestore = getFirestore();
  const deleted: Record<string, number> = {};
  const ownedCollections = [
    "missions",
    "devotionals",
    "journalEntries",
    "progress",
    "partnerLinks",
    "posts",
    "reports"
  ];

  deleted.groups = await removeUserFromGroups(uid);

  for (const collection of ownedCollections) {
    deleted[collection] = await deleteQuery(
      firestore.collection(collection).where("userID", "==", uid)
    );
  }

  deleted.postsByAuthor = await deleteQuery(
    firestore.collection("posts").where("authorID", "==", uid)
  );
  deleted.partnerLinksAcceptedBy = await deleteQuery(
    firestore.collection("partnerLinks").where("acceptedByID", "==", uid)
  );
  deleted.reportsAgainstUser = await deleteQuery(
    firestore.collection("reports").where("reportedUserID", "==", uid)
  );
  deleted.aiDailyPlans = await deleteQuery(
    firestore.collection("aiDailyPlans").where("uid", "==", uid)
  );
  deleted.aiUsage = await deleteQuery(
    firestore.collection("aiUsage").where("uid", "==", uid)
  );
  deleted.userState = await deleteQuery(
    firestore.collection("users").doc(uid).collection("state")
  );
  deleted.knownUserDocuments = await deleteDocumentReferences([
    firestore.collection("leaderboards").doc(uid),
    firestore.collection("users").doc(uid)
  ]);

  return deleted;
}

async function removeUserFromGroups(uid: string): Promise<number> {
  const firestore = getFirestore();
  const snapshot = await firestore.collection("groups").where("memberIDs", "array-contains", uid).get();
  const ownedGroupReferences: DocumentReference[] = [];
  const updates: Array<{ reference: DocumentReference; data: Record<string, unknown> }> = [];

  for (const document of snapshot.docs) {
    const data = document.data();
    const ownerID = cleanText(data.ownerID) || cleanText(data.userID);
    if (ownerID === uid) {
      ownedGroupReferences.push(document.ref);
      continue;
    }

    const memberIDs = uniqueStrings(data.memberIDs).filter((memberID) => memberID !== uid);
    const adminIDs = uniqueStrings(data.adminIDs).filter((adminID) => adminID !== uid && memberIDs.includes(adminID));
    const memberNames = stringRecord(data.memberNames);
    delete memberNames[uid];

    updates.push({
      reference: document.ref,
      data: {
        memberIDs,
        adminIDs,
        memberNames,
        members: memberIDs.length,
        updatedAt: FieldValue.serverTimestamp()
      }
    });
  }

  const updatedCount = await updateDocumentReferences(updates);
  const deletedCount = await deleteDocumentReferences(ownedGroupReferences);
  return updatedCount + deletedCount;
}

async function deleteQuery(query: Query): Promise<number> {
  const snapshot = await query.get();
  return deleteDocumentReferences(snapshot.docs.map((document) => document.ref));
}

async function deleteDocumentReferences(references: DocumentReference[]): Promise<number> {
  let batch = getFirestore().batch();
  let operationCount = 0;
  let deletedCount = 0;

  for (const reference of references) {
    batch.delete(reference);
    operationCount += 1;
    deletedCount += 1;

    if (operationCount === 450) {
      await batch.commit();
      batch = getFirestore().batch();
      operationCount = 0;
    }
  }

  if (operationCount > 0) {
    await batch.commit();
  }

  return deletedCount;
}

async function updateDocumentReferences(updates: Array<{ reference: DocumentReference; data: Record<string, unknown> }>): Promise<number> {
  let batch = getFirestore().batch();
  let operationCount = 0;
  let updatedCount = 0;

  for (const update of updates) {
    batch.update(update.reference, update.data);
    operationCount += 1;
    updatedCount += 1;

    if (operationCount === 450) {
      await batch.commit();
      batch = getFirestore().batch();
      operationCount = 0;
    }
  }

  if (operationCount > 0) {
    await batch.commit();
  }

  return updatedCount;
}

function uniqueStrings(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return Array.from(new Set(value.map(cleanText).filter(Boolean)));
}

function stringRecord(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(value)
      .map(([key, entryValue]) => [cleanText(key), cleanText(entryValue)] as const)
      .filter(([key, entryValue]) => Boolean(key && entryValue))
  );
}

function sanitizedDailyPlanRequest(request: DailyPlanRequest): DailyPlanRequest {
  const profile = request.profile ?? {};
  return {
    profile: {
      ageGroup: cleanText(profile.ageGroup),
      goals: (profile.goals ?? []).slice(0, maxGoals).map(cleanText).filter(Boolean),
      mainStruggle: cleanText(profile.mainStruggle) || "Discipline",
      currentStreak: cleanNumber(profile.currentStreak, 0, 3650),
      longestStreak: cleanNumber(profile.longestStreak, 0, 3650),
      recoveryStreak: cleanNumber(profile.recoveryStreak, 0, 3650),
      ovrScore: cleanNumber(profile.ovrScore, 0, 100),
      streakGoal: profile.streakGoal === undefined ? 30 : cleanNumber(profile.streakGoal, 7, 365),
      notificationHour: profile.notificationHour === undefined ? 8 : cleanNumber(profile.notificationHour, 0, 23),
      notificationMinute: profile.notificationMinute === undefined ? 0 : cleanNumber(profile.notificationMinute, 0, 59),
      joinedAt: cleanText(profile.joinedAt)
    },
    recentHistory: (request.recentHistory ?? []).slice(0, maxRecentHistory).map((entry) => ({
      hardestPart: cleanText(entry.hardestPart),
      lessonLearned: cleanText(entry.lessonLearned),
      effortRating: cleanNumber(entry.effortRating, 1, 5),
      improvementPlan: cleanText(entry.improvementPlan),
      mood: cleanText(entry.mood),
      failureReason: entry.failureReason ? cleanText(entry.failureReason) : null
    })),
    contentFeedback: (request.contentFeedback ?? []).slice(0, 12).map((entry) => ({
      contentKind: cleanText(entry.contentKind),
      rating: cleanText(entry.rating),
      titleSnapshot: cleanText(entry.titleSnapshot),
      createdAt: cleanText(entry.createdAt)
    })),
    generatedAt: cleanText(request.generatedAt),
    forceRegenerate: request.forceRegenerate === true,
    regenerationReason: cleanText(request.regenerationReason)
  };
}

function cleanText(value: unknown): string {
  if (typeof value !== "string") {
    return "";
  }
  return value.replace(/\s+/g, " ").trim().slice(0, maxTextLength);
}

function cleanNumber(value: unknown, minimum: number, maximum: number): number {
  const numberValue = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(numberValue)) {
    return minimum;
  }
  return Math.min(Math.max(Math.round(numberValue), minimum), maximum);
}

function progressionPlan(profile: DailyPlanRequest["profile"]): {
  targetDifficulty: number;
  targetChallengeCompletions: number;
  minimumDurationMinutes: number;
  missionPressure: string;
  growthBand: string;
  ageMaturity: ReturnType<typeof ageMaturityContext>;
} {
  const ovr = cleanNumber(profile?.ovrScore, 0, 100);
  const streak = cleanNumber(profile?.currentStreak, 0, 3650);
  const recoveryStreak = cleanNumber(profile?.recoveryStreak, 0, 3650);
  const streakGoal = cleanNumber(profile?.streakGoal, 7, 365);
  const ageGroup = cleanText(profile?.ageGroup);
  const ageMaturity = ageMaturityContext(ageGroup);
  const ovrLevel = ovrDifficultyStep(ovr);
  const streakStep = streak >= 14 ? 2 : streak >= 5 ? 1 : 0;
  const ambitionStep = streakGoal >= 60 ? 1 : 0;
  const starterAdjustment = streakGoal <= 14 && ovr < 60 ? -1 : 0;
  const recoveryAdjustment = streak === 0 && recoveryStreak > 0 ? -1 : 0;
  const targetDifficulty = Math.min(
    5,
    Math.max(1, ovrLevel + streakStep + ambitionStep + ageMaturity.difficultyAdjustment + starterAdjustment + recoveryAdjustment)
  );

  return {
    targetDifficulty,
    targetChallengeCompletions: requiredChallengeCompletions(targetDifficulty),
    minimumDurationMinutes: minimumMissionMinutes(targetDifficulty, ageGroup),
    missionPressure: missionPressureLine(targetDifficulty),
    growthBand: ovr >= 90 ? "mastery" : ovr >= 75 ? "advanced" : ovr >= 60 ? "building" : "foundation",
    ageMaturity
  };
}

function ovrDifficultyStep(ovr: number): number {
  if (ovr < 55) {
    return 1;
  }
  if (ovr < 68) {
    return 2;
  }
  if (ovr < 80) {
    return 3;
  }
  if (ovr < 90) {
    return 4;
  }
  return 5;
}

function requiredChallengeCompletions(difficulty: number): number {
  if (difficulty <= 1) {
    return 3;
  }
  if (difficulty === 2) {
    return 5;
  }
  if (difficulty === 3) {
    return 7;
  }
  if (difficulty === 4) {
    return 10;
  }
  return 14;
}

function challengeWindowDays(difficulty: number): number {
  if (difficulty <= 1) {
    return 5;
  }
  if (difficulty === 2) {
    return 7;
  }
  if (difficulty === 3) {
    return 10;
  }
  if (difficulty === 4) {
    return 14;
  }
  return 21;
}

function minimumMissionMinutes(difficulty: number, ageGroup: string): number {
  const base = ageMaturityContext(ageGroup).baseMissionMinutes;
  return Math.min(90, base + Math.max(0, difficulty - 1) * 10);
}

function ageMaturityContext(ageGroup: string) {
  const normalized = ageGroup.toLowerCase().replace(/\s+/g, " ").trim();
  if (normalized === "13 - 15" || normalized === "13-15") {
    return {
      band: "13-15",
      maturityTitle: "foundation",
      difficultyAdjustment: -1,
      baseMissionMinutes: 15,
      devotionalDirective: "Keep lessons concrete, direct, and school-life aware. Avoid adult-level pressure. Focus on one clear choice, one honest prayer, and one action they can finish.",
      missionDirective: "Use simple success conditions, shorter protected blocks, clear boundaries, and reflection that builds honesty without shame."
    };
  }
  if (normalized === "16 - 18" || normalized === "16-18" || normalized === "teen") {
    return {
      band: "16-18",
      maturityTitle: "identity and responsibility",
      difficultyAdjustment: 0,
      baseMissionMinutes: 20,
      devotionalDirective: "Make lessons more mature by naming identity, peer pressure, digital temptation, responsibility, and the kind of person repeated choices are forming.",
      missionDirective: "Require a visible boundary, a specific success condition, and one choice that trains character under pressure."
    };
  }
  if (normalized === "college" || normalized === "19 - 24" || normalized === "19-24") {
    return {
      band: "19-24",
      maturityTitle: "independence and ownership",
      difficultyAdjustment: 0,
      baseMissionMinutes: 25,
      devotionalDirective: "Make lessons ownership-driven. Connect faith to independence, schedule control, study or work pressure, relationships, and private discipline when nobody is checking.",
      missionDirective: "Require adult ownership: plan the block, remove the distraction before it starts, finish measurable work, and report the result honestly."
    };
  }
  return {
    band: "25+",
    maturityTitle: "vocation and leadership",
    difficultyAdjustment: 1,
    baseMissionMinutes: 30,
    devotionalDirective: "Make lessons mature and weighty. Connect faith to vocation, leadership, money, family, integrity, long-term consistency, and responsibilities that affect other people.",
    missionDirective: "Make missions more demanding and mature: protect a longer window, remove a known escape route, include follow-through, and connect the action to leadership or stewardship."
  };
}

function missionPressureLine(difficulty: number): string {
  if (difficulty <= 1) {
    return "Level 1: finish the simple version without skipping reflection.";
  }
  if (difficulty === 2) {
    return "Level 2: add resistance by protecting the full timer and removing the first distraction.";
  }
  if (difficulty === 3) {
    return "Level 3: finish the mission and add one accountability check-in afterward.";
  }
  if (difficulty === 4) {
    return "Level 4: complete the full mission with app blocking, reflection, and a concrete next step.";
  }
  return "Level 5: protect the full window, remove every known trigger, and report the result to your partner.";
}

function firstWeekRamp(profile: DailyPlanRequest["profile"], generatedDate: string): FirstWeekRampContext {
  const joinedAt = cleanText(profile?.joinedAt);
  const joinedTime = Date.parse(joinedAt);
  const generatedTime = Date.parse(`${generatedDate}T00:00:00.000Z`);
  if (!joinedAt || !Number.isFinite(joinedTime) || !Number.isFinite(generatedTime)) {
    return { active: false };
  }

  const joinedStart = Date.parse(new Date(joinedTime).toISOString().slice(0, 10) + "T00:00:00.000Z");
  const dayOffset = Math.floor((generatedTime - joinedStart) / 86_400_000);
  if (dayOffset < 0 || dayOffset > 6) {
    return { active: false };
  }

  return firstWeekRampSteps[dayOffset];
}

function personalizationContext(
  request: DailyPlanRequest,
  intent: OnboardingIntent,
  progression: ReturnType<typeof progressionPlan>,
  ramp: FirstWeekRampContext,
  recentPlanMemory: RecentPlanMemory
) {
  const profile = request.profile ?? {};
  const history = request.recentHistory ?? [];
  const feedback = request.contentFeedback ?? [];
  const recentFailures = history.filter((entry) => cleanText(entry.failureReason).length > 0);
  const latestEntry = history[0];
  const commonFailureReason = mostCommonText(recentFailures.map((entry) => cleanText(entry.failureReason)));
  const commonHardestPart = mostCommonText(history.map((entry) => cleanText(entry.hardestPart)));
  const latestImprovementPlan = cleanText(latestEntry?.improvementPlan);
  const averageEffort = averageEffortRating(history);
  const lowEffortCount = history.filter((entry) => cleanNumber(entry.effortRating, 1, 5) <= 2).length;
  const highEffortCount = history.filter((entry) => cleanNumber(entry.effortRating, 1, 5) >= 4).length;
  const missionTooEasy = feedback.filter((entry) => entry.contentKind === "mission" && entry.rating === "tooEasy");
  const missionTooHard = feedback.filter((entry) => entry.contentKind === "mission" && entry.rating === "tooHard");
  const notRelevant = feedback.filter((entry) => entry.rating === "notRelevant");
  const goodFeedback = feedback.filter((entry) => entry.rating === "good");
  const feedbackDirective = (() => {
    if (missionTooEasy.length > missionTooHard.length) {
      return "The user has said missions are too easy. Increase specificity, resistance, accountability, and measurable constraints without making the plan impossible.";
    }
    if (missionTooHard.length > missionTooEasy.length) {
      return "The user has said missions are too hard. Keep the target difficulty, but reduce setup friction and make the first step clearer.";
    }
    if (notRelevant.length > 0) {
      return "The user has rejected at least one plan as not relevant. Change the mission mechanic and devotional angle away from the rejected titles.";
    }
    if (goodFeedback.length > 0) {
      return "The user has marked similar content as good. Preserve the useful tone while changing the actual action.";
    }
    return "No strong feedback signal yet. Use onboarding and first-week progression as the main guide.";
  })();

  const streak = cleanNumber(profile.currentStreak, 0, 3650);
  const ovr = cleanNumber(profile.ovrScore, 0, 100);
  const streakState = streak === 0 ?
    "new-or-reset" :
    streak < 3 ?
      "fragile-start" :
      streak < 7 ?
        "early-momentum" :
        "established";
  const ovrState = ovr < 55 ? "baseline" : ovr < 70 ? "building" : ovr < 85 ? "strong" : "high";

  return {
    userSignals: {
      primaryGoal: intent.primaryGoal,
      mainStruggle: profile.mainStruggle ?? "Discipline",
      ageGroup: profile.ageGroup ?? "",
      ageMaturity: progression.ageMaturity,
      streakState,
      currentStreak: streak,
      streakGoal: intent.streakGoal,
      ovrState,
      ovrScore: ovr,
      reminderTime: intent.reminderTime,
      appBlockingShouldBeConsidered: intent.category === "Focus" || intent.category === "Self-control"
    },
    firstWeek: ramp.active ? ramp : null,
    behaviorSignals: {
      recentFailureCount: recentFailures.length,
      commonFailureReason,
      commonHardestPart,
      latestImprovementPlan,
      averageEffort,
      lowEffortCount,
      highEffortCount,
      feedbackDirective,
      rejectedTitles: uniqueNonEmpty(notRelevant.map((entry) => cleanText(entry.titleSnapshot))).slice(0, 6),
      likedTitles: uniqueNonEmpty(goodFeedback.map((entry) => cleanText(entry.titleSnapshot))).slice(0, 6)
    },
    contentMemory: {
      avoidMissionTitles: recentPlanMemory.missionTitles.slice(0, 6),
      avoidDevotionalTitles: recentPlanMemory.devotionalTitles.slice(0, 6),
      avoidPracticalActions: recentPlanMemory.practicalActions.slice(0, 6),
      recentCategories: recentPlanMemory.missionCategories.slice(0, 6)
    },
    progression,
    generationRequirements: uniqueNonEmpty([
      `Primary mission must train ${intent.primaryGoal}.`,
      `Mission category should be ${intent.category} unless the first-week day clearly requires a secondary category.`,
      ramp.active ? `This is Day ${ramp.day} of the first week: ${ramp.title}. Objective: ${ramp.objective}.` : "",
      ramp.active ? `Use mission mechanic: ${ramp.missionMechanic}.` : "",
      ramp.active ? `Use spiritual angle: ${ramp.spiritualAngle}.` : "",
      commonFailureReason ? `Counter the recent failure reason: ${commonFailureReason}.` : "",
      commonHardestPart ? `Address the hardest part the user reports: ${commonHardestPart}.` : "",
      latestImprovementPlan ? `Respect the user's own improvement plan: ${latestImprovementPlan}.` : "",
      feedbackDirective
    ])
  };
}

function mostCommonText(values: string[]): string {
  const counts = new Map<string, number>();
  for (const value of values.map(cleanText).filter(Boolean)) {
    const key = value.toLowerCase();
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }

  let winner = "";
  let highestCount = 0;
  for (const [value, count] of counts.entries()) {
    if (count > highestCount) {
      winner = value;
      highestCount = count;
    }
  }
  return winner;
}

function averageEffortRating(history: NonNullable<DailyPlanRequest["recentHistory"]>): number | null {
  const ratings = history
    .map((entry) => cleanNumber(entry.effortRating, 1, 5))
    .filter((rating) => Number.isFinite(rating));
  if (ratings.length === 0) {
    return null;
  }
  return Math.round((ratings.reduce((total, rating) => total + rating, 0) / ratings.length) * 10) / 10;
}

const firstWeekRampSteps: FirstWeekRampContext[] = [
  {
    active: true,
    day: 1,
    title: "Start clean",
    objective: "Prove that one small act of obedience can start the climb.",
    spiritualAngle: "small beginnings, honest return, and obedience before emotion",
    missionMechanic: "one written commitment plus one short mission block",
    missionCue: "Day 1 must feel like a clean start: one honest prayer, one written sentence, and one small action completed before overthinking.",
    practicalAction: "Pray one honest sentence, write the exact promise for today, and begin the mission within two minutes.",
    reflectionFocus: "What resistance showed up before you even started?",
    habitFocus: "first promise kept",
    extraChallenge: "Name the exact moment today usually gets away from you.",
    durationBiasMinutes: 0,
    personalizationRule: "Keep the mission simple, but make the success condition concrete enough that the user cannot fake completion."
  },
  {
    active: true,
    day: 2,
    title: "Remove friction",
    objective: "Make obedience easier by changing the environment before pressure rises.",
    spiritualAngle: "wisdom, preparation, and removing what competes for attention",
    missionMechanic: "environment reset before the main action",
    missionCue: "Day 2 must make the user remove one known obstacle before the mission begins.",
    practicalAction: "Move or block one distraction, clear the mission space, and start before checking another app.",
    reflectionFocus: "Which obstacle had more control over you than you expected?",
    habitFocus: "remove one obstacle early",
    extraChallenge: "Set up tomorrow's first step before bed.",
    durationBiasMinutes: 0,
    personalizationRule: "Use the user's main struggle to choose the obstacle: phone, delayed task, trigger, approval pressure, or prayer avoidance."
  },
  {
    active: true,
    day: 3,
    title: "Hold attention",
    objective: "Train one uninterrupted block of attention.",
    spiritualAngle: "undivided attention, worship through focus, and staying present",
    missionMechanic: "single-task timer with no context switching",
    missionCue: "Day 3 must require one completed block without switching tasks, apps, tabs, or conversations.",
    practicalAction: "Put the phone away, breathe for ten seconds, name the one task, and stay until the timer ends.",
    reflectionFocus: "What tried to pull your attention away first?",
    habitFocus: "one-task start",
    extraChallenge: "Write what pulled at your attention after the mission.",
    durationBiasMinutes: 5,
    personalizationRule: "If the user chose a phone or focus goal, make app blocking or physical phone distance part of the setup."
  },
  {
    active: true,
    day: 4,
    title: "Tell the truth",
    objective: "Turn discipline into honest self-awareness and accountability.",
    spiritualAngle: "truth, confession, humility, and bringing hidden resistance to God",
    missionMechanic: "mission plus accountability check-in",
    missionCue: "Day 4 must include honest reflection and one accountability action, not only task completion.",
    practicalAction: "Ask God to show the real resistance underneath the habit, then send one honest update to a partner or trusted person.",
    reflectionFocus: "What did you not want to admit about the resistance?",
    habitFocus: "honest check-in",
    extraChallenge: "Send one accountability update before the day ends.",
    durationBiasMinutes: 5,
    personalizationRule: "Use recent failureReason or hardestPart as the thing the user must tell the truth about."
  },
  {
    active: true,
    day: 5,
    title: "Repeat the win",
    objective: "Convert one good moment into a repeatable rhythm.",
    spiritualAngle: "endurance, repetition, and faithfulness after the newness fades",
    missionMechanic: "same cue, same time, repeatable action",
    missionCue: "Day 5 must repeat a faithful pattern at the same time or cue if possible.",
    practicalAction: "Anchor today's action to the same cue used yesterday, then set tomorrow's cue before the day ends.",
    reflectionFocus: "What made this action repeatable or fragile?",
    habitFocus: "same cue repeat",
    extraChallenge: "Protect a five-minute reset before your weakest hour.",
    durationBiasMinutes: 5,
    personalizationRule: "Make the mission feel like a rhythm the user could keep for seven more days, not a one-off stunt."
  },
  {
    active: true,
    day: 6,
    title: "Raise the standard",
    objective: "Add one stricter boundary now that the user has evidence they can follow through.",
    spiritualAngle: "self-control, surrender, and choosing the harder faithful option",
    missionMechanic: "stronger boundary plus full timer completion",
    missionCue: "Day 6 should raise the standard with one cleaner boundary, a full timer, and no easy escape route.",
    practicalAction: "Choose the stricter version of the boundary today and keep it until the reflection is submitted.",
    reflectionFocus: "What escape route did you want to keep available?",
    habitFocus: "stricter boundary",
    extraChallenge: "Avoid the easiest escape route until the mission is complete.",
    durationBiasMinutes: 10,
    personalizationRule: "If app blocking is enabled, make the mission explicitly use the blocking window. If not, use a physical boundary."
  },
  {
    active: true,
    day: 7,
    title: "Review and commit",
    objective: "Review the first week and choose the next seven-day rhythm.",
    spiritualAngle: "remembrance, gratitude, commitment, and wisdom for the next step",
    missionMechanic: "weekly review plus one commitment action",
    missionCue: "Day 7 must include a short first-week review before the main action and end by choosing the next rhythm.",
    practicalAction: "Write one lesson from the week, thank God for one specific sign of growth, and choose the habit you will keep next week.",
    reflectionFocus: "What pattern from this week is God asking you to continue?",
    habitFocus: "next seven-day commitment",
    extraChallenge: "Choose the one habit you will keep for the next seven days.",
    durationBiasMinutes: 10,
    personalizationRule: "Make the mission feel like a weekly review and recommitment, not just another task."
  }
];

function onboardingIntent(profile: DailyPlanRequest["profile"]): OnboardingIntent {
  const goals = (profile?.goals ?? []).map(cleanText).filter(Boolean);
  const struggle = cleanText(profile?.mainStruggle) || "Discipline";
  const primaryGoal = prioritizedGoal(goals, struggle);
  const streakGoal = cleanNumber(profile?.streakGoal, 7, 365);
  const notificationHour = profile?.notificationHour === undefined ? 8 : cleanNumber(profile.notificationHour, 0, 23);
  const notificationMinute = profile?.notificationMinute === undefined ? 0 : cleanNumber(profile.notificationMinute, 0, 59);
  const reminderTime = `${String(notificationHour).padStart(2, "0")}:${String(notificationMinute).padStart(2, "0")}`;
  const goal = primaryGoal.toLowerCase();
  const pressurePoint = struggle.toLowerCase();
  const intensity = streakGoal >= 60 ?
    "Long streak goal: raise difficulty deliberately as consistency grows." :
    streakGoal <= 14 ?
      "Starter streak goal: keep the first plan simple enough to complete." :
      "Reset streak goal: build meaningful pressure without making Day 1 too heavy.";

  if (goal.includes("phone")) {
    return {
      primaryGoal,
      category: "Focus",
      headline: "Phone boundaries first",
      planSummary: `Prioritize app blocking, phone distance, and protected attention while training ${pressurePoint}. ${intensity}`,
      missionCue: "Make the mission include a specific phone boundary, app-blocking window, or no-scroll condition.",
      devotionalFocus: "attention before God instead of reaction to the phone",
      habitTitle: "Phone away before mission",
      challengeTitle: "Phone Boundary",
      streakGoal,
      reminderTime
    };
  }

  if (goal.includes("procrastinating")) {
    return {
      primaryGoal,
      category: "Discipline",
      headline: "Delayed tasks become the target",
      planSummary: `Prioritize one avoided responsibility, a visible stopping point, and action before entertainment while training ${pressurePoint}. ${intensity}`,
      missionCue: "Make the mission target one delayed task and define the exact stopping point.",
      devotionalFocus: "faithfulness before motivation",
      habitTitle: "Hard thing before easy thing",
      challengeTitle: "Delayed Task",
      streakGoal,
      reminderTime
    };
  }

  if (goal.includes("prayer")) {
    return {
      primaryGoal,
      category: "Faith",
      headline: "Prayer becomes the anchor",
      planSummary: `Prioritize honest prayer before pressure, scrolling, or reaction while training ${pressurePoint}. ${intensity}`,
      missionCue: "Make the mission begin with honest prayer and end with one concrete obedience step.",
      devotionalFocus: "returning to God before the pressure grows",
      habitTitle: "Two-minute honest prayer",
      challengeTitle: "Prayer Rhythm",
      streakGoal,
      reminderTime
    };
  }

  if (goal.includes("self-control") || goal.includes("bad habits")) {
    return {
      primaryGoal,
      category: "Self-control",
      headline: "Triggers get a plan",
      planSummary: `Prioritize identifying the first trigger, changing environment, and replacing the habit while training ${pressurePoint}. ${intensity}`,
      missionCue: "Make the mission include a named trigger, a location change, and a replacement action.",
      devotionalFocus: "a clean heart and a prepared boundary",
      habitTitle: "Trigger reset",
      challengeTitle: "Guardrail",
      streakGoal,
      reminderTime
    };
  }

  if (goal.includes("focus")) {
    return {
      primaryGoal,
      category: "Focus",
      headline: "Focus gets protected",
      planSummary: `Prioritize one task, one protected timer, and fewer context switches while training ${pressurePoint}. ${intensity}`,
      missionCue: "Make the mission use a single task, a timer, and a no-switching success condition.",
      devotionalFocus: "undivided attention as obedience",
      habitTitle: "One-task focus start",
      challengeTitle: "Deep Work",
      streakGoal,
      reminderTime
    };
  }

  if (goal.includes("confidence")) {
    return {
      primaryGoal,
      category: "Social",
      headline: "Courage becomes visible",
      planSummary: `Prioritize one visible act of honesty, service, encouragement, or responsibility while training ${pressurePoint}. ${intensity}`,
      missionCue: "Make the mission include one visible action before the user feels fully ready.",
      devotionalFocus: "courage formed by truth instead of approval",
      habitTitle: "One courage step",
      challengeTitle: "Courage Step",
      streakGoal,
      reminderTime
    };
  }

  if (goal.includes("consistent")) {
    return {
      primaryGoal,
      category: "Discipline",
      headline: "Consistency gets simple",
      planSummary: `Prioritize a repeatable win at the reminder time ${reminderTime} while training ${pressurePoint}. ${intensity}`,
      missionCue: "Make the mission repeatable and small enough to do again tomorrow at the same time.",
      devotionalFocus: "showing up again when motivation drops",
      habitTitle: "Same-time small win",
      challengeTitle: "No-Zero Chain",
      streakGoal,
      reminderTime
    };
  }

  if (goal.includes("god")) {
    return {
      primaryGoal,
      category: "Faith",
      headline: "Faith leads the system",
      planSummary: `Prioritize scripture, prayer, and practical obedience while training ${pressurePoint}. ${intensity}`,
      missionCue: "Make the mission connect the devotional verse to one concrete action.",
      devotionalFocus: "obedience that makes faith practical",
      habitTitle: "Verse into action",
      challengeTitle: "Obedience Practice",
      streakGoal,
      reminderTime
    };
  }

  return {
    primaryGoal,
    category: "Discipline",
    headline: "Discipline becomes daily",
    planSummary: `Prioritize the next right thing before the day drifts while training ${pressurePoint}. ${intensity}`,
    missionCue: "Make the mission a concrete next right thing with a clear finish line.",
    devotionalFocus: "faithfulness in the small thing",
    habitTitle: "Next right thing",
    challengeTitle: "Hard Thing First",
    streakGoal,
    reminderTime
  };
}

function prioritizedGoal(goals: string[], struggle: string): string {
  const fallback = fallbackGoalForStruggle(struggle);
  if (goals.length === 0) {
    return fallback;
  }
  const priorityTerms = [
    "phone",
    "procrastinating",
    "prayer",
    "self-control",
    "bad habits",
    "focus",
    "confidence",
    "consistent",
    "god",
    "discipline"
  ];
  for (const term of priorityTerms) {
    const match = goals.find((goal) => goal.toLowerCase().includes(term));
    if (match) {
      return match;
    }
  }
  return goals[0];
}

function fallbackGoalForStruggle(struggle: string): string {
  if (struggle === "Focus") {
    return "Improve focus";
  }
  if (struggle === "Consistency") {
    return "Become consistent";
  }
  if (struggle === "Purity / Self-control") {
    return "Strengthen self-control";
  }
  if (struggle === "Prayer") {
    return "Improve prayer life";
  }
  if (struggle === "Scripture") {
    return "Grow closer to God";
  }
  if (struggle === "Social Pressure") {
    return "Build confidence";
  }
  return "Build discipline";
}

async function createDailyPlan(
  request: DailyPlanRequest,
  uid: string,
  observability: GenerationObservability
): Promise<DailyPlanResponse> {
  const client = new OpenAI({ apiKey: openAIKey.value() });
  const struggle = request.profile?.mainStruggle ?? "Discipline";
  const verseOptions = verseOptionsByStruggle[struggle] ?? verseOptionsByStruggle.Discipline;
  const generatedDate = generatedDateKey(request);
  const recentPlanMemory = await loadRecentPlanMemory(uid);
  const recentlyUsedVerses = recentPlanMemory.devotionalVerses
    .map(normalizedVerseReference)
    .filter(Boolean);
  const unusedAllowedVerses = verseOptions
    .map((verse) => verse.reference)
    .filter((reference) => !recentlyUsedVerses.includes(reference.toLowerCase()));
  const model = process.env.OPENAI_MODEL ?? defaultModel;
  observability.model = model;
  const outputTokenLimit = maxOutputTokens();
  const promptId = process.env.OPENAI_DAILY_PLAN_PROMPT_ID?.trim();
  const progression = progressionPlan(request.profile);
  const intent = onboardingIntent(request.profile);
  const ramp = firstWeekRamp(request.profile, generatedDate);
  const personalization = personalizationContext(request, intent, progression, ramp, recentPlanMemory);
  const promptVariables = {
    profile: JSON.stringify(request.profile ?? {}),
    onboardingIntent: JSON.stringify(intent),
    firstWeekRamp: JSON.stringify(ramp),
    personalizationContext: JSON.stringify(personalization),
    recentHistory: JSON.stringify(request.recentHistory ?? []),
    contentFeedback: JSON.stringify(request.contentFeedback ?? []),
    recentPlanMemory: JSON.stringify(recentPlanMemory),
    generatedDate,
    forceRegenerate: JSON.stringify(request.forceRegenerate === true),
    regenerationReason: cleanText(request.regenerationReason),
    allowedVerses: JSON.stringify(verseOptions.map((verse) => verse.reference)),
    preferredVerses: JSON.stringify(unusedAllowedVerses.length > 0 ? unusedAllowedVerses : verseOptions.map((verse) => verse.reference)),
    progression: JSON.stringify(progression)
  };
  const input = [
    {
      role: "system",
      content: [
        "You generate daily Christian discipline plans for The Climb.",
        "Write in a calm, serious, modern tone for teens and young adults.",
        "Return only the requested JSON shape.",
        "Use one of the provided WEB/public-domain references exactly for bibleVerse; set verseText to an empty string because the server will attach the approved public-domain verse text.",
        "Make the devotional explanation 140-220 words and tie it directly to the user's struggle.",
        "Make the mission concrete, measurable, and possible today.",
        "Use onboardingIntent as the main personalization contract. The mission, practicalAction, at least one habit, and the primary challenge must directly reflect onboardingIntent.primaryGoal, onboardingIntent.missionCue, and onboardingIntent.challengeTitle.",
        "Use personalizationContext as the strongest source of truth after safety and schema. It contains the user's first-week day, behavior signals, feedback signals, and specific generation requirements.",
        "Use personalizationContext.userSignals.ageMaturity to adjust maturity and difficulty. The devotional must follow ageMaturity.devotionalDirective and the mission must follow ageMaturity.missionDirective without directly naming these directives.",
        "If firstWeekRamp.active is true, treat the first-week day as a curriculum, not decoration. The mission must follow firstWeekRamp.missionMechanic, the devotional must reflect firstWeekRamp.spiritualAngle, the reflection question must use firstWeekRamp.reflectionFocus, and one habit or extra challenge must use firstWeekRamp.habitFocus.",
        "Do not write tutorial-like copy such as 'Day 1 teaches you'. Make the plan feel natural while still following the day objective.",
        "If personalizationContext.behaviorSignals.commonFailureReason exists, the mission summary must include a concrete countermeasure for that failure reason.",
        "If personalizationContext.behaviorSignals.latestImprovementPlan exists, incorporate the user's own improvement plan into the mission or practical action.",
        "If forceRegenerate is true, the user rejected today's previous plan. Generate a materially different mission/devotional and address regenerationReason through the new plan without saying the plan was regenerated.",
        "Use contentFeedback as learning memory. Good means preserve that style. Too easy means increase specificity, resistance, or duration within progression limits. Too hard means lower friction without making it vague. Not relevant means change the mechanic and spiritual angle away from the titleSnapshot.",
        "If onboardingIntent.category differs from the struggle category, prefer onboardingIntent.category for the primary mission and use the struggle as the pressure point being trained.",
        "Use onboardingIntent.reminderTime and streakGoal when a same-time repeat or streak rhythm is relevant.",
        "Use the provided progression object. Mission difficulty must match targetDifficulty. Duration must be at least minimumDurationMinutes. Include missionPressure as one of the extraChallenges.",
        "For older age bands, make lessons more mature and missions more demanding through ownership, accountability, follow-through, and longer protected windows. For younger age bands, keep missions concrete, safe, and finishable.",
        "Challenges must get harder as targetDifficulty rises by increasing targetCompletions, duration, required consistency, and daysRemaining.",
        "Every generated day must feel materially different from the recent plan memory.",
        "Do not reuse or lightly paraphrase recent mission titles, mission summaries, devotional titles, reflection questions, or practical actions.",
        "Prefer an allowed Bible reference that is not in recentlyUsedVerses. If all allowed references were used recently, pick the least similar angle and write a new devotional title.",
        "Rotate mission mechanics across focus block, prayer, scripture, environment reset, service, accountability, planning, cleanup, courage conversation, and recovery action. Do not default to a phone-away deep-work mission unless recentPlanMemory has no similar mission.",
        "Mission title must name the concrete action; summary must include a clear duration, setting, and success condition.",
        "The devotional should focus on a distinct spiritual angle such as obedience, endurance, courage, repentance, attention, surrender, wisdom, honesty, humility, or service.",
        "Do not repeat generic habit-tracker language. Write like a focused Christian discipline coach.",
        "Avoid clinical, medical, crisis, or therapy claims. Keep advice practical and spiritually grounded.",
        "Do not mention that AI generated this content."
      ].join(" ")
    },
    {
      role: "user",
      content: JSON.stringify({
        profile: request.profile,
        recentHistory: request.recentHistory ?? [],
        contentFeedback: request.contentFeedback ?? [],
        personalizationContext: personalization,
        recentPlanMemory,
        generatedAt: request.generatedAt,
        generatedDate,
        forceRegenerate: request.forceRegenerate === true,
        regenerationReason: cleanText(request.regenerationReason),
        onboardingIntent: intent,
        firstWeekRamp: ramp,
        allowedVerses: verseOptions.map((verse) => verse.reference),
        preferredVerses: unusedAllowedVerses.length > 0 ? unusedAllowedVerses : verseOptions.map((verse) => verse.reference),
        recentlyUsedVerses,
        progression,
        distinctnessRules: [
          "Choose a different mission mechanic than the most recent mission.",
          "Choose a different title structure than the last three titles.",
          "Avoid repeating words like quiet, focused, phone-away, reset, or today if those appeared recently.",
        "Make the fallback mission different from the primary mission, not just shorter."
        ],
        feedbackRules: [
          "If recent mission feedback includes Too easy, make the mission more concrete and add measured resistance without exceeding progression.minimumDurationMinutes by more than 20 minutes.",
          "If recent mission feedback includes Too hard, keep the targetDifficulty but make the setup simpler and the success condition clearer.",
          "If recent devotional feedback includes Not relevant, choose a different allowed verse and a different spiritual angle than the rejected title."
        ]
      })
    }
  ];

  const estimatedInputCharacters = JSON.stringify(input).length;
  const responseParams: Record<string, unknown> = {
    model,
    max_output_tokens: outputTokenLimit,
    input,
    text: {
      format: {
        type: "json_schema",
        name: "daily_plan",
        schema: dailyPlanSchema,
        strict: true
      }
    }
  };

  if (promptId) {
    responseParams.prompt = {
      prompt_id: promptId,
      variables: promptVariables
    };
  }

  logger.info("Generating AI daily plan.", {
    uid,
    requestId: observability.requestId,
    generatedDate,
    model,
    outputTokenLimit,
    promptIdConfigured: Boolean(promptId),
    appCheckRequired: appCheckIsRequired(),
    forceRegenerate: request.forceRegenerate === true,
    firstWeekRampDay: ramp.day ?? null,
    recentHistoryCount: request.recentHistory?.length ?? 0,
    contentFeedbackCount: request.contentFeedback?.length ?? 0,
    rememberedMissionCount: recentPlanMemory.missionTitles.length,
    rememberedDevotionalCount: recentPlanMemory.devotionalTitles.length,
    estimatedInputCharacters
  });

  let aiResponse: { output_text: string; id?: string; usage?: unknown; _request_id?: string };
  try {
    aiResponse = await createOpenAIResponse(client, responseParams, uid, generatedDate, observability);
  } catch (error) {
    if (!promptId) {
      throw error;
    }

    logger.warn("Stored OpenAI prompt failed; retrying with inline daily plan prompt.", {
      uid,
      requestId: observability.requestId,
      generatedDate,
      error: error instanceof Error ? error.message : String(error)
    });
    delete responseParams.prompt;
    aiResponse = await createOpenAIResponse(client, responseParams, uid, generatedDate, observability);
  }

  const plan = JSON.parse(aiResponse.output_text) as DailyPlanResponse;
  plan.mission.difficulty = progression.targetDifficulty;
  plan.mission.durationMinutes = Math.min(
    120,
    Math.max(
      progression.minimumDurationMinutes + (ramp.durationBiasMinutes ?? 0),
      Math.round(plan.mission.durationMinutes || progression.minimumDurationMinutes)
    )
  );
  plan.mission.extraChallenges = uniqueNonEmpty([progression.missionPressure, ...(plan.mission.extraChallenges ?? [])]).slice(0, 5);
  plan.challenges = plan.challenges.map((challenge) => ({
    ...challenge,
    difficulty: progression.targetDifficulty,
    daysRemaining: Math.max(
      challengeWindowDays(progression.targetDifficulty),
      Math.round(challenge.daysRemaining || 1)
    ),
    targetCompletions: Math.min(
      14,
      Math.max(progression.targetChallengeCompletions, Math.round(challenge.targetCompletions || progression.targetChallengeCompletions))
    )
  }));
  const selectedVerse = exactVerse(plan.devotional.bibleVerse, verseOptions);
  const verse = resolvePublicDomainVerse(selectedVerse.reference);
  plan.devotional.bibleVerse = `${verse.reference} (${verse.translation})`;
  plan.devotional.verseText = verse.text;
  applyFirstWeekRampToPlan(plan, ramp, intent);

  logger.info("AI daily plan generated successfully.", {
    uid,
    requestId: observability.requestId,
    generatedDate,
    model,
    outputTokenLimit,
    promptIdConfigured: Boolean(promptId),
    category: plan.mission.category,
    durationMinutes: plan.mission.durationMinutes,
    firstWeekRampDay: ramp.day ?? null,
    cacheVersion: dailyPlanCacheVersion,
    bibleVerse: verse.reference,
    openAILatencyMs: observability.openAILatencyMs,
    openAIRequestId: observability.openAIRequestId,
    openAIUsage: observability.openAIUsage,
    outputCharacters: aiResponse.output_text.length
  });

  return plan;
}

function applyFirstWeekRampToPlan(
  plan: DailyPlanResponse,
  ramp: FirstWeekRampContext,
  intent: OnboardingIntent
): void {
  if (!ramp.active) {
    return;
  }

  plan.devotional.explanation = uniqueNonEmpty([
    plan.devotional.explanation,
    ramp.spiritualAngle ? `First-week focus: ${ramp.spiritualAngle}.` : ""
  ]).join(" ");
  plan.devotional.reflectionQuestion = ramp.reflectionFocus || plan.devotional.reflectionQuestion;
  plan.devotional.practicalAction = uniqueNonEmpty([
    ramp.practicalAction ?? "",
    plan.devotional.practicalAction
  ]).join(" ");

  plan.mission.summary = uniqueNonEmpty([
    ramp.missionCue ?? "",
    plan.mission.summary,
    ramp.personalizationRule ?? ""
  ]).join(" ");
  plan.mission.extraChallenges = uniqueNonEmpty([
    ramp.extraChallenge ?? "",
    ramp.objective ? `First-week objective: ${ramp.objective}` : "",
    ...(plan.mission.extraChallenges ?? [])
  ]).slice(0, 5);

  const firstWeekHabitID = `first-week-day-${ramp.day ?? 0}`;
  const habitTitle = ramp.habitFocus ? `First week: ${ramp.habitFocus}` : "First week rhythm";
  const habits = plan.habits ?? [];
  if (!habits.some((habit) => habit.id === firstWeekHabitID || habit.title.toLowerCase() === habitTitle.toLowerCase())) {
    plan.habits = [
      {
        id: firstWeekHabitID,
        title: habitTitle,
        cadence: "Daily",
        isEnabled: true
      },
      ...habits
    ].slice(0, 4);
  }

  if (plan.challenges.length > 0) {
    plan.challenges[0] = {
      ...plan.challenges[0],
      title: `${ramp.title ?? "First Week"} ${intent.challengeTitle}`.trim(),
      detail: uniqueNonEmpty([
        ramp.objective ?? "",
        intent.planSummary,
        plan.challenges[0].detail
      ]).join(" ")
    };
  }
}

async function createOpenAIResponse(
  client: OpenAI,
  responseParams: Record<string, unknown>,
  uid: string,
  generatedDate: string,
  observability: GenerationObservability
): Promise<{ output_text: string; id?: string; usage?: unknown; _request_id?: string }> {
  const attempts = openAIRetryCount() + 1;
  const timeoutMs = openAITimeoutMs();
  let lastError: unknown;

  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    const startedAt = Date.now();

    try {
      const response = await client.responses.create(responseParams as any, {
        signal: controller.signal
      } as any) as { output_text: string; id?: string; usage?: unknown; _request_id?: string };
      const latencyMs = Date.now() - startedAt;
      observability.openAILatencyMs = (observability.openAILatencyMs ?? 0) + latencyMs;
      observability.openAIRequestId = response._request_id ?? response.id;
      observability.openAIUsage = response.usage;

      logger.info("OpenAI daily plan attempt succeeded.", {
        uid,
        requestId: observability.requestId,
        generatedDate,
        model: observability.model,
        attempt,
        latencyMs,
        totalOpenAILatencyMs: observability.openAILatencyMs,
        openAIRequestId: observability.openAIRequestId,
        openAIUsage: observability.openAIUsage
      });

      return response;
    } catch (error) {
      const latencyMs = Date.now() - startedAt;
      observability.openAILatencyMs = (observability.openAILatencyMs ?? 0) + latencyMs;
      lastError = error;

      const retryable = shouldRetryOpenAIError(error, controller.signal.aborted);
      const retrying = retryable && attempt < attempts;

      logger.warn("OpenAI daily plan attempt failed.", {
        uid,
        requestId: observability.requestId,
        generatedDate,
        model: observability.model,
        attempt,
        attempts,
        latencyMs,
        totalOpenAILatencyMs: observability.openAILatencyMs,
        timedOut: controller.signal.aborted,
        retryable,
        retrying,
        status: openAIErrorStatus(error),
        code: openAIErrorCode(error),
        error: error instanceof Error ? error.message : String(error)
      });

      if (!retrying) {
        break;
      }

      await delay(250 * attempt + Math.floor(Math.random() * 150));
    } finally {
      clearTimeout(timeout);
    }
  }

  throw lastError instanceof Error ? lastError : new Error(String(lastError ?? "OpenAI request failed."));
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function shouldRetryOpenAIError(error: unknown, timedOut: boolean): boolean {
  if (timedOut) {
    return true;
  }
  const status = openAIErrorStatus(error);
  return status === 408 || status === 409 || status === 429 || status === 500 || status === 502 || status === 503 || status === 504;
}

function openAIErrorStatus(error: unknown): number | undefined {
  if (!error || typeof error !== "object") {
    return undefined;
  }
  const record = error as Record<string, unknown>;
  const status = record.status ?? record.statusCode;
  return typeof status === "number" ? status : undefined;
}

function openAIErrorCode(error: unknown): unknown {
  if (!error || typeof error !== "object") {
    return undefined;
  }
  return (error as Record<string, unknown>).code;
}

async function loadRecentPlanMemory(uid: string): Promise<RecentPlanMemory> {
  const emptyMemory: RecentPlanMemory = {
    missionTitles: [],
    missionSummaries: [],
    missionCategories: [],
    devotionalTitles: [],
    devotionalVerses: [],
    reflectionQuestions: [],
    practicalActions: []
  };

  try {
    const snapshot = await getFirestore()
      .collection("users")
      .doc(uid)
      .collection("state")
      .doc("current")
      .get();
    const payload = snapshot.get("payload");
    if (typeof payload !== "string" || payload.length === 0) {
      return emptyMemory;
    }

    const decoded = JSON.parse(Buffer.from(payload, "base64").toString("utf8")) as StoredSnapshot;
    const missions = sortedRecentItems(decoded.missions ?? []);
    const devotionals = sortedRecentItems(decoded.devotionals ?? []);

    return {
      missionTitles: uniqueNonEmpty(missions.map((mission) => cleanText(mission.title)).filter(Boolean)),
      missionSummaries: uniqueNonEmpty(missions.map((mission) => cleanText(mission.summary)).filter(Boolean)),
      missionCategories: uniqueNonEmpty(missions.map((mission) => cleanText(mission.category)).filter(Boolean)),
      devotionalTitles: uniqueNonEmpty(devotionals.map((devotional) => cleanText(devotional.title)).filter(Boolean)),
      devotionalVerses: uniqueNonEmpty(
        devotionals
          .map((devotional) => normalizedVerseReference(cleanText(devotional.bibleVerse)))
          .filter(Boolean)
      ),
      reflectionQuestions: uniqueNonEmpty(devotionals.map((devotional) => cleanText(devotional.reflectionQuestion)).filter(Boolean)),
      practicalActions: uniqueNonEmpty(devotionals.map((devotional) => cleanText(devotional.practicalAction)).filter(Boolean))
    };
  } catch (error) {
    logger.warn("Unable to load recent plan memory; generating without repetition context.", {
      uid,
      error: error instanceof Error ? error.message : String(error)
    });
    return emptyMemory;
  }
}

function sortedRecentItems<T extends { date?: string }>(items: T[]): T[] {
  return items
    .filter((item) => Object.values(item).some((value) => typeof value === "string" && value.trim().length > 0))
    .sort((left, right) => {
      const leftDate = Date.parse(left.date ?? "");
      const rightDate = Date.parse(right.date ?? "");
      return (Number.isFinite(rightDate) ? rightDate : 0) - (Number.isFinite(leftDate) ? leftDate : 0);
    })
    .slice(0, maxRecentPlanMemory);
}

function uniqueNonEmpty(values: string[]): string[] {
  const seen = new Set<string>();
  const output: string[] = [];
  for (const value of values) {
    const cleaned = cleanText(value);
    const key = cleaned.toLowerCase();
    if (!cleaned || seen.has(key)) {
      continue;
    }
    seen.add(key);
    output.push(cleaned);
    if (output.length >= maxRecentPlanMemory) {
      break;
    }
  }
  return output;
}

const publicDomainVerses: Record<string, string> = {
  "Colossians 3:23": "And whatever you do, work heartily, as for the Lord, and not for men,",
  "Proverbs 4:25": "Let your eyes look straight ahead. Fix your gaze directly before you.",
  "Matthew 6:22": "The lamp of the body is the eye. If therefore your eye is sound, your whole body will be full of light.",
  "Luke 16:10": "He who is faithful in a very little is faithful also in much. He who is dishonest in a very little is also dishonest in much.",
  "Proverbs 13:4": "The soul of the sluggard desires, and has nothing, but the desire of the diligent shall be fully satisfied.",
  "1 Corinthians 9:27": "but I beat my body and bring it into submission, lest by any means, after I have preached to others, I myself should be rejected.",
  "Galatians 6:9": "Let us not be weary in doing good, for we will reap in due season, if we don't give up.",
  "1 Corinthians 15:58": "Therefore, my beloved brothers, be steadfast, immovable, always abounding in the Lord's work, because you know that your labor is not in vain in the Lord.",
  "Hebrews 12:1": "Therefore let us also, seeing we are surrounded by so great a cloud of witnesses, lay aside every weight and the sin which so easily entangles us, and let us run with perseverance the race that is set before us,",
  "Psalm 51:10": "Create in me a clean heart, O God. Renew a right spirit within me.",
  "1 Corinthians 10:13": "No temptation has taken you except what is common to man. God is faithful, who will not allow you to be tempted above what you are able, but will with the temptation also make the way of escape, that you may be able to endure it.",
  "2 Timothy 2:22": "Flee from youthful lusts; but pursue righteousness, faith, love, and peace with those who call on the Lord out of a pure heart.",
  "1 Thessalonians 5:17": "Pray without ceasing.",
  "Philippians 4:6": "In nothing be anxious, but in everything, by prayer and petition with thanksgiving, let your requests be made known to God.",
  "Jeremiah 33:3": "'Call to me, and I will answer you, and will show you great and difficult things, which you don't know.'",
  "Psalm 119:105": "Your word is a lamp to my feet, and a light for my path.",
  "Joshua 1:8": "This book of the law shall not depart out of your mouth, but you shall meditate on it day and night, that you may observe to do according to all that is written in it; for then you shall make your way prosperous, and then you shall have good success.",
  "Psalm 119:11": "I have hidden your word in my heart, that I might not sin against you.",
  "Romans 12:2": "Don't be conformed to this world, but be transformed by the renewing of your mind, so that you may prove what is the good, well-pleasing, and perfect will of God.",
  "Proverbs 29:25": "The fear of man proves to be a snare, but whoever puts his trust in Yahweh is kept safe.",
  "Galatians 1:10": "For am I now seeking the favor of men, or of God? Or am I striving to please men? For if I were still pleasing men, I wouldn't be a servant of Christ."
};

function resolvePublicDomainVerse(reference: string): ResolvedVerse {
  return {
    reference,
    text: publicDomainVerses[reference] ?? publicDomainVerses["Colossians 3:23"],
    translation: "WEB"
  };
}

async function fallbackDailyPlan(request: DailyPlanRequest, uid: string): Promise<DailyPlanResponse> {
  const struggle = request.profile?.mainStruggle ?? "Discipline";
  const intent = onboardingIntent(request.profile);
  const category = intent.category;
  const generatedDate = generatedDateKey(request);
  const progression = progressionPlan(request.profile);
  const ramp = firstWeekRamp(request.profile, generatedDate);
  const regenerationSeed = request.forceRegenerate ?
    `|regen|${cleanText(request.regenerationReason) || "different-plan"}|${Date.now()}` :
    "";
  const recentPlanMemory = await loadRecentPlanMemory(uid);
  const verseReference = fallbackVerseReference(struggle, recentPlanMemory, `${uid}|${generatedDate}|verse${regenerationSeed}`);
  const verse = resolvePublicDomainVerse(verseReference);
  const devotional = pickLeastRecentOption(
    fallbackDevotionalOptions(struggle),
    recentPlanMemory.devotionalTitles,
    `${uid}|${generatedDate}|devotional${regenerationSeed}`
  );
  const mission = pickLeastRecentOption(
    fallbackMissionOptions(struggle),
    recentPlanMemory.missionTitles,
    `${uid}|${generatedDate}|mission${regenerationSeed}`
  );

  return {
    devotional: {
      title: devotional.title,
      bibleVerse: `${verse.reference} (${verse.translation})`,
      verseText: verse.text,
      explanation: `${devotional.explanation} This path is tuned toward ${intent.primaryGoal.toLowerCase()}, so today's devotional should become practical through ${intent.devotionalFocus}.`,
      reflectionQuestion: devotional.reflectionQuestion,
      practicalAction: uniqueNonEmpty([
        ramp.practicalAction ?? "",
        devotional.practicalAction,
        intent.missionCue
      ]).join(" ")
    },
    mission: {
      title: `${intent.challengeTitle}: ${mission.title}`,
      summary: uniqueNonEmpty([
        ramp.missionCue ?? "",
        mission.summary,
        intent.missionCue
      ]).join(" "),
      category,
      durationMinutes: Math.max(
        progression.minimumDurationMinutes,
        mission.durationMinutes + Math.max(0, progression.targetDifficulty - 2) * 5
      ),
      difficulty: progression.targetDifficulty,
      fallbackTitle: mission.fallbackTitle,
      fallbackSummary: mission.fallbackSummary,
      extraChallenges: uniqueNonEmpty([
        ramp.extraChallenge ?? "",
        progression.missionPressure,
        `Protect this goal: ${intent.primaryGoal}.`,
        `Repeat the mission near ${intent.reminderTime} tomorrow if possible.`,
        ...mission.extraChallenges
      ]).slice(0, 5)
    },
    habits: [
      {
        id: `goal-${intent.challengeTitle.toLowerCase().replace(/\s+/g, "-")}`,
        title: intent.habitTitle,
        cadence: "Daily",
        isEnabled: true
      },
      {
        id: "morning-prayer",
        title: "Morning prayer before phone",
        cadence: "Daily",
        isEnabled: true
      },
      {
        id: "evening-reflection",
        title: "Evening reflection",
        cadence: "Daily",
        isEnabled: true
      }
    ],
    challenges: [
      {
        id: `three-day-${intent.challengeTitle.toLowerCase().replace(/\s+/g, "-")}`,
        title: `${progression.growthBand} ${intent.challengeTitle}`,
        detail: `${intent.planSummary} Complete ${progression.targetChallengeCompletions} level ${progression.targetDifficulty} missions without dropping reflection.`,
        category: intent.category,
        daysRemaining: challengeWindowDays(progression.targetDifficulty),
        difficulty: progression.targetDifficulty,
        targetCompletions: progression.targetChallengeCompletions
      }
    ]
  };
}

function fallbackVerseReference(struggle: string, memory: RecentPlanMemory, seed: string): string {
  const options = verseOptionsByStruggle[struggle] ?? verseOptionsByStruggle.Discipline;
  const recentlyUsed = new Set(memory.devotionalVerses.map((verse) => normalizedVerseReference(verse)));
  const unusedOptions = options.filter((option) => !recentlyUsed.has(option.reference.toLowerCase()));
  const selectableOptions = unusedOptions.length > 0 ? unusedOptions : options;
  return selectableOptions[deterministicIndex(selectableOptions.length, seed)].reference;
}

function fallbackDevotionalOptions(struggle: string): FallbackDevotionalOption[] {
  const common = [
    {
      title: "A Smaller Obedience",
      explanation: "God often rebuilds discipline through a smaller act than we expected. Today does not need a dramatic reset to matter. The faithful move is to name the next obedient step, remove one obstacle, and do it with honesty before God. This is not about proving you are strong; it is about returning quickly, choosing the light you already have, and refusing to let yesterday decide the shape of today.",
      reflectionQuestion: "What small act of obedience would change the direction of this day?",
      practicalAction: "Write the next obedient step in one sentence, pray over it, and complete it before adding anything else."
    },
    {
      title: "Before the Drift",
      explanation: "Most compromise begins quietly before it becomes obvious. A day can drift through small delays, small excuses, and small moments of divided attention. Faithfulness interrupts that drift early. Give God the first honest response today instead of waiting until you feel ready. Choose one boundary, one action, and one moment of attention that protects who you are becoming.",
      reflectionQuestion: "Where does your day usually begin to drift?",
      practicalAction: "Put one boundary in place before the pressure shows up, then act on the mission immediately."
    },
    {
      title: "Attention as Worship",
      explanation: "Your attention is one of the most practical ways you worship. What you return to shapes what you trust. Today, discipline is not just finishing a task; it is giving God a real claim over your focus, your choices, and your first response when distraction pulls at you. Start with one clean block of obedience and let that become evidence of a quieter, stronger direction.",
      reflectionQuestion: "What keeps taking your attention before God gets your honesty?",
      practicalAction: "Take one minute of silent prayer, then begin the mission without checking another app."
    }
  ];

  if (struggle === "Prayer") {
    return [
      ...common,
      {
        title: "Return Before You Spiral",
        explanation: "Prayer becomes real when it interrupts the moment you would normally handle alone. You do not need perfect words to return to God. You need honesty, humility, and a willingness to come back before the pressure gets louder. Today, let prayer happen earlier than usual: before the scroll, before the reaction, before the excuse, and before the mission begins.",
        reflectionQuestion: "What pressure do you need to bring to God before it grows?",
        practicalAction: "Pray out loud for two minutes, naming one fear, one desire, and one obedient next step."
      }
    ];
  }

  if (struggle === "Scripture") {
    return [
      ...common,
      {
        title: "Read Until It Confronts",
        explanation: "Scripture is not meant to be background noise for a busy life. It gives enough light for the next decision and enough truth to interrupt what is false. Today, read slowly enough for one line to confront you. Do not measure success by how much you read. Measure it by whether you name one real response and obey it.",
        reflectionQuestion: "What decision needs to come under Scripture today?",
        practicalAction: "Read one short passage, write the sentence that confronts you, and take one action from it."
      }
    ];
  }

  return common;
}

function fallbackMissionOptions(struggle: string): FallbackMissionOption[] {
  const options: FallbackMissionOption[] = [
    {
      title: "Clear the First Obstacle",
      summary: "Spend 20 minutes removing the one physical or digital obstacle that keeps pulling you off mission, then begin one important task immediately after.",
      durationMinutes: 20,
      difficulty: 2,
      fallbackTitle: "Five-minute reset",
      fallbackSummary: "Clear one surface, close one distracting app, and write the next action.",
      extraChallenges: ["Pray before starting.", "Name the obstacle out loud.", "Write one sentence about what changed."]
    },
    {
      title: "One Visible Act",
      summary: "Choose one action that makes your faith visible in a quiet way: encourage someone, apologize, serve at home, or finish a responsibility without being asked.",
      durationMinutes: 25,
      difficulty: 3,
      fallbackTitle: "One honest message",
      fallbackSummary: "Send one sincere encouragement or apology, then write why you delayed it.",
      extraChallenges: ["Do it before entertainment.", "Keep the action private if possible.", "Reflect on what resistance came up."]
    },
    {
      title: "The First Hard Step",
      summary: "Set a 30-minute timer and work only on the task you have delayed the most. Success is starting, staying with it, and reaching a clear stopping point.",
      durationMinutes: 30,
      difficulty: 3,
      fallbackTitle: "Ten hard minutes",
      fallbackSummary: "Do ten minutes on the delayed task with every distraction closed.",
      extraChallenges: ["Write the task before the timer starts.", "Keep your phone out of reach.", "Log what you completed."]
    },
    {
      title: "Quiet Prayer Walk",
      summary: "Walk or sit somewhere away from your phone for 15 minutes and pray honestly through what you are avoiding, what you want, and what God is asking you to do next.",
      durationMinutes: 15,
      difficulty: 2,
      fallbackTitle: "Three honest prayers",
      fallbackSummary: "Pray one sentence for confession, one for help, and one for obedience.",
      extraChallenges: ["No audio during the walk.", "End with one concrete action.", "Write the next step when finished."]
    }
  ];

  if (struggle === "Focus") {
    return options;
  }

  if (struggle === "Purity / Self-control") {
    return [
      {
        title: "Move Before the Trigger",
        summary: "Identify your most likely trigger today, change your location before it hits, and replace the urge with a specific better action for 20 minutes.",
        durationMinutes: 20,
        difficulty: 3,
        fallbackTitle: "Change rooms now",
        fallbackSummary: "Move to a better environment, pray honestly, and do one replacement action for five minutes.",
        extraChallenges: ["Tell one trusted person your boundary.", "Remove one trigger source.", "Write the first warning sign you noticed."]
      },
      ...options
    ];
  }

  return options;
}

function pickLeastRecentOption<T extends { title: string }>(options: T[], recentTitles: string[], seed: string): T {
  const recent = new Set(recentTitles.map((title) => title.toLowerCase()));
  const startIndex = deterministicIndex(options.length, seed);
  for (let offset = 0; offset < options.length; offset += 1) {
    const option = options[(startIndex + offset) % options.length];
    if (!recent.has(option.title.toLowerCase())) {
      return option;
    }
  }
  return options[startIndex];
}

function deterministicIndex(count: number, seed: string): number {
  if (count <= 1) {
    return 0;
  }
  const hash = seed.split("").reduce((value, character) => {
    return ((value << 5) - value + character.charCodeAt(0)) >>> 0;
  }, 2166136261);
  return hash % count;
}

function exactVerse(reference: string, options: VerseOption[]): VerseOption {
  const normalizedReference = normalizedVerseReference(reference);
  return options.find((option) => option.reference.toLowerCase() === normalizedReference) ?? options[0];
}

function normalizedVerseReference(reference: string): string {
  return reference
    .replace(/\s*\((web|nlt|kjv|niv|esv)\)\s*$/i, "")
    .trim()
    .toLowerCase();
}
