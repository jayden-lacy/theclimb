#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const functionsRoot = join(scriptDir, "..");
const source = readFileSync(join(functionsRoot, "src", "index.ts"), "utf8");

const categories = new Set(["Focus", "Faith", "Discipline", "Self-control", "Social"]);
const maxRecentPlanMemory = 10;
const maxGoals = 5;
const maxRecentHistory = 8;
const maxTextLength = 600;

const validDailyPlanFixture = {
  devotional: {
    title: "Attention Before Reaction",
    bibleVerse: "Colossians 3:23",
    verseText: "",
    explanation: "Give the first focused block of the day to obedience instead of reaction.",
    reflectionQuestion: "What will get your first honest yes today?",
    practicalAction: "Pray for one minute, write the next action, and begin before opening another app."
  },
  mission: {
    title: "Phone Boundary Focus Block",
    summary: "Place the phone outside the room and finish one 25-minute task with a written stopping point.",
    category: "Focus",
    durationMinutes: 25,
    difficulty: 3,
    fallbackTitle: "Ten-Minute Phone Boundary",
    fallbackSummary: "Move the phone away and complete ten focused minutes.",
    extraChallenges: [
      "Level 3: finish the mission and add one accountability check-in afterward.",
      "Send your result to your accountability partner."
    ]
  },
  habits: [
    {
      id: "phone-away-before-mission",
      title: "Phone away before mission",
      cadence: "Daily",
      isEnabled: true
    }
  ],
  challenges: [
    {
      id: "deep-work",
      title: "Deep Work",
      detail: "Complete seven protected focus blocks before the challenge expires.",
      category: "Focus",
      daysRemaining: 10,
      difficulty: 3,
      targetCompletions: 7
    }
  ]
};

const requestFixture = {
  profile: {
    ageGroup: "College",
    goals: [
      "Reduce phone use",
      "Improve focus",
      "Grow closer to God",
      "Build discipline",
      "Become consistent",
      "This extra goal should be trimmed"
    ],
    mainStruggle: "Focus",
    currentStreak: 4.7,
    longestStreak: "19",
    recoveryStreak: -2,
    ovrScore: 72,
    streakGoal: 90,
    notificationHour: 25,
    notificationMinute: "12",
    onboarding: {
      spiritualStartingPoint: "growing",
      dailyCommitmentMinutes: 10,
      preferredTimeWindow: "evening",
      primaryObstacle: "My phone pulls me away",
      whyStarted: "I want to become more disciplined",
      firstStepCompletedAt: "2026-06-27T14:00:00.000Z",
      initialMilestoneDays: 3
    }
  },
  recentHistory: Array.from({ length: 10 }, (_, index) => ({
    hardestPart: `Hardest part ${index}`,
    lessonLearned: `Lesson ${index}`,
    effortRating: index + 1,
    improvementPlan: `Plan ${index}`,
    mood: "Steady",
    failureReason: index % 2 === 0 ? "Distracted" : null
  })),
  generatedAt: "2026-06-27T14:30:00.000Z"
};

const storedSnapshotFixture = {
  missions: [
    {
      date: "2026-06-25",
      title: "Phone Boundary Focus Block",
      summary: "Move the phone away and finish the first task.",
      category: "Focus"
    },
    {
      date: "2026-06-27",
      title: "Delayed Task Sprint",
      summary: "Start the avoided task before entertainment.",
      category: "Discipline"
    },
    {
      date: "2026-06-26",
      title: "Phone Boundary Focus Block",
      summary: "Duplicate title should collapse.",
      category: "Focus"
    }
  ],
  devotionals: [
    {
      date: "2026-06-27",
      title: "Faithful With Attention",
      bibleVerse: "Colossians 3:23 (WEB)",
      reflectionQuestion: "Where does your attention drift first?",
      practicalAction: "Begin the mission before another app."
    },
    {
      date: "2026-06-26",
      title: "Faithful With Attention",
      bibleVerse: "Proverbs 4:25 (WEB)",
      reflectionQuestion: "Duplicate title should collapse.",
      practicalAction: "Place your phone outside the room."
    }
  ]
};

