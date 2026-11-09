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
    wait for a tap on a confirm card)       daily limit (ai_usage)
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

| Setting (repo variable, optional) | Default | Meaning |
|---|---|---|
| `AI_MODEL` | `claude-opus-5-5` | Claude model the function calls |
| `AI_DAILY_CHAT_CALLS` | 120 | model calls per account per day (one question can take 2-4) |
| `AI_DAILY_VOICE_SECONDS` | 900 | Sarvam seconds per account per day |

Requests run at low effort with prompt caching on the fixed prompt and the
conversation. The day is India's calendar day.

## Secrets

| Repo secret | Where from | Used by |
|---|---|---|
| `ANTHROPIC_API_KEY` | console.anthropic.com -> API keys | chat |
| `SARVAM_API_KEY` | dashboard.sarvam.ai -> API keys | voice fallback |
| `REVENUECAT_SECRET_KEY` | RevenueCat -> project -> API keys -> secret (v1) key, `sk_...` | plan check |
| `SUPABASE_URL`, `SUPABASE_ACCESS_TOKEN` | already set | deploy |

## Going live

1. Merge the PR.
2. Actions -> `supabase-deploy` -> Run (adds the `ai_usage` table).
3. Actions -> `ai-assistant-deploy` -> Run (copies the keys into the
   function's secrets, deploys it, checks it refuses callers with no
   session, and runs the live checks against the real keys).
4. Build the next app version.

## Tests

- `deno test` in `supabase/functions/ai-assistant` (offline, fakes).
- `supabase/tests/ai_usage_test.sql` (the daily allowance; local database).
- `live_test.ts` with the real keys: the prompt and tools are accepted,
  Claude picks `add_expense` with the right amount, a Hindi question gets a
  Hindi answer, and the Sarvam and RevenueCat keys work. Runs in the
  `ai-assistant` workflow from the repo secrets.
- Flutter: `assistant_tools_test`, `assistant_conversation_test`,
  `assistant_screen_test`, `voice_dpr_agent_test`.
