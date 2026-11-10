# FieldOS website

Plain static HTML and CSS, no build step. Open `index.html` in a browser to preview.

Pages: home (`index.html`), `builders.html` (For builders: company plans with no public prices and the "Book a site audit" form; `builders-thanks.html` after sending it), `guide.html` (the video guide), `privacy-policy.html`, `terms-of-use.html`,
`delete-account.html` (Play Console's account-deletion URL), `support.html`, `404.html`.
Colours match `fieldos_mobile/lib/core/brand.dart`.

## Hosting (free)

This repo is private on a free GitHub plan, so GitHub Pages cannot serve it.
Use any free static host and upload this folder as it is:

- **Netlify Drop**: go to https://app.netlify.com/drop, sign in, drag the `website` folder onto the page.
- **Cloudflare Pages**: Workers & Pages → Create → Pages → Upload assets → drag the folder.

Then set these in Play Console and as repo variables (`PRIVACY_POLICY_URL`, `TERMS_URL`):
`<site>/privacy-policy.html`, `<site>/terms-of-use.html`, and `<site>/delete-account.html`
for the Data safety account-deletion link.

## Site audit form

`builders.html` posts to **Netlify Forms** (`data-netlify="true"`, form name `site-audit`,
with a honeypot field). Netlify picks the form up on deploy. To get an email for each request:
Netlify → the site → Forms → Form notifications → add info@mldynamic.com. Other hosts don't
process the form; the page also gives the email address.

## Before going live

- Pricing (₹999/month, ₹10,999/year per person) must match the Play Console base plans.
- The Google Play buttons point at `com.mldynamic.fieldos`; they work once the listing is public.
- Keep the privacy policy and terms here in step with the in-app copies in `docs/store/`.

## Screens and videos

`assets/screens/` are real app screens rendered by
`fieldos_mobile/tool/store_screenshots/` (demo data, no client figures).
`assets/video/` holds the 30-second promo and the video guide, compressed
for the web; the full-quality masters are in the project's marketing files.
Fonts are self-hosted (`assets/fonts/`, Inter, SIL OFL) so the site makes
no third-party requests.

## Owner dashboard (`owner.html`)

A read-only page for owners and project managers: every running site's
money in and out (30 days), last daily report, labour today, open issues,
approvals waiting, construction progress and the week's corrections and
deletes, with the sites that need attention first. No libraries and no
build step: plain `fetch` against the FieldOS cloud's REST API, signed in
as the person, so the server's row-level security decides what they see.
It never writes. The session is kept for the browser tab only.

To switch it on when deploying:

1. Fill `assets/owner/config.js` with the Supabase project URL and its
   **anon (public)** key, the same ones the app is built with. Never put
   the service-role key here.
2. In Supabase, Authentication, URL Configuration, add
   `<site>/owner.html` to the redirect URLs so "Sign in with Google" can
   come back to it.

`robots.txt` keeps search engines off it. Without step 1 the page says it
isn't connected yet.
