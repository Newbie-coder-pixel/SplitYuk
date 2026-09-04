# SplitYuk — Design System

**Source:** reverse-engineered from the "Receipt Workspace" mockup set (9 screens covering the full flow: intro → scan → OCR review → manual entry → pick friends → split summary → item assignment → send → payment status).

All colors below are **sampled/estimated from the mockups by eye**, not exported from a design tool — treat hex values as a close starting palette and true them up against real design files or brand swatches before shipping pixel-perfect UI. The goal of this document is consistency of *system*, not exact pixel matching.

---

## 1. Concept & Tone

The entire UI leans into a **physical receipt / ticket-stub metaphor** to reinforce the product's core promise (PRD §3: nothing is stored):

- Screens are framed as a "Receipt Workspace" — every major card looks like a torn paper chit: perforated dashed edges, zigzag torn-paper strips, circular stub notches on the sides.
- Rotated rubber-stamp badges ("CHECK OK", "TALLY OK", "LUNAS", "SIAP KIRIM // SPLITYUK", "100% LOKAL & PRIVAT") visually reassure the user at each checkpoint — this is the primary trust-building device, doing the job a security badge or lock icon would do elsewhere.
- Copy repeatedly and explicitly restates ephemerality in-context ("Tanpa akun. Tanpa riwayat tersimpan.", "Sesi akan dibersihkan secara otomatis dari memori perangkat.") rather than relying on a one-time onboarding disclaimer. Privacy messaging is a recurring UI element, not a footnote.
- Numbers, IDs, and receipt-authentic text ("NOTA KONTAN #0492", "REG-0001") use a monospace/slab typewriter treatment to look "printed"; conversational body copy uses a normal humanist sans — the contrast between the two fonts *is* the receipt illusion.
- Language is bilingual: system/meta chrome ("Receipt Workspace", step counters, tab labels) leans English; user-facing instructional and transactional copy is Indonesian. Don't force one language everywhere — follow the pattern per string type (see §7).

---

## 2. Color System

| Token | Approx. Hex | Where it's used |
|---|---|---|
| `bg-app` | `#F3F1F6` | Screen background (very light lavender-gray) |
| `bg-card-outer` | `#DAD5C3` | Outer "envelope" card behind the receipt on the intro screen (warm khaki/beige) |
| `bg-paper` | `#FBF9F4` | Receipt/ticket paper surface — cards that mimic physical paper |
| `bg-surface` | `#FFFFFF` | Standard white cards/panels (forms, lists) |
| `bg-input` | `#EAE6F2` | Text input fill, chip fill (unselected-but-fillable), search bar |
| `text-primary` | `#1E2130` | Headings, primary body text — near-black navy, never pure black |
| `text-secondary` | `#6B6B76` | Meta text, timestamps, helper copy, placeholder labels |
| `accent-terracotta` | `#C97B6E` | Primary CTA buttons, active tab indicator, progress bar fill, key totals |
| `accent-maroon` | `#7A3B3B` | Header avatar chip, some primary buttons (deeper/darker variant of terracotta for high-emphasis CTAs like "Looks right, continue") |
| `accent-violet` | `#5B4B8A` | Stamp outlines/text, selected-checkbox fill, "LIVE EDIT"/status badges, payment progress bar |
| `accent-amber` | `#E3B15E` / bg `#F6E3BE` | Warning banners (OCR mismatch, rounding note), "fees" badge, tilted mini-tag labels |
| `accent-success-green` | `#4E9B6E` (dot/check only) | Small live/ready indicators (green dot on WhatsApp channel, ready checkmark) |
| `divider-dashed` | `#C9C4D6` | Dashed/dotted separators between line items, receipt perforation lines |
| `border-subtle` | `#DDD9E8` | Card borders, dashed-outline buttons |

**Usage rules:**
- **Terracotta vs. maroon:** terracotta is the default primary-action color (most CTAs, active tab state). Maroon appears as an alternate primary on a couple of screens — treat it as the same semantic role (primary CTA) rather than a second competing accent; don't introduce a third "primary" color.
- **Violet is reserved for authenticity/status marks** — stamps, "LIVE EDIT", selected-contact checkmarks, the payment-progress bar. It should read as "the system verifying something," not as a general-purpose accent.
- **Amber is reserved for warnings/attention**, never for positive or neutral state.
- Never use a fourth hue for a new UI purpose without checking whether terracotta/maroon/violet/amber already covers that semantic (primary action / verification / warning).

