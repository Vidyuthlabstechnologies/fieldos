# Google ML Kit — Applicability Research for FieldOS Mobile

**Provenance:** produced by the `hermes` agent CLI (nemotron-3-ultra-free via OpenCode Zen,
web-search/web-extract tools) on 2026-08-23, researching whether Google ML Kit could make
FieldOS Mobile better, faster, and more secure, in response to
https://github.com/flutter-ml/google_ml_kit_flutter/tree/master/packages/example. Sourced from
pub.dev package pages and Google's ML Kit developer docs, all accessed the same day. Not yet
independently re-verified beyond the source citations inline — treat as a strong research pass
to prototype against, not a locked-in spec.

---

## 1. Package landscape — what to use today

**Use the individual per-feature packages, not the `google_ml_kit` umbrella package.** The
umbrella package's own pub.dev listing states: *"DO NOT USE `google_ml_kit` in a production
app — instead use only the plugin(s) for the features listed."* All per-feature packages
(`google_mlkit_text_recognition`, `google_mlkit_barcode_scanning`,
`google_mlkit_document_scanner`, `google_mlkit_entity_extraction`, `google_mlkit_language_id`,
`google_mlkit_translation`) are published by the same verified publisher (flutter-ml.dev),
updated in lockstep, share one example app, and avoid the umbrella package's ~50–100MB APK
bloat from bundling all 20+ ML Kit features regardless of which you actually use.

## 2. Relevant capabilities

| Capability | On-device? | Concrete FieldOS use | Cost |
|---|---|---|---|
| **Text Recognition v2** | Yes, fully on-device, no network, no runtime model download (Latin bundled; Devanagari/CJK add ~2–3MB each) | Scan a delivery challan/GRN slip/equipment nameplate to pre-fill Documents metadata or a material receipt; photograph a printed BOQ sheet to OCR line items into estimation entry | +2–4MB base |
| **Barcode/QR Scanning** | Yes, fully on-device, no network, no model download | Tag equipment with a QR/Code-128 sticker → scan to open its log instantly; scan material batch barcodes for traceable receipts | +2–3MB |
| **Document Scanner** | Yes, fully on-device via Google Play Services (auto-capture, edge detection, perspective correction, filters, outputs PDF/JPEG) | Upgrades the just-built Documents feature from "pick an existing file" to "scan paper → PDF → attach" in one offline flow | ~0MB APK impact (Play Services); Android-only, Beta |
| **Entity Extraction** | Yes, on-device after a one-time per-language model download (~10–20MB/language; English and Hindi both supported) | Run on OCR output or Sarvam transcripts to auto-populate date/phone/address/money/tracking-number fields | +1MB code, +20–40MB one-time download for en+hi |
| **Language ID** | Yes, fully on-device, zero model download | Route non-English DPR/OCR text for translation or review flagging | +0.5MB |
| **On-device Translation** | Yes, on-device after a per-language-pair download (~20–30MB/pair) | Worker notes in Hindi/Telugu/Tamil → English without a cloud call | +1MB code, +~25MB/pair download; quality for construction terminology is unvalidated |

Not relevant, checked and ruled out: face detection, face mesh, image labeling, generic object
detection, digital ink recognition, pose detection, selfie/subject segmentation, smart reply —
none map to any FieldOS workflow (no auth/identity, no chat, no AR/fitness features, and
generic object classes don't match construction/equipment/material taxonomies).

## 3. Security/privacy analysis

The honest version, not the oversold one: ML Kit's on-device APIs never send image/text/scan
content to Google — a genuine, real advantage over any cloud OCR/NLP service, and directly
comparable to (and better than) the existing Sarvam voice call, which does upload audio
off-device. But the size of that advantage varies by use case: the data involved in barcode/OCR
scans (challan numbers, equipment IDs, dates) is low-sensitivity operational data, so the
privacy delta there is real but modest. **Translation is the case where it matters most** —
a worker's own dictated notes are the most sensitive content in this list, and keeping them
fully on-device (versus sending them to any cloud translation API) is the clearest win. Simpler
compliance posture (no cross-border data-processor relationship for these APIs) is a secondary
but real benefit given India's DPDP Act.

## 4. Recommendation

**Worth building, in priority order:**
1. **Document Scanner** — near-zero APK cost (Play Services-hosted), upgrades a feature that
   was *just* added this session, no new permission needed.
2. **Barcode Scanning** — near-zero cost, makes the equipment-tracking feature (also just
   added) actually fast to use in the field via asset QR tags.

**Prototype before committing:**
3. **Text Recognition** — only worth shipping if a real accuracy test against actual site
   paperwork (challans, GRNs, nameplates) hits ≥90% on the fields that matter. Don't ship on
   faith.
4. **Entity Extraction + Language ID** — Language ID is free and worth adding unconditionally;
   Entity Extraction only pays for itself if it demonstrably auto-fills several fields per
   document/DPR.

**Skip for now:** on-device Translation — construction-terminology quality for Hindi/Telugu/
Tamil→English is unvalidated, and the pivot-through-English translation path is a known
quality risk. Revisit only if workers explicitly ask for vernacular entry and real output
quality is checked first.

All of the "worth building" and "prototype" items are Android-only-compatible, require no
Firebase project, and add no new network dependency — consistent with FieldOS's offline-first
architecture.
