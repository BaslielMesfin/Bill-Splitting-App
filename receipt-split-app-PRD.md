# PRD: Fair Split — Ethiopian Receipt-Splitting App

## 1. Problem Statement

Groups splitting a restaurant bill in Ethiopia run into a specific, recurring math problem: everyone ordered different things, so the bill can't be divided evenly by headcount. Manually allocating each person's share of **service charge** and **15% VAT** proportional to what they actually ate is tedious to do by hand, and rounding errors mean the individual shares never sum exactly to the total — so someone always ends up covering a leftover few birr in cash.

This app exists to solve exactly that: photograph the receipt, assign items to people (including shared items), and get an exact, penny-accurate breakdown of what each person owes — with the rounding math handled correctly so it always reconciles to the total.

## 2. Target User (v1)

- Groups of friends/colleagues in Addis Ababa splitting a restaurant bill.
- One person (the "payer") does the assignment on their own phone; results are shared with the group as text or an image, not synced live to everyone's device.
- Receipts follow the standard ERCA fiscal receipt format (fixed layout conventions: SUBTOTAL, Service Chrg, TXBL1, TAX1 15%, TOTAL) — this is a narrower, more tractable OCR problem than "any receipt from any country," and it's the basis for launching as a focused local tool rather than a generic global bill-splitter.

## 3. Explicitly Out of Scope for v1

- Multi-device real-time collaboration (everyone tapping their own items simultaneously).
- Actual payment processing / money movement (Chapa, Telebirr, etc.) — v2 candidate only.
- Multi-currency or non-Ethiopian tax formats.
- User accounts, login, or receipt history sync across devices.
- Support for handwritten or non-fiscal (hand-written) receipts.

Do not build any of the above in v1. Flag it in code comments as a v2 seam if it's cheap to leave room for, but don't implement it.

## 4. Core User Flow

1. Payer opens app, taps "New Split" — camera opens immediately, no home screen delay.
2. Alignment guide overlays the live camera view with a hint ("Fit the receipt in frame — good lighting helps"). Payer manually taps the shutter (no auto-capture — a deliberate, in-focus shot matters more than speed, since a bad photo wastes an API call and gives a bad parse).
3. Immediate preview: "Retake" / "Use Photo" — catches obvious failures (blur, cut-off receipt, glare) before it reaches the parsing step.
4. On "Use Photo," image uploads to the backend proxy, which forwards it to the vision API with a structured-extraction prompt (see §6). Loading state: "Reading receipt…"
5. App runs an automatic validation check (do items sum to subtotal, does tax match 15% of taxable base, etc.). If it checks out, go straight to Review, fully pre-filled. If not, still go to Review but visually flag the specific mismatched field(s).
6. **Review & Edit Receipt**: editable table of parsed line items + subtotal/service/tax/total. Every field is tappable and editable, even ones that parsed cleanly — vision models occasionally misread a digit on a curved thermal receipt, and the payer needs a fast correction, not a leap of faith. Do not treat parsed output as ground truth without this confirmation/edit step.
7. **Add participants**: payer sees their saved "recent people" as tappable chips (see §8, Participants screen) and taps everyone in this group, or adds new names on the fly. Each participant has a required first name and an optional last name (used for disambiguation when two people share a first name, e.g. "Abebe" vs "Abebe K.").
8. **Assign items**: for each line item, payer taps which participant it belongs to. For any line item with quantity > 1, the item expands into individual units (e.g. 3 separate "Novida" chips) so the payer can assign each unit to a different person rather than being forced to split the whole line evenly. For shared items, a unit or item can be assigned to multiple participants with a default equal split, adjustable to a custom ratio. An "unassigned items" counter shows progress until everything is accounted for.
9. App computes each person's exact share (§7) and displays a per-person summary.
10. Payer can share the summary as formatted text (copy to clipboard / native share sheet) — no payment integration in v1.

**Failure path**: if the photo comes back completely unreadable (no signal, quota exhausted, garbage response), skip straight to a clear error state — "Couldn't read this receipt clearly. Retake photo, or enter items manually" — both options one tap away, so the flow never dead-ends.

## 5. Data Model

