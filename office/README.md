# FieldOS Office

The web app for the people who run sites from the office: owners, project
managers and accounts. It signs in with the same FieldOS account as the phone
app and reads the same cloud, through the same row-level security, so it can
never see or do more than that person could on their phone. Online only.

Plan and build order: the "FieldOS office web app" plan doc (step 1 of 7 is
this scaffold: sign-in, company picker, list of sites).

## Address

Served at `https://fieldos-mldynamic.netlify.app/office/`, under the website
(Vite `base` is `/office/`). For Google sign-in that address must be on the
Supabase Auth redirect list. Email and password sign-in needs nothing extra.

## Run it

```bash
npm ci
cp .env.example .env.local   # fill in VITE_SUPABASE_ANON_KEY (public anon key only)
npm run dev                  # http://localhost:5173/office/
npm run build                # static files in dist/
```

## Test it

The browser tests run against a local FieldOS cloud. From the repo root:

```bash
supabase start -x realtime,imgproxy,edge-runtime,logflare,vector,supavisor,studio,mailpit
cd office
eval "$(cd .. && supabase status -o env)" && export API_URL ANON_KEY SERVICE_ROLE_KEY
npm run typecheck
npm run test:e2e
```

The tests make their own accounts and companies, and check that one company
never sees another's sites. The service role key is used only by the tests,
to make confirmed accounts; never put it in `.env.local`.

## Rules

- Every label goes in `src/strings.ts` (other languages come later from the
  phone app's label tables).
- Use `start`/`end` (logical) CSS properties, not left/right, so right-to-left
  languages work.
- Writes go through the same server functions and guards as the phones.
