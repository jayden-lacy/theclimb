# Age Rating Review

Last reviewed: July 29, 2026

This review is an engineering and product content inventory. Apple assigns the final rating from the current App Store Connect questionnaire. Re-answer the questionnaire for the exact submitted binary rather than copying a prior rating.

## Intended Audience

The Climb is intended for users age 13 and older.

Current onboarding choices begin at:

- 13–15
- 16–18
- 19–24
- 25+

There is no Under 13 onboarding option. Public Terms and marketing must use the same minimum age. The product does not currently implement parental consent, a child-directed account system, or guardian administration.

## Content Inventory

| Content area | Present | Release assessment |
| --- | --- | --- |
| Christian scripture, prayer, and devotional content | Yes | Religious and reflective content; not inherently mature |
| Discipline, temptation, purity, and personal-struggle themes | Yes | May discuss sensitive topics in non-graphic, supportive language |
| AI-generated missions and devotionals | Yes | Text generation is constrained and has deterministic fallback; still requires monitoring |
| User-generated community posts | Yes | Report, block, own-post deletion, filtering, and support controls are present |
| Groups and accountability partners | Yes | Limited social/accountability interaction; not anonymous unrestricted chat |
| Violence or graphic injury | Not intended | No first-party graphic content or visual violence |
| Sexual content or nudity | Not intended | Adult-site protection discusses blocking at a category level and should not display explicit material |
| Profanity or crude humor | Not intended | Basic filtering exists for community content |
| Alcohol, tobacco, or drug use | Not intended | No promotional or instructional content |
| Gambling or simulated gambling | No | No gambling mechanics or purchases |
| Contests or sweepstakes | No | None |
| Medical or treatment advice | No | Product is not medical care and must not present itself as treatment |
| Unrestricted web browsing | No | The app opens specific legal/support/invite URLs and does not include a general web browser |
| Advertising | No | No ad network or third-party ads |
| In-app purchases | No | Product is free; no StoreKit products or subscription |

## User-Generated Content

Answer Apple's user-generated-content and communication questions truthfully. Community includes posts, groups, partner check-ins, encouragement, and limited user-to-user interaction.

Required release controls:

- [ ] Report post works against the production backend.
- [ ] Block user removes that user's content from the requesting user's experience.
- [ ] Users can delete their own posts.
- [ ] Group admins can manage members and roles according to backend authorization.
- [ ] Basic profanity and abuse filtering is active.
- [ ] Support is reachable at `support@theclimbapp.org`.
- [ ] Published community rules and Terms prohibit abuse, sexual content, threats, harassment, and illegal content.
- [ ] Moderation response ownership and escalation timing are documented internally.

All items above require a final production smoke test; they were not reverified against a deployed backend during this documentation audit.

## Adult-Protection Feature

The presence of adult-site protection does not mean the app displays adult content. Product copy should:

- describe the category without examples, thumbnails, or explicit URLs;
- avoid screenshots of adult material;
- use approved test fixtures for QA;
- redact domains from evidence where practical; and
- avoid making the app itself a directory of restricted content.

## AI Content Controls

- [ ] Prompts prohibit explicit sexual content, self-harm encouragement, hate, abuse, and dangerous instructions.
- [ ] Community and AI safety fallbacks remain active.
- [ ] Generated content is monitored after launch using privacy-safe aggregate failure signals.
- [ ] Support has a path for reporting inappropriate generated content.
- [ ] The app does not present AI text as professional medical, legal, or pastoral care.

## Rating Recommendation

Use a product minimum age of 13+ because account creation begins at age 13 and the app includes user-generated community content and discussion of personal struggles. This is not a prediction of Apple's assigned rating.

Before submission:

1. Complete the current App Store Connect age-rating questionnaire.
2. Mark user-generated content and relevant communication capabilities accurately.
3. Answer sensitive-theme frequency based on actual first-party and generated content, not product intent alone.
4. Confirm the assigned rating is compatible with the Terms, onboarding gate, marketing, and target countries.
5. Escalate to legal/privacy review if any storefront requires a different child-consent or age-assurance approach.

## Release Decision

| Reviewer | Date | App Store assigned rating | Approved |
| --- | --- | --- | --- |
| Product |  |  | Pending |
| Privacy/legal |  |  | Pending |
| Release owner |  |  | Pending |
