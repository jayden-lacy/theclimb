# Spending Alerts

Last verified: September 5, 2026

## Owner Requirement

Alert when combined monthly Firebase/Google Cloud and OpenAI spending reaches USD 100. The owner supplied a destination email privately; keep the address in provider notification settings rather than the public repository. Alerts must not disable billing or interrupt production requests.

## Verified Configuration

- Google Cloud project: `the-climb0`.
- The existing project-scoped USD 25 monthly budget remains unchanged, including actual-spend thresholds at 50%, 90%, and 100%. It provides earlier warnings at USD 12.50, 22.50, and 25.
- Cloud Billing Budget API is enabled.
- The enabled `The Climb release owner` email notification channel is attached to that budget. Default billing-role recipients remain enabled. The API returned the saved recipient/channel and budget configuration successfully.
- Mailbox receipt of a real notification has not been verified. Do not claim successful delivery from configuration alone.
- OpenAI settings require sign-in; no OpenAI spend-alert change was made in this pass.
- **The USD 100 combined alert is not active.** A Google Cloud budget cannot include externally billed OpenAI spend. Two separate USD 100 provider alerts would not satisfy this requirement. Neither would relabeling the existing USD 25 budget as a combined budget.

## Remaining Integration

1. Obtain authorized access to the correct OpenAI project and its cost records. An ordinary inference key must not be treated as an organization Admin key. Never paste an Admin key into chat or commit it.
2. Collect project-scoped Google Cloud billing totals through billing export or budget Pub/Sub updates, and the matching OpenAI project's Costs API totals. Use actual provider cost records, not token-price estimates presented as billed spend.
3. Define one monthly accounting boundary, USD currency, credit treatment, freshness limits, and project scope. Budget estimates can arrive late and differ from a final invoice; publish that limitation with the alert.
4. Aggregate both providers, warn once per threshold/month, and deduplicate retries. Treat missing, stale, or failed provider reads as unavailable data, never zero spending. Preserve independent provider early warnings as a fallback.
5. Test totals below/at/above USD 100, provider failure, pagination, late adjustments, month rollover, delivery retries, and a real email received by the owner.

Do not deploy a purported combined monitor until both inputs and email delivery have been verified. Do not add a hard spending cap or automatically disable services without a separate owner decision.

## References

- [Google Cloud budget recipients](https://docs.cloud.google.com/billing/docs/how-to/budgets-notification-recipients)
- [Google Cloud programmatic budget notifications](https://docs.cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications)
- [OpenAI spend alerts](https://developers.openai.com/api/docs/guides/terraform/rate-limits-and-spend)
- [OpenAI usage and costs](https://platform.openai.com/docs/api-reference/usage)
