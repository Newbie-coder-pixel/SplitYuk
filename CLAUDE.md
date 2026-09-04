# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

- [PRD_SplitBill_App_v3.md](PRD_SplitBill_App_v3.md) — the spec; read before making product/architecture decisions.
- [design.md](design.md) — the visual design system (colors, typography, receipt/stamp motifs) extracted from the mockups. Flags one unresolved conflict with the PRD in §8 (a payment-destination box shown in one mockup that contradicts §6/§9.6) — that box was deliberately **not** implemented.
- [app/](app/) — the Flutter app (Android & iOS). All product logic lives here.
- [server/](server/) — the stateless Vercel/Node relay (see [server/README.md](server/README.md)). Scaffolded but never deployed — no live Fonnte/Resend/Upstash credentials exist for this project.

## Commands

Flutter app (run from `app/`):
- `flutter analyze` — must be clean before considering any change done.
- `flutter test` — unit tests (`test/logic`, `test/models`, `test/state`) plus widget/screen smoke tests (`test/widget_test.dart`, `test/screens_smoke_test.dart`). Run a single file with `flutter test test/logic/split_calculator_test.dart`, or a single test with `--plain-name "some test name"`.
- `flutter run -d chrome` / `-d macos` — only screens that don't touch camera/contacts/OCR plugins (those are Android/iOS-only) will function on these targets; useful for a quick non-hardware smoke check, not full verification.
- No Android emulator or iOS simulator is set up in this environment — camera/contacts/OCR flows have been written against the real plugin APIs but not run on-device. Say so rather than claiming they've been verified.

Backend relay (run from `server/`):
- `npm install`
- `npm run typecheck` (`tsc --noEmit`) — must be clean.
- `vercel dev` / `vercel deploy` — needs real `FONNTE_API_KEY` / `RESEND_API_KEY` / `RESEND_FROM_ADDRESS` / `UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN` (see `.env.example`), none of which are provisioned here.

## What this product is

SplitYuk is a mobile app (Flutter, Android & iOS) for splitting a bill among a group via receipt-scan OCR or manual input, then notifying each member of their amount owed over WhatsApp (Fonnte) and/or email. It does not process payments — it only tells people what they owe and lets them coordinate payment themselves outside the app.

Read the full PRD before making product or architecture decisions — it is the single source of truth. The sections below summarize the constraints that most affect how code should be structured; they are not a substitute for reading §1–17 directly.

## The defining constraint: no personal data is ever stored

This shapes almost every architectural decision in the PRD (§3) and must not be casually broken by "helpful" additions like caching, logging, or draft-recovery:

- **Never stored anywhere (server or on-device, beyond the active session):** bill contents, receipt photos, item lists, contact data, member phone numbers/emails, payment status history.
- **Never collected at all, even transiently:** payment destination info (bank account, e-wallet, QRIS). This was deliberately removed from scope (§6, §9.6) rather than "secured" — don't reintroduce it, including via seemingly harmless features like a QRIS image attachment (explicitly rejected in §10).
- **The only server-side state that may persist across sessions:** (a) a per-installation rate-limit counter, and (b) fully anonymized aggregate delivery-success counters. Neither may ever be linkable to a bill, phone number, name, or person (§12).
- **Transient processing ≠ storage:** the backend relay legitimately sees phone numbers/emails/amounts/images for the duration of a single notification request, but must not log, cache, or persist any of it — scrub these fields from platform access logs too.
- **Consequence:** there is no draft recovery. If the app is closed/killed mid-flow, the bill is gone (§11.7, FR-8.3).

Any change that adds a database table, file write, or cache entry for bill/contact/payment data is a violation of the core design principle, not just a code-quality nit — flag it explicitly rather than implementing it quietly.

## Architecture (per PRD §13–14)