```
Receipt {
  id: string
  imageUri: string
  merchantName?: string
  currency: "ETB"
  lineItems: LineItem[]
  serviceChargeAmount: number   // absolute value, not %
  taxRate: number               // default 0.15, editable
  taxAmount: number             // as printed, used to cross-check computed value
  subtotal: number
  total: number
  createdAt: timestamp
}

LineItem {
  id: string
  description: string
  quantity: number
  unitPrice: number
  amount: number                // quantity * unitPrice, should reconcile to receipt
  assignments: Assignment[]     // one item can have multiple assignees
}

Assignment {
  participantId: string
  share: number                 // fraction 0–1, all assignments for a line item must sum to 1
}

Participant {
  id: string
  firstName: string
  lastName?: string             // optional, used for disambiguation (e.g. duplicate first names)
}

SplitResult {
  participantId: string
  itemSubtotal: number
  serviceChargeShare: number
  taxShare: number
  totalOwed: number              // decimal, precise to the cent — NOT rounded per-person
}
```

**Recent People / Groups (local device storage, not part of a single Receipt):**

```
SavedPerson {
  id: string
  firstName: string
  lastName?: string
  lastUsedAt: timestamp          // powers "recent people" chip ordering
}
```

## 6. Receipt Parsing (Gemini Vision API, free tier)

Send the receipt photo to the Gemini API (multimodal, free tier — no credit card required as of 2026) with a prompt that forces strict JSON output matching the `Receipt` shape above. Key implementation requirements:

- **Never call Gemini directly from the mobile app with an embedded API key** — anyone could extract it from the app binary and burn your free quota. Route every call through a thin backend proxy (a single serverless function on Cloudflare Workers or Vercel, both free tier) that holds the key server-side and simply forwards image-in/JSON-out.
- **Prompt must instruct the model to return ONLY valid JSON, no markdown fences, no preamble.**
- Include few-shot guidance in the prompt describing the expected ERCA receipt layout (Description / Qty / Price / Amount columns, SUBTOTAL, Service Chrg, TXBL1, TAX1 15%, TOTAL) so the model knows what to look for.
- The model should return numbers as numbers, not strings, and should not invent items or amounts it can't read — if a field is unreadable, it should return `null` for that field rather than guessing, so the app can prompt the user to fill it in manually.
- Always validate after parsing: do line items sum to the subtotal? Does subtotal + service charge = taxable base? Does taxable base × tax rate ≈ tax amount? If validation fails, show the raw parsed values with a warning banner and let the payer correct fields manually rather than silently trusting a bad parse.
- Design this as a single request/response call (image in, JSON out) — no need for multi-turn conversation or tool use for this step.

**Known constraint of the free tier — revisit if this grows beyond friends:** Gemini's free quota is per Google Cloud project, not per app user. For a friend-group app with occasional use, this is a non-issue. If this ever scales to public use, the shared daily quota will become a real bottleneck — the fix at that point is either asking users to bring their own free Gemini API key, or moving to a paid tier. Not a v1 concern, but don't be surprised by it later.

## 7. Splitting Algorithm (this is the core value of the app — get it exactly right)

**Step 0 — round the target total up, before splitting anything:**

`splitTarget = ceil(receipt.total)` — round the real total (e.g. 2656.60) up to the next whole birr (2657). This rounded-up value, not the original decimal total, is what all shares must reconcile to. The difference between `splitTarget` and `receipt.total` (e.g. 0.40) is a small buffer absorbed collectively by the group — nobody is individually shorted, and there's no ambiguity about who "covers the gap," which was the original problem this app exists to solve.

Given assigned line items per participant:

1. **Per-person item subtotal** = sum of (line item amount × participant's share) across all their assigned/shared items.
2. **Service charge allocation**: `person.serviceChargeShare = (person.itemSubtotal / receipt.subtotal) * receipt.serviceChargeAmount`
3. **Taxable base per person**: `person.taxableBase = person.itemSubtotal + person.serviceChargeShare`
4. **Tax allocation**: `person.taxShare = person.taxableBase * receipt.taxRate`
5. **Raw total per person** (before final reconciliation): `person.itemSubtotal + person.serviceChargeShare + person.taxShare`

**Important**: individual `SplitResult.totalOwed` values remain decimal/cent-precise (e.g. 531.51) — do NOT round individual shares to whole numbers. Only the target they reconcile to (`splitTarget`) is rounded up; the per-person breakdown stays exact to the cent.

### Rounding reconciliation (largest remainder method, applied against `splitTarget`)

1. Round every person's raw total down to 2 decimals, keep track of the remainder (the fractional cents dropped).
2. Compute `difference = splitTarget - sum(all rounded-down totals)` — note this uses `splitTarget` (the rounded-up whole number), not the original decimal `receipt.total`.
3. Sort participants by the size of their dropped remainder, descending.
4. Distribute 1 cent at a time to the participants with the largest remainders until `difference` is exhausted.
5. Final per-person totals (still decimal-precise) now sum exactly to `splitTarget`. Never leave an unallocated remainder — this must reconcile every time, not "usually."

Write this as a pure, unit-testable function: `computeSplit(receipt, participants, assignments) -> SplitResult[]`, independent of any UI or networking code, so it can be tested against the worked example below and edge cases without needing the parsing step at all.

### Worked test case (use as a unit test fixture)

From the source receipt used to design this app:
- Subtotal: 2227.69, Service Charge: 82.40, Taxable base: 2310.09, Tax (15%): 346.51, Total: 2656.60 → `splitTarget` = 2657
- Build a test with 2–3 fake participants and hand-assigned item splits, and assert the computed per-person decimal totals sum exactly to 2657 (not 2656.60).

## 8. Screens (v1)

1. **Home** — "New Split" button, (optionally) list of recent local splits.
2. **Capture** — camera with alignment guide overlay, manual shutter, retake/use-photo confirmation.
3. **Review & Edit Receipt** — editable table of parsed line items + subtotal/service/tax/total, with a validation warning if the numbers don't reconcile.
4. **Participants** — shows saved "recent people" as tappable chips (ordered by most recently used), tap to select who's in this split, "+ Add new" for anyone not yet saved. First name required, last name optional (used for disambiguating duplicate first names).
5. **Assign Items** — for each line item, select one participant; items with quantity > 1 expand into individual unit chips for per-unit assignment; shared items/units support multi-select with adjustable split ratios; an unassigned-items counter tracks progress.
6. **Summary** — per-person totals (decimal-precise, reconciled to `splitTarget`), itemized breakdown on tap, share button.

### Design direction (Apple-esque, clean, fast)

- Generous white space, one primary action per screen — no competing calls to action.
- Large tap targets (minimum ~44x44pt), especially on the Assign Items screen where taps need to be fast and unambiguous.
- Single accent color used only for primary actions/selected states; everything else neutral (grays/whites) — avoid multiple competing colors.
- Native-feeling depth: subtle card shadows, rounded corners, spring-based screen transitions (react-native-reanimated) under ~250ms — smooth, not decorative.
- Fast output matters more than polish: prioritize smart defaults (recent-people chips, sensible default equal-split ratios) over elaborate animation, since speed to a finished split is the actual success metric (§10).

## 9. Tech Stack Recommendation

- **Framework**: React Native (Expo) — one codebase, targeting **Android first** for v1 (per current decision; easy to extend to iOS later without a rewrite since it's the same codebase).
- **Vision/parsing**: Gemini API (free tier, multimodal) called through a thin serverless proxy (Cloudflare Workers or Vercel Functions, both free tier) — never embed the API key directly in the app. See §6 for the free-tier scaling caveat.
- **State management**: Zustand — lightweight, sufficient for an app this size.
- **Storage**: local device storage only (Expo SQLite or AsyncStorage) for recent participants/saved groups and optional split history — no backend database, no login, consistent with the no-accounts requirement.
- **Animations**: react-native-reanimated for smooth, native-feeling screen transitions.
- **Typography**: Expo Google Fonts (Inter) — clean, free, reads close to native system fonts without licensing concerns.
- **Icons**: lucide-react-native for a consistent, minimal icon set.

## 10. Success Criteria for v1

- A user can photograph a real ERCA-format receipt and get correctly parsed line items at least ~85% of the time without manual correction (measure this against a small test set of real receipts before considering v1 done).
- The split computation always reconciles exactly to `splitTarget` (the rounded-up total) — this should be enforced by unit tests, not just manual spot-checks.
- End-to-end flow (photo → assigned items → summary) completable in under 2 minutes for a 5-person, 5-item bill.

## 11. Open Questions / Assumptions to Revisit

- What happens when a receipt has a discount line, multiple tax rates, or a service charge expressed as a percentage rather than a fixed amount printed on the receipt? v1 should handle the common case shown above; flag anything that doesn't match this shape for manual entry rather than guessing.
- Should "recent splits" persist locally between app sessions? Not required for v1 but cheap to add if using SQLite from the start.
- Chapa/Telebirr "request payment" integration is a natural v2 feature once the split math is solid — don't build it now, but keep the `SplitResult` data model clean enough that a payment request could be generated from it later without restructuring.
- iOS support is deferred but not architecturally blocked — React Native/Expo means adding it later is a build-target change, not a rewrite, if this expands beyond the initial Android/friend-group use.
- Revisit the Gemini free-tier quota constraint (§6) if usage grows beyond a small friend group — this is the one part of the stack with a real scaling ceiling baked in from day one.
