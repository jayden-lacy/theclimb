# Daily AI Devotionals

The iOS app already calls `RemoteAIContentService` when it needs today's plan. If `AIProxyURL` is empty, the app safely falls back to the local template generator.

## Architecture

Do not put an OpenAI API key in the iOS app. The app should call a backend endpoint, and the backend should call OpenAI.

Flow:

1. App launches or finishes onboarding.
2. `AppViewModel.ensureTodayPlan()` checks whether today's mission and devotional exist.
3. `RemoteAIContentService` sends the user's Firebase Auth ID token in the `X-Firebase-Auth` header, plus profile and recent reflections, to `AIProxyURL`.
4. Firebase Functions verifies the Firebase user, then calls OpenAI with Structured Outputs.
5. The response is decoded into the app's `DailyPlan` shape and saved locally.

The function uses the inline structured prompt in `firebase/functions/src/index.ts` by default. If you want to use a stored OpenAI prompt, set `OPENAI_DAILY_PLAN_PROMPT_ID` as an environment variable on the deployed function instead of hardcoding the prompt ID in source.

## Backend Setup

The scaffold in `firebase/functions` exposes one HTTPS function:

```text
generateDailyPlan
```

Install and deploy it from the repo root:

```sh
cd firebase/functions
npm install
cd ../..
firebase functions:secrets:set OPENAI_API_KEY --project the-climb0
firebase deploy --only functions --project the-climb0
```

The iOS app is configured to call this project endpoint:

```xml
<key>AIProxyURL</key>
<string>https://us-central1-the-climb0.cloudfunctions.net/generateDailyPlan</string>
```

If you deploy to a different Firebase project, replace that URL with the deployed HTTPS function URL.

## Verse Accuracy

The backend gives the model a struggle-specific list of approved verse references and then overwrites the response with local World English Bible (WEB) public-domain verse text. That keeps the devotional AI-generated while preventing invented Bible quotes and avoiding a runtime external Bible API dependency.

## Security

Never put `OPENAI_API_KEY` in Swift, `Info.plist`, Firebase Remote Config, or any file shipped in the app bundle. If a key has been pasted into chat, logs, or source control, revoke it and create a new one before setting the Firebase secret. The function is publicly invokable at the Cloud Run layer but requires a Firebase Auth token in `X-Firebase-Auth` before it will call OpenAI, which prevents the endpoint from acting as an open public proxy.

To add more verses, update both `verseOptionsByStruggle` and the local `publicDomainVerses` WEB text map in:

```text
firebase/functions/src/index.ts
```

Use public-domain text or a Bible translation/API you have the right to use.

## Daily Behavior

The app generates a new plan once per local calendar day when the user opens the app and no plan for that day exists. The Firebase Function caches successful or fallback responses in the backend-only `aiDailyPlans/{uid}_{yyyy-MM-dd}` collection before returning them, so repeat opens for the same user/date can avoid another OpenAI call and do not burn the daily AI limit. For server-side pregeneration before users open the app, add a scheduled Firebase Function that writes compatible cached plans ahead of time.

Users can request a different plan from Home before starting the mission. That sends `forceRegenerate=true` and a short reason to the Firebase Function. The function skips the same-day cache for that request, still applies the per-user daily AI rate limit, writes the replacement plan back to `aiDailyPlans/{uid}_{yyyy-MM-dd}`, and returns fallback content if OpenAI fails.

The first seven days after `profile.joinedAt` use a guided ramp. The backend includes a first-week context in the AI prompt, and the iOS client also post-processes AI/fallback plans with the same ramp so new users get clearer early steps without changing the stored data model.