function validateDailyPlan(plan) {
  const errors = [];
  requireObject(plan, "plan", ["devotional", "mission", "habits", "challenges"], errors);
  validateDevotional(plan.devotional, errors);
  validateMission(plan.mission, errors);
  validateHabits(plan.habits, errors);
  validateChallenges(plan.challenges, errors);
  return errors;
}

function validateDevotional(devotional, errors) {
  if (!requireObject(devotional, "devotional", [
    "title",
    "bibleVerse",
    "verseText",
    "explanation",
    "reflectionQuestion",
    "practicalAction"
  ], errors)) {
    return;
  }

  for (const field of ["title", "bibleVerse", "verseText", "explanation", "reflectionQuestion", "practicalAction"]) {
    requireString(devotional[field], `devotional.${field}`, errors);
  }
}

function validateMission(mission, errors) {
  if (!requireObject(mission, "mission", [
    "title",
    "summary",
    "category",
    "durationMinutes",
    "difficulty",
    "fallbackTitle",
    "fallbackSummary",
    "extraChallenges"
  ], errors)) {
    return;
  }

  for (const field of ["title", "summary", "fallbackTitle", "fallbackSummary"]) {
    requireString(mission[field], `mission.${field}`, errors);
  }
  requireCategory(mission.category, "mission.category", errors);
  requireIntegerInRange(mission.durationMinutes, "mission.durationMinutes", 5, 120, errors);
  requireIntegerInRange(mission.difficulty, "mission.difficulty", 1, 5, errors);
  requireStringArray(mission.extraChallenges, "mission.extraChallenges", errors);
}

function validateHabits(habits, errors) {
  if (!Array.isArray(habits)) {
    errors.push("habits must be an array.");
    return;
  }

  habits.forEach((habit, index) => {
    if (!requireObject(habit, `habits[${index}]`, ["id", "title", "cadence", "isEnabled"], errors)) {
      return;
    }
    for (const field of ["id", "title", "cadence"]) {
      requireString(habit[field], `habits[${index}].${field}`, errors);
    }
    if (typeof habit.isEnabled !== "boolean") {
      errors.push(`habits[${index}].isEnabled must be a boolean.`);
    }
  });
}

function validateChallenges(challenges, errors) {
  if (!Array.isArray(challenges)) {
    errors.push("challenges must be an array.");
    return;
  }

  challenges.forEach((challenge, index) => {
    if (!requireObject(challenge, `challenges[${index}]`, [
      "id",
      "title",
      "detail",
      "category",
      "daysRemaining",
      "difficulty",
      "targetCompletions"
    ], errors)) {
      return;
    }

    for (const field of ["id", "title", "detail"]) {
      requireString(challenge[field], `challenges[${index}].${field}`, errors);
    }
    requireCategory(challenge.category, `challenges[${index}].category`, errors);
    requireIntegerInRange(challenge.daysRemaining, `challenges[${index}].daysRemaining`, 1, 30, errors);
    requireIntegerInRange(challenge.difficulty, `challenges[${index}].difficulty`, 1, 5, errors);
    requireIntegerInRange(challenge.targetCompletions, `challenges[${index}].targetCompletions`, 1, 14, errors);
  });
}

function requireObject(value, label, requiredKeys, errors) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    errors.push(`${label} must be an object.`);
    return false;
  }

  const keys = Object.keys(value);
  const allowed = new Set(requiredKeys);
  for (const key of requiredKeys) {
    if (!keys.includes(key)) {
      errors.push(`${label}.${key} is required.`);
    }
  }
  for (const key of keys) {
    if (!allowed.has(key)) {
      errors.push(`${label}.${key} is not allowed by the schema.`);
    }
  }

  return true;
}

function requireString(value, label, errors) {
  if (typeof value !== "string") {
    errors.push(`${label} must be a string.`);
  }
}

