# Ask FieldOS: the AI assistant

Anyone on a site can type or speak what they need, in their own language,
and the assistant does it in the app: adds expenses, payments, tasks,
workers, attendance, issues, daily reports and material entries, answers
questions about the sites, and gives a button to the right screen for
anything done by hand (photos, bills, estimation, chat).

## How it fits together

```
phone (Flutter)                          Supabase edge function           outside services
---------------                          ----------------------           ----------------
Home -> Ask FieldOS (assistant_screen)
  AssistantConversation  --chat-------->  ai-assistant                --> Anthropic (Claude)
    AssistantTools (runs the actions        checks sign-in (JWT)
    on the phone's own data; changes        checks plan (RevenueCat)  --> RevenueCat REST v1
    wait for a tap on a confirm card)       monthly ₹ cap (ai_usage)  --> backup: DeepSeek on Sarvam
                                            daily call guard
  voice: phone recognizer, offline
    fallback ----------transcribe----->     same checks               --> Sarvam speech-to-text
  answers read aloud: phone TTS, offline
```

- The keys live only in the function's secrets. Nothing secret ships in the
  app, and nobody types a key in Settings any more.
- The system prompt and the tool list are fixed on the server
  (`supabase/functions/ai-assistant/tools.ts`), so the shared key can't be
  used as a general chatbot. The phone side of each tool is in
  `fieldos_mobile/lib/agents/assistant_tools.dart`; a test fails if the two
  lists differ.
- FieldOS is offline-first: the site data is on the phone, so the phone runs
  the tools and sends back only the results the model asked for.
- Sarvam is used only when the phone's own speech recognizer can't do the
  language. Everything else (reading aloud, translation, the DPR parser) is
  on the phone and free.

## Limits and cost

FieldOS must keep a 98% margin, so the AI has a hard money cap per person.

- One plan brings in at least ₹779 a person a month after the store's 15%
  (yearly ₹10,999 / 12 x 0.85). 2% of that is ₹15.6 for every cost FieldOS
  has. The AI gets ₹10 of it by default.
- Every call is costed from the provider's own token counts (Claude, the
  DeepSeek backup) or seconds (Sarvam voice) and added to the person's spend
  for the month (India's calendar month), in table `ai_usage`. Once it
  reaches the allowance, the assistant says so and stops until the 1st. The
  app shows "15% of this month's assistant use is left" from 20% down.
- Claude Haiku with the prompt and tools cached, thinking off, low effort and
  at most 2,000 output tokens. A typical question (2-3 calls) costs about
  ₹0.05-0.10, so ₹10 is roughly 100-200 questions a month.
- A chat over about 120,000 characters must be started again, which keeps
  every call under the 100K tokens where Haiku's price goes up 5 times.
- When Anthropic is down or overloaded, DeepSeek V4.1 Flash on the Sarvam key
  answers instead, through the same tools.

| Setting (repo variable, optional) | Default | Meaning |
|---|---|---|
| `AI_MONTHLY_BUDGET_INR` | 10 | what one person's AI use may cost a month, in ₹ |
| `AI_DAILY_CHAT_CALLS` | 60 | model calls per person per day, a guard against bursts |
| `AI_MODEL` | `claude-haiku-5-5` | Claude model the function calls |
| `AI_USD_INR` | 95 | rupees per dollar used to cost Claude, kept on the high side |

Prices used (check them when a provider changes its prices; they are in
`core.ts`):

| What | Price |
|---|---|
| Claude Haiku | $0.10 in / $0.50 out per million tokens; cache reads $0.01, cache writes $0.125 |
| DeepSeek V4.1 Flash on Sarvam (backup) | ₹14 in / ₹55 out per million tokens; cached ₹0.25 |
| Sarvam speech to text | ₹0.49 a minute |

## Secrets

| Repo secret | Where from | Used by |
|---|---|---|
| `ANTHROPIC_API_KEY` | console.anthropic.com -> API keys | chat |
| `SARVAM_API_KEY` | dashboard.sarvam.ai -> API keys | voice fallback, backup chat model |
| `REVENUECAT_ANDROID_KEY` | already set for the app build (`goog_...`) | plan check |
| `REVENUECAT_SECRET_KEY` | optional: RevenueCat -> API keys -> secret (v1) key, `sk_...`; used instead when set | plan check |
| `SUPABASE_URL`, `SUPABASE_ACCESS_TOKEN` | already set | deploy |

## Going live

1. Merge the PR.
2. Actions -> `supabase-deploy` -> Run (adds the `ai_usage` table and its
   two functions).
3. Actions -> `ai-assistant-deploy` -> Run (copies the keys into the
   function's secrets, deploys it, checks it refuses callers with no
   session, and runs the live checks against the real keys).
4. Build the next app version.

## Tests

- `deno test` in `supabase/functions/ai-assistant` (offline, fakes).
- `supabase/tests/ai_usage_test.sql` (the daily allowance; local database).
- `live_test.ts` with the real keys: the prompt and tools are accepted,
  Claude picks `add_expense` with the right amount and the question costs
  under ₹0.15, a Hindi question gets a Hindi answer, DeepSeek on Sarvam picks
  the same tool, and the Sarvam and RevenueCat keys work. Runs in the
  `ai-assistant` workflow from the repo secrets.
- Flutter: `assistant_tools_test`, `assistant_conversation_test`,
  `assistant_screen_test`, `voice_dpr_agent_test`.
