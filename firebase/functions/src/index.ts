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
const maxRecentHistory = 8;
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
  }>;
};

type VerseOption = {
  reference: string;
  text: string;
};

const verseOptionsByStruggle: Record<string, VerseOption[]> = {
  Focus: [
    {
      reference: "Colossians 3:23",
      text: "\"And whatsoever ye do, do it heartily, as to the Lord, and not unto men.\""
    },
    {
      reference: "Proverbs 4:25",
      text: "\"Let thine eyes look right on, and let thine eyelids look straight before thee.\""
    },
    {
      reference: "Matthew 6:22",
      text: "\"The light of the body is the eye: if therefore thine eye be single, thy whole body shall be full of light.\""
    }
  ],
  Discipline: [
    {
      reference: "Luke 16:10",
      text: "\"He that is faithful in that which is least is faithful also in much: and he that is unjust in the least is unjust also in much.\""
    },
    {
      reference: "Proverbs 13:4",
      text: "\"The soul of the sluggard desireth, and hath nothing: but the soul of the diligent shall be made fat.\""
    },
    {
      reference: "1 Corinthians 9:27",
      text: "\"But I keep under my body, and bring it into subjection.\""
    }
  ],
  Consistency: [
    {
      reference: "Galatians 6:9",
      text: "\"And let us not be weary in well doing: for in due season we shall reap, if we faint not.\""
    },
    {
      reference: "1 Corinthians 15:58",
      text: "\"Therefore, my beloved brethren, be ye stedfast, unmoveable, always abounding in the work of the Lord.\""
    },
    {
      reference: "Hebrews 12:1",
      text: "\"Let us run with patience the race that is set before us.\""
    }
  ],
  "Purity / Self-control": [
    {
      reference: "Psalm 51:10",
      text: "\"Create in me a clean heart, O God; and renew a right spirit within me.\""
    },
    {
      reference: "1 Corinthians 10:13",
      text: "\"God is faithful, who will not suffer you to be tempted above that ye are able.\""
    },
    {
      reference: "2 Timothy 2:22",
      text: "\"Flee also youthful lusts: but follow righteousness, faith, charity, peace.\""
    }
  ],
  Prayer: [
    {
      reference: "1 Thessalonians 5:17",
      text: "\"Pray without ceasing.\""
    },
    {
      reference: "Philippians 4:6",
      text: "\"Be careful for nothing; but in every thing by prayer and supplication with thanksgiving let your requests be made known unto God.\""
    },
    {
      reference: "Jeremiah 33:3",
      text: "\"Call unto me, and I will answer thee, and shew thee great and mighty things, which thou knowest not.\""
    }
  ],
  Scripture: [
    {
      reference: "Psalm 119:105",
      text: "\"Thy word is a lamp unto my feet, and a light unto my path.\""
    },
    {
      reference: "Joshua 1:8",
      text: "\"This book of the law shall not depart out of thy mouth; but thou shalt meditate therein day and night.\""
    },
    {
      reference: "Psalm 119:11",
      text: "\"Thy word have I hid in mine heart, that I might not sin against thee.\""
    }
  ],
  "Social Pressure": [
    {
      reference: "Romans 12:2",
      text: "\"And be not conformed to this world: but be ye transformed by the renewing of your mind.\""
    },
    {
      reference: "Proverbs 29:25",
      text: "\"The fear of man bringeth a snare: but whoso putteth his trust in the LORD shall be safe.\""
    },
    {
      reference: "Galatians 1:10",
      text: "\"For do I now persuade men, or God? or do I seek to please men?\""
    }
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
        required: ["id", "title", "detail", "category", "daysRemaining"],
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          detail: { type: "string" },
          category: {
            type: "string",
            enum: ["Focus", "Faith", "Discipline", "Self-control", "Social"]
          },
          daysRemaining: { type: "integer", minimum: 1, maximum: 30 }
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
        plan = fallbackDailyPlan(body);
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
  return process.env.ENFORCE_APP_CHECK === "true";
}

function dailyLimit(): number {
  const parsed = Number.parseInt(process.env.AI_DAILY_LIMIT_PER_USER ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : defaultDailyLimit;
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
  if (!appCheckHeader) {
    if (appCheckIsRequired()) {
      throw new HTTPError(401, "Update the app before generating a daily plan.");
    }
    return;
  }

  try {
    await getAppCheck().verifyToken(appCheckHeader);
  } catch (error) {
    if (appCheckIsRequired()) {
      throw new HTTPError(401, "Unable to verify this app install.");
    }
    logger.warn("Invalid App Check token soft-allowed because ENFORCE_APP_CHECK is false.", {
      uid,
      error: error instanceof Error ? error.message : String(error)
    });
  }
}

async function enforceRateLimit(uid: string): Promise<void> {
  const dateKey = new Date().toISOString().slice(0, 10);
  const document = getFirestore().collection("aiUsage").doc(`${uid}_${dateKey}`);
  const limit = dailyLimit();

  await getFirestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(document);
    const currentCount = snapshot.exists ? Number(snapshot.get("count") ?? 0) : 0;
    if (currentCount >= limit) {
      throw new HTTPError(429, "Daily AI generation limit reached. Try again tomorrow.");
    }

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
      ovrScore: cleanNumber(profile.ovrScore, 0, 100)
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

async function createDailyPlan(request: DailyPlanRequest, uid: string): Promise<DailyPlanResponse> {
  const client = new OpenAI({ apiKey: openAIKey.value() });
  const struggle = request.profile?.mainStruggle ?? "Discipline";
  const verseOptions = verseOptionsByStruggle[struggle] ?? verseOptionsByStruggle.Discipline;
  const generatedDate = request.generatedAt?.slice(0, 10) ?? new Date().toISOString().slice(0, 10);
  const model = process.env.OPENAI_MODEL ?? defaultModel;
  const promptId = process.env.OPENAI_DAILY_PLAN_PROMPT_ID?.trim();
  const promptVariables = {
    profile: JSON.stringify(request.profile ?? {}),
    recentHistory: JSON.stringify(request.recentHistory ?? []),
    generatedDate,
    allowedVerses: JSON.stringify(verseOptions)
  };
  const input = [
    {
      role: "system",
      content: [
        "You generate daily Christian discipline plans for The Climb.",
        "Write in a calm, serious, modern tone for teens and young adults.",
        "Return only the requested JSON shape.",
        "Use one of the provided public-domain KJV verses exactly; do not invent or paraphrase Bible text.",
        "Make the devotional explanation 140-220 words and tie it directly to the user's struggle.",
        "Make the mission concrete, measurable, and possible today.",
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
        generatedAt: request.generatedAt,
        generatedDate,
        allowedVerses: verseOptions
      })
    }
  ];

  const responseParams: Record<string, unknown> = {
    model,
    max_output_tokens: 1800,
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
    promptIdConfigured: Boolean(promptId)
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
  const verse = exactVerse(plan.devotional.bibleVerse, verseOptions);
  plan.devotional.bibleVerse = verse.reference;
  plan.devotional.verseText = verse.text;

  return plan;
}

function fallbackDailyPlan(request: DailyPlanRequest): DailyPlanResponse {
  const struggle = request.profile?.mainStruggle ?? "Discipline";
  const category = fallbackCategory(struggle);
  const verse = (verseOptionsByStruggle[struggle] ?? verseOptionsByStruggle.Discipline)[0];

  return {
    devotional: {
      title: "Faithful With Today",
      bibleVerse: verse.reference,
      verseText: verse.text,
      explanation: [
        "Growth today does not need to be loud to be real.",
        "The next faithful step is usually simple: obey what is in front of you, remove one distraction, and finish one thing with your whole heart.",
        "This moment is an invitation to practice discipline without performing for anyone.",
        "Give God your attention in the ordinary work of today, and let consistency become worship instead of pressure."
      ].join(" "),
      reflectionQuestion: "What one distraction do you need to surrender before you start?",
      practicalAction: "Choose one focused block today, put your phone away, pray for one minute, then finish the mission."
    },
    mission: {
      title: "One focused hour",
      summary: "Put your phone away and complete one important task with no social media, no scrolling, and no multitasking.",
      category,
      durationMinutes: 60,
      difficulty: 3,
      fallbackTitle: "Ten minutes of obedience",
      fallbackSummary: "If the full mission is too much, do ten focused minutes with your phone out of reach.",
      extraChallenges: [
        "Pray before starting.",
        "Write down what tempted you to quit.",
        "Tell your accountability partner when you finish."
      ]
    },
    habits: [
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
        id: "three-day-focus",
        title: "Three-day focus reset",
        detail: "Complete one phone-free focus block for three straight days.",
        category: "Focus",
        daysRemaining: 3
      }
    ]
  };
}

function fallbackCategory(struggle: string): DailyPlanResponse["mission"]["category"] {
  if (struggle === "Prayer" || struggle === "Scripture") {
    return "Faith";
  }
  if (struggle === "Purity / Self-control") {
    return "Self-control";
  }
  if (struggle === "Social Pressure") {
    return "Social";
  }
  if (struggle === "Focus") {
    return "Focus";
  }
  return "Discipline";
}

function exactVerse(reference: string, options: VerseOption[]): VerseOption {
  const normalizedReference = reference.trim().toLowerCase();
  return options.find((option) => option.reference.toLowerCase() === normalizedReference) ?? options[0];
}