---

## 3. Typography

Two families, used with a deliberate purpose split — do not blend them within the same text element:

1. **Display/mono family** (a bold, slightly condensed monospace or slab-serif face — visually like a receipt-printer or typewriter font): used for
   - Screen/section titles that should feel "printed" (`SPLITYUK`, `Receipt Workspace`, `NOTA PATUNGAN`, `WARUNG SEDAP MALAM`)
   - Uppercase letter-spaced micro-labels (`SLIP SEMENTARA`, `KETERANGAN ITEM`, `JUMLAH (IDR)`, `TOTAL TAGIHAN`)
   - IDs/codes (`No. REG-0001`, `NOTA KONTAN #0492`, `S-89240`)
   - Stamp text inside rotated badges

2. **Body/humanist sans family** (a clean, rounded-ish grotesque, e.g. something in the Inter/system-UI family): used for
   - All conversational/instructional copy ("This app never saves your bills...", "Ketuk item, lalu pilih teman yang ikut memesan.")
   - Form labels and input text, contact names, list item descriptions
   - Button labels

**Scale (relative, not exact px):**
- Hero title (`SPLITYUK`): largest, bold, mono — one-off, intro screen only
- Screen title (nav bar): medium, bold, mono
- Section heading (card titles like "Ringkasan Pembagian Nota", "Review Scanned Chit"): medium-large, bold, sans
- Body copy: regular weight, sans, comfortable line-height (receipts feel dense; body paragraphs should not)
- Micro-label / eyebrow (uppercase, letter-spaced): small, mono or sans-with-tracking, secondary text color
- Monetary amounts: bold, tabular/mono numerals so columns of Rp values align — this is important, amounts must never use a proportional font that lets digits shift width

---

## 4. Signature Motifs

These are the visual devices that make screens read as "SplitYuk" rather than a generic form UI. Reuse them structurally, not just visually:

- **Perforated ticket edge:** a horizontal dashed line interrupted by two small circular notches (one near each side edge), simulating a tear-off stub. Used at the top/bottom boundary of receipt-styled cards.
- **Zigzag/torn-paper strip:** a row of small triangles used as a card's bottom border, reinforcing the "torn receipt" edge. Appears at the base of the intro card and the payment-status card.
- **Dotted leader lines:** in any label↔value row (item name ⋯⋯⋯ price), fill the gap with a dotted rule rather than just whitespace — this is core to the "printed receipt" feel and should be the default pattern for all price rows, not just a few screens.
- **Rotated rubber-stamp badge:** outlined (not filled) shape, ~ -10° to -15° rotation, violet stroke + violet uppercase mono text, slightly irregular/hand-stamped feel. Used as a confirmation/verification affordance (`CHECK OK`, `TALLY OK`, `LUNAS`, `SIAP KIRIM // SPLITYUK`, `100% LOKAL & PRIVAT`). Never used for errors or warnings — stamps are always a positive/neutral confirmation.
- **Tilted mini-tag:** a small rectangular label, slightly rotated, that looks stapled/clipped onto a card corner (`NOTA KONTAN #0492`, `#SLIP-MANUAL`). Used to give an artifact (a scanned receipt, an inserted manual-entry form) its own sub-identity within a larger screen.
- **Avatar initials with a consistent color rotation:** member avatars are colored circles with 2-letter initials; colors cycle through terracotta / violet / amber (not an unlimited palette) so any group of members stays visually within the app's palette rather than introducing arbitrary per-user colors.

---

## 5. Components

**Buttons**
- Primary: full-width, rounded rectangle (large radius), terracotta or maroon fill, bold dark text, trailing arrow (`→` or `▷`) for forward-progressing actions. Some primary buttons show a subtle offset/hard shadow (small neubrutalist-style drop shadow, not a soft blur) — apply this consistently to all primary CTAs, not selectively.
- Secondary: same shape, light lavender (`bg-input`) or white fill, no shadow.
- Dashed-outline button: used for optional/"add" actions (`+ Add item row`, `+ Tambah teman di luar kontak`) — border-dashed, transparent or very light fill, signals "expands the form" rather than "advances the flow."
- Disabled: gray fill, lock icon prefix, no shadow — used specifically to block progress until a validation rule is satisfied (e.g., "Selesaikan pembagian (5 item tersisa)" while items remain unassigned), not for generic disabled states.