function requireStringArray(value, label, errors) {
  if (!Array.isArray(value)) {
    errors.push(`${label} must be an array.`);
    return;
  }
  value.forEach((entry, index) => requireString(entry, `${label}[${index}]`, errors));
}

function requireCategory(value, label, errors) {
  if (!categories.has(value)) {
    errors.push(`${label} must be one of ${Array.from(categories).join(", ")}.`);
  }
}

function requireIntegerInRange(value, label, minimum, maximum, errors) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    errors.push(`${label} must be an integer from ${minimum} to ${maximum}.`);
  }
}

function sanitizeDailyPlanRequest(request) {
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
      streakGoal: profile.streakGoal === undefined ? 30 : cleanNumber(profile.streakGoal, 3, 365),
      notificationHour: profile.notificationHour === undefined ? 8 : cleanNumber(profile.notificationHour, 0, 23),
      notificationMinute: profile.notificationMinute === undefined ? 0 : cleanNumber(profile.notificationMinute, 0, 59),
      onboarding: sanitizeOnboardingContext(profile.onboarding)
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

function sanitizeOnboardingContext(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }

  return {
    spiritualStartingPoint: cleanText(value.spiritualStartingPoint),
    dailyCommitmentMinutes: cleanNumber(value.dailyCommitmentMinutes, 5, 120),
    preferredTimeWindow: cleanText(value.preferredTimeWindow),
    primaryObstacle: cleanText(value.primaryObstacle),
    whyStarted: cleanText(value.whyStarted),
    firstStepCompletedAt: cleanText(value.firstStepCompletedAt),
    initialMilestoneDays: cleanNumber(value.initialMilestoneDays, 3, 100)
  };
}

function extractRecentPlanMemoryFromEncodedPayload(payload) {
  const decoded = JSON.parse(Buffer.from(payload, "base64").toString("utf8"));
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
}

function sortedRecentItems(items) {
  return items
    .filter((item) => Object.values(item).some((value) => typeof value === "string" && value.trim().length > 0))
    .sort((left, right) => {
      const leftDate = Date.parse(left.date ?? "");
      const rightDate = Date.parse(right.date ?? "");
      return (Number.isFinite(rightDate) ? rightDate : 0) - (Number.isFinite(leftDate) ? leftDate : 0);
    })
    .slice(0, maxRecentPlanMemory);
}