- **Mobile app — Flutter.** All bill/member/split state lives only in-memory for the session (`Bill`, `BillItem`, `Member` — see §14 for exact fields). Receipt OCR runs fully on-device via Google ML Kit; the photo is never uploaded except as a one-time notification attachment, and any temp file the OS creates for camera/gallery access must be deleted immediately after use (open item, §17).
- **Backend — stateless serverless functions** (Vercel Functions, Node/TypeScript). Its only jobs: hold the Fonnte/email API keys server-side, relay one notification request at a time, and increment the anonymized counters. It must not model bill/user data — no relational database is used or needed.
- **Rate-limit/metrics store — a lightweight KV store (e.g. Upstash Redis),** not Postgres — deliberately sized to hold nothing but anonymized counters, keyed by a random per-installation token (not a phone number or any identifier).
- **Notifications:** WhatsApp via Fonnte (unofficial gateway — see risk note below), email via Resend/SendGrid as fallback. No hosted links are ever generated for bill detail; instead the receipt photo (scan flow) or an on-device-rendered summary image (manual flow, via `RepaintBoundary` or equivalent) is attached directly to the message.
- **Split calculation:** supports itemized assignment (including splitting one item across several members) and quick modes (equal / percentage / custom amount). Tax/service/discount distribute proportionally to each member's item subtotal by default, with an "equal split for extras" option. Rounding remainder defaults to the bill creator. All member shares must sum to the bill total before the flow can proceed (FR-5.4).

## App code structure (`app/lib/`)

- `models/` — `Bill`, `BillItem`, `Member`, `SplitMode`/`DiscountConfig`. Plain mutable Dart classes; `Bill`'s money fields (`subtotal`, `taxAmount`, `total`, …) are **derived getters**, not cached fields, so they can never drift out of sync with an edit.
- `logic/` — `SplitCalculator` (the money math), `SplitValidator` (gates whether a split can be calculated/sent), `SplitResult`/`MemberShare`, `ReceiptParser` (OCR-text-to-line-items heuristic). This is the most correctness-critical code in the app — see the invariant below before touching it.
- `state/session_controller.dart` — the single `ChangeNotifier` holding the entire in-memory session (the current `Bill` + member roster). There is no other state management layer and no persistence underneath it; `resetSession()`/`closeSession()` are the only ways state is cleared, matching PRD §3.
- `services/` — thin wrappers around platform plugins: `OcrService` (ML Kit, mobile-only), `ContactsService` (flutter_contacts, mobile-only), `NotificationService` (calls the backend relay's `/api/notify`; `isConfigured` is false until a real relay URL is supplied via `--dart-define=SPLITYUK_RELAY_URL=...`), `ImageRenderService` (captures a `RepaintBoundary` to PNG for the manual-entry summary image).
- `screens/` — one folder per step of the PRD §8 flow (`intro`, `create`, `scan`, `members`, `assignment`, `split`, `send`, `status`), navigated via plain `Navigator.push`/`MaterialPageRoute` — no named-route table.
- `core/` — `theme/` (implements design.md's tokens: `AppColors`, `AppTypography`, `AppSpacing`/`AppRadius`), `widgets/` (the reusable receipt-styled components: `ReceiptCard`, `StampBadge`, `DashedLine`, `AmountRow`, `MemberAvatar`, `SegmentedTabs`, button variants), `utils/` (`CurrencyFormatter`, `IdGenerator`, `InstallationId`, `TempFileCleaner`).

**The `SplitCalculator` invariant** (see its doc comment and `test/logic/split_calculator_test.dart`): for every split mode, the sum of every member's final integer share always equals `Bill.total` exactly — no fractional Rupiah, nothing lost or invented to rounding. Any rounding remainder is charged entirely to whichever member is `isCreator`, as one final adjustment, never spread across everyone. All intermediate math stays `double` and is rounded exactly once, at the end, per member. If you change this file, the reconciliation tests must still pass.

**Known simplifications versus the PRD**, made deliberately for lower risk rather than by accident:
- Receipt capture uses `image_picker` (camera source), not a custom live-viewfinder UI — covers FR-2.1 without the platform-specific risk surface of the raw `camera` plugin.
- The backend relay is scaffolded but not deployed anywhere; `NotificationService.isConfigured` is false by default and the send screen says so plainly rather than pretending a send succeeded.
- The per-installation rate-limit token (`InstallationId`) is the one thing persisted on-device across sessions (via `shared_preferences`) — this is the PRD §12/§3 narrow exception, not a violation of it.

## Known unresolved risks to keep in mind

- **Single shared Fonnte number (§15, §17):** if every install sends WhatsApp messages through one Fonnte-linked number, that number will almost certainly get banned at scale and looks suspicious to recipients. This is flagged as the most serious open risk in the document and needs a dedicated design pass (per-installation device linking, or migrating to the official WhatsApp Cloud API) — don't treat the current Fonnte integration as a finished, scalable design.
- Third-party services (Fonnte, the email provider) may retain their own delivery logs outside our control — this must stay disclosed in the app's privacy notice, not hidden.
