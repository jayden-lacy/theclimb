import OpenAI from "openai";
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const openAIKey = defineSecret("OPENAI_API_KEY");
const defaultModel = "gpt-5.4-mini";
const defaultDailyLimit = 6;
const defaultMaxOutputTokens = 1800;
const minimumMaxOutputTokens = 800;
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
  };
  recentHistory?: Array<{
    hardestPart?: string;
    lessonLearned?: string;
    effortRating?: number;
    improvementPlan?: string;
    mood?: string;
    failureReason?: string | null;
  }>;
  generatedAt?: string;
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
  translation: "NLT" | "Modern";
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
    if (request.method !== "POST") {
      response.status(405).json({ error: "Use POST." });
      return;
    }

    try {
      const uid = await verifyFirebaseUser(request.get("x-firebase-auth"), request.get("authorization"));
      await verifyAppCheckToken(request.get("x-firebase-appcheck"), uid);
      const body = sanitizedDailyPlanRequest(request.body as DailyPlanRequest);
      await enforceRateLimit(uid);

      let plan: DailyPlanResponse;
      try {
        plan = await createDailyPlan(body, uid);
      } catch (error) {
        logger.error("AI daily plan generation failed; returning fallback plan.", {
          uid,
          error: error instanceof Error ? error.message : String(error)
        });
        plan = await fallbackDailyPlan(body, uid);
      }

      response.status(200).json(plan);
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const severity = status >= 500 ? logger.error : logger.warn;
      severity("generateDailyPlan request rejected.", {
        status,
        error: error instanceof Error ? error.message : String(error)
      });
      response.status(status).json({
        error: error instanceof Error ? error.message : "Unable to generate plan."
      });
    }
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

