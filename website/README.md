# FieldOS website

Plain static HTML and CSS, no build step. Open `index.html` in a browser to preview.

Pages: home (`index.html`), `privacy-policy.html`, `terms-of-use.html`,
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

## Before going live

- Pricing (₹499/month, ₹4,999/year per person) must match the Play Console base plans.
- The Google Play buttons point at `com.mldynamic.fieldos`; they work once the listing is public.
- Keep the privacy policy and terms here in step with the in-app copies in `docs/store/`.