function uniqueNonEmpty(values) {
  const seen = new Set();
  const output = [];
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

function normalizedVerseReference(value) {
  return value
    .replace(/\s*\((WEB|NLT|Modern)\)\s*$/i, "")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function cleanText(value) {
  if (typeof value !== "string") {
    return "";
  }
  return value.replace(/\s+/g, " ").trim().slice(0, maxTextLength);
}

function cleanNumber(value, minimum, maximum) {
  const numberValue = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(numberValue)) {
    return minimum;
  }
  return Math.min(Math.max(Math.round(numberValue), minimum), maximum);
}

function assertSourceContainsDailyPlanContract() {
  assert.match(source, /const dailyPlanCacheVersion = "commitment-onboarding-v2"/, "Daily plan cache should be versioned when generation behavior changes.");
  assert.match(source, /const dailyPlanSchema = \{[\s\S]*additionalProperties: false/, "dailyPlanSchema should reject extra object properties.");
  assert.match(source, /name: "daily_plan"[\s\S]*schema: dailyPlanSchema[\s\S]*strict: true/, "OpenAI response format should use the strict daily plan JSON schema.");
  assert.match(source, /function personalizationContext\(/, "AI generation should derive a personalization context before prompting.");
  assert.match(source, /const firstWeekRampSteps[\s\S]*missionMechanic[\s\S]*reflectionFocus[\s\S]*habitFocus/, "First-week ramp should carry mission, reflection, and habit instructions.");
  assert.match(source, /function applyFirstWeekRampToPlan\(/, "Server should enforce first-week plan details after model generation.");
  assertInOrder(
    source,
    [
      "const cachedPlan = await getCachedDailyPlan(uid, generatedDate, requestId);",
      "if (cachedPlan)",
      "response.status(200).json(dailyPlanResponsePayload(cachedPlan",
      "return;",
      "await enforceRateLimit(uid);",
      "plan = await createDailyPlan(body, uid"
    ],
    "Cache hits should return before rate limiting or OpenAI plan generation."
  );
  assertInOrder(
    source,
    ["const recentPlanMemory = await loadRecentPlanMemory(uid);", "client.responses.create"],
    "Recent plan memory should be loaded before the OpenAI response call."
  );
  assert.match(source, /async function fallbackDailyPlan[\s\S]*const recentPlanMemory = await loadRecentPlanMemory\(uid\);/, "Fallback daily plans should also use recent plan memory.");
  assert.match(source, /commonFailureReason[\s\S]*latestImprovementPlan[\s\S]*feedbackDirective/, "Personalization context should include failure, improvement, and feedback signals.");
  assert.match(source, /type DailyPlanOnboardingContext/, "Daily plan requests should support onboarding personalization context.");
  assert.match(source, /dailyCommitmentMinutes[\s\S]*primaryObstacle[\s\S]*whyStarted/, "Onboarding commitment, obstacle, and motivation should reach AI personalization.");
  assert.match(source, /Never turn that answer into a spiritual score/, "Spiritual starting point must not be treated as spiritual worth or a score.");
  assert.match(source, /commitmentMinutes === undefined[\s\S]*targetDifficulty - 1\) \* 5/, "Mission duration should grow from the user's onboarding commitment.");
}

function assertInOrder(haystack, needles, message) {
  let offset = 0;
  for (const needle of needles) {
    const index = haystack.indexOf(needle, offset);
    assert.notEqual(index, -1, `${message} Missing or out of order: ${needle}`);
    offset = index + needle.length;
  }
}

function main() {
  assert.deepEqual(validateDailyPlan(validDailyPlanFixture), [], "Valid daily plan fixture should satisfy the schema.");

  const missingRequired = structuredClone(validDailyPlanFixture);
  delete missingRequired.mission.durationMinutes;
  assert.match(validateDailyPlan(missingRequired).join("\n"), /mission\.durationMinutes is required/);

  const extraProperty = structuredClone(validDailyPlanFixture);
  extraProperty.devotional.unexpected = "not allowed";
  assert.match(validateDailyPlan(extraProperty).join("\n"), /devotional\.unexpected is not allowed/);

  const invalidBounds = structuredClone(validDailyPlanFixture);
  invalidBounds.challenges[0].targetCompletions = 99;
  assert.match(validateDailyPlan(invalidBounds).join("\n"), /targetCompletions must be an integer from 1 to 14/);

  const sanitized = sanitizeDailyPlanRequest(requestFixture);
  assert.equal(sanitized.profile.goals.length, maxGoals);
  assert.equal(sanitized.profile.currentStreak, 5);
  assert.equal(sanitized.profile.longestStreak, 19);
  assert.equal(sanitized.profile.recoveryStreak, 0);
  assert.equal(sanitized.profile.notificationHour, 23);
  assert.equal(sanitized.profile.onboarding.dailyCommitmentMinutes, 10);
  assert.equal(sanitized.profile.onboarding.primaryObstacle, "My phone pulls me away");
  assert.equal(sanitized.recentHistory.length, maxRecentHistory);

  const encodedPayload = Buffer.from(JSON.stringify(storedSnapshotFixture), "utf8").toString("base64");
  const memory = extractRecentPlanMemoryFromEncodedPayload(encodedPayload);
  assert.deepEqual(memory.missionTitles, ["Delayed Task Sprint", "Phone Boundary Focus Block"]);
  assert.deepEqual(memory.devotionalTitles, ["Faithful With Attention"]);
  assert.deepEqual(memory.devotionalVerses, ["colossians 3:23", "proverbs 4:25"]);

  assertSourceContainsDailyPlanContract();

  console.log("Daily plan fixture validation passed without OpenAI or Firebase network calls.");
}

main();