function appCheckIsRequired(): boolean {
  const value = (process.env.ENFORCE_APP_CHECK ?? "").toLowerCase();
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

async function verifyFirebaseUser(firebaseAuthHeader?: string, authorizationHeader?: string): Promise<string> {
  const prefix = "Bearer ";
  const token = firebaseAuthHeader ?? (
    authorizationHeader?.startsWith(prefix) ? authorizationHeader.slice(prefix.length) : undefined
  );
  if (!token) {
    throw new HTTPError(401, "Sign in before generating a daily plan.");
  }

  try {
    const decodedToken = await getAuth().verifyIdToken(token);
    return decodedToken.uid;
  } catch {
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
      notificationMinute: profile.notificationMinute === undefined ? 0 : cleanNumber(profile.notificationMinute, 0, 59)
    },
    recentHistory: (request.recentHistory ?? []).slice(0, maxRecentHistory).map((entry) => ({
      hardestPart: cleanText(entry.hardestPart),
      lessonLearned: cleanText(entry.lessonLearned),
      effortRating: cleanNumber(entry.effortRating, 1, 5),
      improvementPlan: cleanText(entry.improvementPlan),
      mood: cleanText(entry.mood),
      failureReason: entry.failureReason ? cleanText(entry.failureReason) : null
    })),
    generatedAt: cleanText(request.generatedAt)
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
} {
  const ovr = cleanNumber(profile?.ovrScore, 0, 100);
  const streak = cleanNumber(profile?.currentStreak, 0, 3650);
  const recoveryStreak = cleanNumber(profile?.recoveryStreak, 0, 3650);
  const streakGoal = cleanNumber(profile?.streakGoal, 7, 365);
  const ageGroup = cleanText(profile?.ageGroup);
  const ovrLevel = ovrDifficultyStep(ovr);
  const streakStep = streak >= 14 ? 2 : streak >= 5 ? 1 : 0;
  const ambitionStep = streakGoal >= 60 ? 1 : 0;
  const starterAdjustment = streakGoal <= 14 && ovr < 60 ? -1 : 0;
  const recoveryAdjustment = streak === 0 && recoveryStreak > 0 ? -1 : 0;
  const targetDifficulty = Math.min(5, Math.max(1, ovrLevel + streakStep + ambitionStep + starterAdjustment + recoveryAdjustment));

  return {
    targetDifficulty,
    targetChallengeCompletions: requiredChallengeCompletions(targetDifficulty),
    minimumDurationMinutes: minimumMissionMinutes(targetDifficulty, ageGroup),
    missionPressure: missionPressureLine(targetDifficulty),
    growthBand: ovr >= 90 ? "mastery" : ovr >= 75 ? "advanced" : ovr >= 60 ? "building" : "foundation"
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
  const base = ageGroup === "Teen" ? 15 : ageGroup === "College" ? 20 : 25;
  return Math.min(90, base + Math.max(0, difficulty - 1) * 10);
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

async function createDailyPlan(request: DailyPlanRequest, uid: string): Promise<DailyPlanResponse> {
  const client = new OpenAI({ apiKey: openAIKey.value() });
  const struggle = request.profile?.mainStruggle ?? "Discipline";
  const verseOptions = verseOptionsByStruggle[struggle] ?? verseOptionsByStruggle.Discipline;
  const generatedDate = request.generatedAt?.slice(0, 10) ?? new Date().toISOString().slice(0, 10);
  const recentPlanMemory = await loadRecentPlanMemory(uid);
  const recentlyUsedVerses = recentPlanMemory.devotionalVerses
    .map(normalizedVerseReference)
    .filter(Boolean);
  const unusedAllowedVerses = verseOptions
    .map((verse) => verse.reference)
    .filter((reference) => !recentlyUsedVerses.includes(reference.toLowerCase()));
  const model = process.env.OPENAI_MODEL ?? defaultModel;
  const outputTokenLimit = maxOutputTokens();
  const promptId = process.env.OPENAI_DAILY_PLAN_PROMPT_ID?.trim();
  const progression = progressionPlan(request.profile);
  const intent = onboardingIntent(request.profile);
  const promptVariables = {
    profile: JSON.stringify(request.profile ?? {}),
    onboardingIntent: JSON.stringify(intent),
    recentHistory: JSON.stringify(request.recentHistory ?? []),
    recentPlanMemory: JSON.stringify(recentPlanMemory),
    generatedDate,
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
        "Use one of the provided NLT references exactly for bibleVerse; set verseText to an empty string because the server will fetch the licensed NLT text.",
        "Make the devotional explanation 140-220 words and tie it directly to the user's struggle.",
        "Make the mission concrete, measurable, and possible today.",
        "Use onboardingIntent as the main personalization contract. The mission, practicalAction, at least one habit, and the primary challenge must directly reflect onboardingIntent.primaryGoal, onboardingIntent.missionCue, and onboardingIntent.challengeTitle.",
        "If onboardingIntent.category differs from the struggle category, prefer onboardingIntent.category for the primary mission and use the struggle as the pressure point being trained.",
        "Use onboardingIntent.reminderTime and streakGoal when a same-time repeat or streak rhythm is relevant.",
        "Use the provided progression object. Mission difficulty must match targetDifficulty. Duration must be at least minimumDurationMinutes. Include missionPressure as one of the extraChallenges.",
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
        recentPlanMemory,
        generatedAt: request.generatedAt,
        generatedDate,
        onboardingIntent: intent,
        allowedVerses: verseOptions.map((verse) => verse.reference),
        preferredVerses: unusedAllowedVerses.length > 0 ? unusedAllowedVerses : verseOptions.map((verse) => verse.reference),
        recentlyUsedVerses,
        progression,
        distinctnessRules: [
          "Choose a different mission mechanic than the most recent mission.",
          "Choose a different title structure than the last three titles.",
          "Avoid repeating words like quiet, focused, phone-away, reset, or today if those appeared recently.",
          "Make the fallback mission different from the primary mission, not just shorter."
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
    generatedDate,
    model,
    outputTokenLimit,
    promptIdConfigured: Boolean(promptId),
    appCheckRequired: appCheckIsRequired(),
    recentHistoryCount: request.recentHistory?.length ?? 0,
    rememberedMissionCount: recentPlanMemory.missionTitles.length,
    rememberedDevotionalCount: recentPlanMemory.devotionalTitles.length,
    estimatedInputCharacters
  });

  let aiResponse: { output_text: string };
  try {
    aiResponse = await client.responses.create(responseParams as any);
  } catch (error) {
    if (!promptId) {
      throw error;
    }

    logger.warn("Stored OpenAI prompt failed; retrying with inline daily plan prompt.", {
      uid,
      error: error instanceof Error ? error.message : String(error)
    });
    delete responseParams.prompt;
    aiResponse = await client.responses.create(responseParams as any);
  }

  const plan = JSON.parse(aiResponse.output_text) as DailyPlanResponse;
  plan.mission.difficulty = progression.targetDifficulty;
  plan.mission.durationMinutes = Math.min(
    120,
    Math.max(progression.minimumDurationMinutes, Math.round(plan.mission.durationMinutes || progression.minimumDurationMinutes))
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
  const nltVerse = await fetchNLTVerse(selectedVerse.reference, uid);
  plan.devotional.bibleVerse = `${nltVerse.reference} (${nltVerse.translation})`;
  plan.devotional.verseText = nltVerse.text;

  logger.info("AI daily plan generated successfully.", {
    uid,
    generatedDate,
    model,
    outputTokenLimit,
    promptIdConfigured: Boolean(promptId),
    category: plan.mission.category,
    durationMinutes: plan.mission.durationMinutes,
    bibleVerse: nltVerse.reference,
    outputCharacters: aiResponse.output_text.length
  });

  return plan;
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

async function fetchNLTVerse(reference: string, uid: string): Promise<ResolvedVerse> {
  const params = new URLSearchParams({
    ref: reference,
    version: "NLT"
  });
  const apiKey = process.env.NLT_API_KEY?.trim();
  if (apiKey) {
    params.set("key", apiKey);
  }

  try {
    const response = await fetch(`https://api.nlt.to/api/passages?${params.toString()}`);
    if (!response.ok) {
      throw new Error(`NLT API returned ${response.status}.`);
    }

    const html = await response.text();
    const text = extractNLTVerseText(html);
    if (!text) {
      throw new Error("NLT API response did not include verse text.");
    }

    return {
      reference,
      text,
      translation: "NLT"
    };
  } catch (error) {
    logger.warn("NLT verse lookup failed; using modern fallback verse summary.", {
      uid,
      reference,
      error: error instanceof Error ? error.message : String(error)
    });
    return {
      reference,
      text: modernVerseSummary(reference),
      translation: "Modern"
    };
  }
}

function extractNLTVerseText(html: string): string {
  const verseExportMatch = html.match(/<verse_export\b[^>]*>([\s\S]*?)<\/verse_export>/i);
  const rawVerseHtml = verseExportMatch?.[1] ?? "";
  return decodeHTMLEntities(
    rawVerseHtml
      .replace(/<span\b[^>]*class=["']vn["'][^>]*>[\s\S]*?<\/span>/gi, " ")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
      .trim()
  );
}

function decodeHTMLEntities(value: string): string {
  return value
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&#(\d+);/g, (_, codePoint: string) => String.fromCodePoint(Number(codePoint)))
    .replace(/\s+/g, " ")
    .trim();
}

function modernVerseSummary(reference: string): string {
  switch (reference) {
  case "Colossians 3:23":
    return "Work with your whole heart as an offering to God, not as performance for people.";
  case "Proverbs 4:25":
    return "Keep your eyes fixed ahead and refuse the pull of scattered attention.";
  case "Matthew 6:22":
    return "A clear eye shapes a clear life; protect what you give your attention to.";
  case "Luke 16:10":
    return "Faithfulness in small things trains the heart for larger responsibility.";
  case "Proverbs 13:4":
    return "Desire alone does not build a life; diligence turns intention into fruit.";
  case "1 Corinthians 9:27":
    return "Discipline means training your body to serve your calling instead of ruling it.";
  case "Galatians 6:9":
    return "Do not quit the good work; endurance carries the harvest you cannot see yet.";
  case "1 Corinthians 15:58":
    return "Stand firm and keep giving yourself to the work God has placed before you.";
  case "Hebrews 12:1":
    return "Run your assigned race with endurance, laying aside what slows obedience.";
  case "Psalm 51:10":
    return "Ask God for a clean heart and a steady spirit, not just better behavior.";
  case "1 Corinthians 10:13":
    return "God is faithful in temptation and provides a way to stand instead of collapse.";
  case "2 Timothy 2:22":
    return "Run from what corrupts you and pursue what forms faith, love, and peace.";
  case "1 Thessalonians 5:17":
    return "Keep returning to prayer until dependence becomes your rhythm.";
  case "Philippians 4:6":
    return "Bring anxiety to God through honest prayer, gratitude, and specific requests.";
  case "Jeremiah 33:3":
    return "Call to God with expectation; He can reveal what you cannot produce alone.";
  case "Psalm 119:105":
    return "God’s Word gives enough light for the next obedient step.";
  case "Joshua 1:8":
    return "Keep Scripture close, meditate on it, and let obedience shape your path.";
  case "Psalm 119:11":
    return "Store God’s Word in your heart so temptation meets truth first.";
  case "Romans 12:2":
    return "Do not be shaped by the world’s pattern; let God renew the way you think.";
  case "Proverbs 29:25":
    return "Fear of people traps the heart, but trust in God gives steadiness.";
  case "Galatians 1:10":
    return "Choose pleasing God over performing for people when pressure starts talking.";
  default:
    return "Work with your whole heart as an offering to God, not as performance for people.";
  }
}

async function fallbackDailyPlan(request: DailyPlanRequest, uid: string): Promise<DailyPlanResponse> {
  const struggle = request.profile?.mainStruggle ?? "Discipline";
  const intent = onboardingIntent(request.profile);
  const category = intent.category;
  const generatedDate = request.generatedAt?.slice(0, 10) ?? new Date().toISOString().slice(0, 10);
  const progression = progressionPlan(request.profile);
  const recentPlanMemory = await loadRecentPlanMemory(uid);
  const verseReference = fallbackVerseReference(struggle, recentPlanMemory, `${uid}|${generatedDate}|verse`);
  const verse = await fetchNLTVerse(verseReference, uid);
  const devotional = pickLeastRecentOption(
    fallbackDevotionalOptions(struggle),
    recentPlanMemory.devotionalTitles,
    `${uid}|${generatedDate}|devotional`
  );
  const mission = pickLeastRecentOption(
    fallbackMissionOptions(struggle),
    recentPlanMemory.missionTitles,
    `${uid}|${generatedDate}|mission`
  );

  return {
    devotional: {
      title: devotional.title,
      bibleVerse: `${verse.reference} (${verse.translation})`,
      verseText: verse.text,
      explanation: `${devotional.explanation} This path is tuned toward ${intent.primaryGoal.toLowerCase()}, so today's devotional should become practical through ${intent.devotionalFocus}.`,
      reflectionQuestion: devotional.reflectionQuestion,
      practicalAction: `${devotional.practicalAction} ${intent.missionCue}`
    },
    mission: {
      title: `${intent.challengeTitle}: ${mission.title}`,
      summary: `${mission.summary} ${intent.missionCue}`,
      category,
      durationMinutes: Math.max(
        progression.minimumDurationMinutes,
        mission.durationMinutes + Math.max(0, progression.targetDifficulty - 2) * 5
      ),
      difficulty: progression.targetDifficulty,
      fallbackTitle: mission.fallbackTitle,
      fallbackSummary: mission.fallbackSummary,
      extraChallenges: uniqueNonEmpty([
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
    .replace(/\s*\((nlt|kjv|niv|esv)\)\s*$/i, "")
    .trim()
    .toLowerCase();
}