**Inputs**
- Rounded rectangle, `bg-input` fill, no visible border by default (the fill color is the affordance). Placeholder text in `text-secondary`.

**Chips / Pills**
- Category or filter chips: rounded-full, `bg-input` when unselected, terracotta/accent fill + icon when selected.
- Status pills: small, high-contrast fill (dark for counts like "3 Dipilih", amber for warnings like "15% fees", lavender for informational like "OCR 94% CONFIDENT").

**Segmented tabs**
- Full-width row split into equal segments, active segment gets solid terracotta fill with dark/white text, inactive segments are transparent/white with `text-secondary`. A thin accent underline can reinforce the active tab.

**Cards**
- Two nesting levels are common: an outer neutral/khaki or white container, and an inner "paper" card with the receipt treatment (perforation, dashed dividers). Don't apply the receipt treatment to every card — reserve it for content that represents the actual bill/receipt artifact; plain forms (contact picker, permissions list) stay on plain white cards.

**List rows**
- Left: icon or avatar. Middle: primary label (bold) + secondary meta line (gray, smaller). Right: value (bold, tabular numerals) and/or a status control (checkbox, chevron, badge). Rows are separated by a dotted rule, not a solid line, when inside a receipt-styled card; solid or no divider elsewhere.

**Progress indicators**
- Step progress (multi-step flow, e.g. "Langkah 2 dari 4"): segmented bar, filled segments in terracotta, unfilled in `bg-input`.
- Completion/payment progress (e.g., "3 of 5 paid — 60%"): a single thick rounded bar, violet fill for payment-status contexts, terracotta fill for item-assignment contexts. Keep this split intentional: violet = money/verification state, terracotta = task-completion state.

**Badges/Stamps** — see §4, Signature Motifs.

---

## 6. Layout & Spacing

- Corner radius scale: large (~20–24px) for outer cards/containers, medium (~12–16px) for buttons and inputs, full/pill for chips and status badges. Stay on this 3-step scale rather than introducing arbitrary radii.
- Consistent horizontal screen padding; cards nest with a visible inset so the "paper inside an envelope" layering reads clearly (outer container has a darker/neutral background peeking around the inner white/paper card).
- Bottom-fixed action bar pattern: on multi-step screens (pick friends, item assignment), the primary CTA and a summary stat (count, total, percentage) sit together in a bar pinned to the bottom of the screen, separate from scrolling content.

---

## 7. Copy & Language Conventions

- **System chrome and structural labels → English:** nav titles ("Receipt Workspace"), tab names ("Itemized", "Total only", "By item", "Equal", "Percent", "Custom"), micro-labels on receipts ("SLIP SEMENTARA", "TALLY OK").
- **User-facing instructions, form labels, and transactional copy → Indonesian:** anything the end user reads as "what do I do next" or "what is happening to my money" ("Pilih Teman Patungan", "Ketuk item, lalu pilih teman yang ikut memesan.", "Kirim rincian ke 5 teman").
- **Privacy/trust reassurance copy is bilingual and repeated at point of relevance**, not centralized in one settings/about screen — restate it contextually (permission screen, intro screen, send screen, close-session screen) in the language the surrounding screen is using.
- Uppercase + letter-spacing is reserved for the mono "printed" labels (§3) — don't uppercase regular sans body copy for emphasis; use bold instead.

---

## 8. Open conflict to resolve before implementation

The "send notification" screen mockup includes a **"Nomor Rekening & QRIS"** info box stating the recipient's bank account/QRIS will be auto-attached to the WhatsApp draft. This directly contradicts [PRD_SplitBill_App_v3.md](PRD_SplitBill_App_v3.md) §6, §7, and §9.6, which state payment-destination collection was **deliberately and permanently removed** from scope for security reasons (unofficial WhatsApp gateway + sensitive financial data = explicit non-goal).

Do not implement that box as shown. Either:
- the mockup is stale/aspirational and should be dropped from the send screen entirely (matches current PRD), or
- the product decision has actually changed and the PRD needs a corresponding update first (§17 already flags "is no payment destination at all too bare?" as an open question — this would be resolving it in the opposite direction from what's currently written).

Flag this to the user rather than silently picking one when building the send/notification screen.
