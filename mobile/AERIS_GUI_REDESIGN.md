# AERIS 2.0 — "Flow" · Complete GUI Redesign Specification

> **What this is:** the full blueprint for AERIS's next-generation interface. Where `AERIS_APP_GUIDE.md` documents the app *as it is*, this file specifies the app *as it should look and feel* — a ground-up visual and experience redesign that keeps **every existing feature** (each section maps back to current functionality) while elevating it to a modern, fluid, delightful fintech experience. Built for **Light + Dark (incl. true-black OLED)** from the first pixel.

---

## 1. Vision & Principles

**"Your money, at a glance, in flow."**

1. **One-glance clarity** — the single most important number on any screen is unmissable within 300 ms of landing. Everything else recedes.
2. **Zero-friction capture** — adding money data is never more than 2 taps or 1 sentence away from anywhere.
3. **Calm by default, alive on touch** — static screens are serene; every touch answers with motion + haptic. No idle animation noise.
4. **Money colors are sacred** — green = in, red = out, amber = at-risk. These never decorate; they only inform.
5. **Progress is visible** — streaks, levels, gardens, and rings make discipline *feel* rewarding everywhere, not only in a gamification tab.
6. **Private by design** — privacy controls (mask amounts, app lock) are one tap away on every screen, and the UI brags about encryption at the right moments.

---

## 2. The "Flow" Design Language

### 2.1 Color system

Three full themes from one token set:

| Token | Light | Dark | OLED (true black) |
|---|---|---|---|
| `bg/canvas` | `#F6FAFA` | `#0D1518` | `#000000` |
| `bg/surface` (cards) | `#FFFFFF` | `#162125` | `#0A1214` |
| `bg/surface-raised` (sheets, dialogs) | `#FFFFFF` | `#1C292E` | `#101B1E` |
| `brand/primary` | `#0EA5A4` | `#2DD4BF` (brighter for dark) | `#2DD4BF` |
| `brand/on-primary` | `#FFFFFF` | `#04302E` | `#04302E` |
| `money/in` | `#16A34A` | `#4ADE80` | `#4ADE80` |
| `money/out` | `#DC2626` | `#F87171` | `#F87171` |
| `state/risk` | `#D97706` | `#FBBF24` | `#FBBF24` |
| `text/primary` | `#0B1416` | `#ECF4F4` | `#ECF4F4` |
| `text/secondary` | `#5B6B6E` | `#93A6A8` | `#93A6A8` |
| `line/divider` | `#E5EDED` | `#23343A` | `#1A282C` |

**Gradients (identical across modes, white text):**
- `grad/hero` teal `#0EA5A4 → #0F766E` — hero spend, success moments
- `grad/streak` ember `#EA580C → #F97316` — active streak surfaces
- `grad/calm` violet `#8B5CF6 → #6366F1` — voice, AI, empty-streak
- `grad/midnight` `#1E293B → #0F172A` — Wrapped, Future Self (dark storytelling surfaces)

**Chart palette:** the existing 12 hues, but with a **−12% saturation variant for dark mode** so charts glow instead of scream. Every chart color ships as a light/dark pair.

**User accent:** the accent picker (Customize) re-seeds `brand/primary`. All components must derive from tokens so any accent works in both modes.

### 2.2 Typography

A two-face system:

- **Display: "Clash Grotesk" / fallback Manrope** — money figures, hero numbers, level titles. Weights 600–800.
- **Text: Inter** — everything else. Weights 400–700.

| Style | Size/weight | Use |
|---|---|---|
| `display/xl` | 44/800, −1% tracking, tabular numerals | Hero spend amount |
| `display/l` | 32/800 | Card-level money figures |
| `display/m` | 24/700 | Section heroes, ring center |
| `title` | 17/700 | Card titles, list headers |
| `body` | 15/450 | Default copy |
| `caption` | 12/500 | Metadata, axis labels |
| `chip` | 11/700, +4% tracking, uppercase | Status chips |

**All money figures use tabular (monospaced) numerals** so counts animate without jitter.

### 2.3 Space, shape, depth

- **8-pt grid**; screen gutter 20; card padding 18; list row height 64.
- **Radius scale:** chips 10 · cards 24 · sheets 28 (top) · hero surfaces 28 · FAB squircle 20.
- **Depth = blur, not shadow.** Light mode: 1 dp tinted shadow. Dark mode: surfaces separate by tone only. Sheets and the nav bar use **frosted glass** (background blur 24, surface at 85% opacity) — the signature "Flow" texture.
- **Hairline borders** (`line/divider` at 60%) on glass surfaces in dark mode for edge definition.

### 2.4 Iconography & illustration

- Icon set: **rounded, 2 px stroke, filled-on-active** (Phosphor/Lucide style). Money-specific glyphs custom: rupee-wave, streak-flame, boss-shield, garden-sprout.
- Aeris mascot upgraded to a **rigged vector character** with 6 moods (happy, neutral, worried, alert, excited, sleeping) + blink/idle micro-loops *only while on-screen interactions are happening*.
- Empty states get bespoke spot illustrations (same line style, brand-tinted) — never a grey icon on grey.

---

## 3. Motion System

| Pattern | Spec |
|---|---|
| Screen enter | Shared-axis horizontal, 280 ms, emphasized-decelerate |
| Sheet | Spring up (stiffness 380, damping 32) with glass fade-in |
| Section entrance | Once per session: fade + 12 px rise, 320 ms, 40 ms stagger between cards |
| Money count | Tween previous→new, 600 ms; digits roll vertically (slot-machine) on the hero |
| Ring/bars fill | 900 ms easeOutCubic, draws on first view only |
| Press feedback | Scale 0.97 + soft haptic (light impact) on every card/chip |
| Success | 600 ms radial "ink bloom" of `money/in` from tap point + medium haptic |
| Streak milestone / boss defeat / goal hit | Full-screen confetti burst (1.2 s) + success haptic — the only big animations allowed |
| Skeletons | Shimmer 1.4 s loop, token-tinted; never spinners on content surfaces |

**Reduced-motion setting honored everywhere** (entrances become fades, confetti becomes a badge pulse).

---

## 4. New Navigation Architecture

**From 7 cramped tabs → 4 tabs + center action + hub.**

```
┌──────────────────────────────────────────────┐
│                                              │
│                 (content)                    │
│                                              │
├──────────────────────────────────────────────┤
│   Home     Activity    [ + ]   Insights   Me │   ← frosted-glass bar
└──────────────────────────────────────────────┘
```

| Slot | Contains | Replaces |
|---|---|---|
| **Home** | Dashboard (with budgets + streak inline) | Home, Budgets entry |
| **Activity** | Segmented: **Transactions · Lent · Subscriptions** | Txns, Lent tabs |
| **[ + ] center FAB** | Radial quick-action: 🎤 Voice · ⌨️ Quick add · ↓ Expense · ↑ Income · 🤝 Lent entry | Both old FABs |
| **Insights** | Segmented: **Charts · AI** (analytics + predictions + assistant entry) | Charts, AI tabs |
| **Me** | Profile + Aeris World + Goals + Settings hub | Me tab |

- The **center FAB** is a brand-gradient squircle floating half-above the bar. Tap → 5 actions fan out radially with stagger; long-press → goes straight to Voice.
- Bar is glass; active tab = filled icon + label + 3 px brand underline dot. Inactive = outline icon only.
- **Budgets** live as a full section inside Home (see 5.6) with a "Manage budgets" push screen — losing the dedicated tab loses nothing.

---

## 5. Screen-by-Screen Redesign

### 5.0 Splash & Onboarding

- **Splash:** true-black canvas (both modes), the rupee-wave mark draws itself as a single stroke (800 ms), wordmark fades in beneath, progress hairline at bottom. < 2 s feel.
- **Onboarding v2:** 4 full-bleed gradient panes with parallax illustrations — (1) "Money tracks itself" SMS demo with a fake message morphing into a transaction tile; (2) "Locked to everyone but you" encryption animation (card folds into a vault); (3) "Make saving a game" mascot + streak demo; (4) **personalisation step (new):** monthly income + one-slider starter budget → lands on a pre-populated dashboard. Skip is always visible.

### 5.1 Auth

- Single card on a soft gradient canvas. Email/password with inline validation; password field has show/hide.
- Sign-up flows into the **Recovery Key ceremony**: the key renders as 6 chunked monospace groups on a card that *looks like a physical key card*; actions: Copy · Save image · "I stored it" checkbox (button disabled until checked, with a 3 s read delay).
- Biometric login chip ("Unlock with fingerprint") appears on return visits when app lock is on.

### 5.2 HOME — "Today"

Layout (scroll):

1. **Status row** — avatar (tap → profile sheet) · "Good morning, Shivang" · privacy-eye (global mask) · bell.
2. **Hero spend module** (glass on `grad/hero`): "Spent this month" → `display/xl` rolling-digit amount → row of three chips: **MoM ↓12%** (green) · **🔥 14-day** streak chip → tap opens streak sheet · range chip (This month ▾ — bottom sheet picker, replaces the old corner selector).
3. **Budget ring strip** — horizontal: the **total budget ring** (large, % center, red-shift past 80%) + mini category rings for the top 3 budgets. "Manage →" pushes Budgets screen. **If no budget:** the ring strip becomes a single "Set a monthly budget" pill card with the piggy illustration → amount sheet (unchanged logic, `total_monthly`).
4. **Streak & check-in card** (`grad/streak` when alive): fire + day count + S-anchored week dots (done ✓ / today ring / future dim) + **"Check in" button morphs into the day's reward** (+15 ✦ Aura) with ink-bloom on claim. Replaces separate check-in + streak banner: one card, one purpose.
5. **Aeris strip** — the mascot, current level ring, a one-line live insight (from the AI engine), tap → Aeris World. Mood = real finances.
6. **Forecast chip-card** — "On pace for ₹18,400 this month · 2 budgets at risk" (amber edge-glow when risky) → Insights.
7. **Recent activity** — 5 latest transaction rows + "All activity →".
8. **Customizable extras** (user-ordered via Customize): Goals progress card · Subscriptions due card · Quote card.

**Interactions:** pull-to-refresh = mascot peeks down and winks; every card long-press → "Hide card / Reorder" mini-menu (new).

### 5.3 ACTIVITY — Transactions · Lent · Subs

Top segmented control (glass pill): **Transactions | Lent | Subscriptions**.

**Transactions pane**
- **Search bar (new):** merchant/note/amount with recent-search chips and instant results.
- **Filter row:** chips — All · In · Out · Category ▾ (bottom-sheet grid) · Account ▾.
- **Smart list:** day headers with day-total ("Tue 10 Jun · −₹1,240"); rows = category squircle icon · merchant · source chip (SMS/voice/manual) · signed tabular amount. **Swipe right = recategorize** (teaches the rule) · **swipe left = delete** (undo snackbar).
- Tap → **Detail sheet** (not a page): amount hero, category pill (tap to change), date, account, note, raw SMS body in a collapsible, Delete / Edit actions.
- Floating **month summary pill** while scrolling ("June · in ₹52K · out ₹38K").

**Lent pane** (full feature set retained + upgrades)
- Header: dual stat — Owed to you / You owe.
- Pending cards with friend avatar-initials, amount, age ("12 days ago"), note; **progress bar for partial repayments (new)**.
- Actions on tap-sheet: Mark received · **Add partial payment (new)** · **Remind via WhatsApp/UPI-link share (new)** · Edit · Delete. Settled section collapses by default.

**Subscriptions pane**
- Auto-detected recurring payments as cards: logo-letter, cadence chip (Monthly/Yearly), next-due countdown ring, monthly cost. Sum header: "₹2,340/month in subscriptions."

### 5.4 [+] Capture flows

- **Voice:** full-screen `grad/calm`, breathing orb that ripples with amplitude; live transcript types beneath; parsed entries appear as editable mini-cards stacking up; "Save all (3)" CTA. Cancel = swipe down.
- **Quick add:** single input ("spent 200 on chai yesterday…") with mic toggle; parsed preview renders as a real transaction tile to confirm; **calculator-pad (new)** supports `250+120`.
- **Add expense/income:** one sheet, segmented In/Out, amount pad first (auto-focus), category grid (8 visible + expand), date chip row (Today · Yesterday · pick), note, account.
- **Lent entry:** same sheet style, segmented "I gave / I borrowed", name (with **contact autocomplete — new**), amount, note, optional due date (new).

### 5.5 INSIGHTS — Charts · AI

Segmented: **Charts | AI**.

**Charts pane** (all 8 existing charts, redesigned)
- Sticky range pill at top.
- **Category donut** — thicker ring, clock-face leader-line labels (angled radial + stub, as currently implemented), tap = slice pop + glass detail card morphs in below (amount, %, count, avg, drill-in).
- **Daily bars** — rounded gradient bars, today highlighted, drag-scrub tooltip.
- **Heatmap** — GitHub-style month grid with mode-aware ramp (light: teal ramp; dark: ember ramp).
- **Trend** — line with zoom/pan/crosshair, month markers, average guide-line.
- **In vs Out** — twin horizontal bars + Net pill.
- **Top merchants** — bars with merchant-letter squircles.
- **Cumulative** — area chart with budget guide-line overlay (new: shows the cap as a dotted line).
- **Radar** — top-6 category polygon.
- Each chart card has a **⤢ expand** to full-screen landscape (new) and a share-as-image action (new).

**AI pane**
- **Mascot hero** speaking the top recommendation (tap to cycle).
- Cards: Month estimate · Budget projections (per-budget risk meters) · Anomalies (pulse-bordered) · Recurring detections · Recommendations (severity-tinted left edge) · Cashflow runway bar.
- **"Ask Aeris" pinned input** at bottom → full chat (typing indicator, suggested question chips, answers can embed mini-charts — new).

### 5.6 Budgets (push screen from Home)

- Hero: total budget ring + spent/left.
- **Per-category cards:** icon, cap, progress (amber > 80%, red over), "ends in N days" pace hint.
- **Auto-suggest** banner: "Let Aeris draft budgets from your history" → checklist sheet of proposed caps (EMA-based, tidy-rounded) with toggles → Apply.
- Add/edit = sheet with category grid + amount pad. Delete with undo.

### 5.7 ME — hub

- **Identity header:** large avatar (tap → View / Change photo — retained), name, email, income chip, **level progress ring around avatar (new)**.
- **Grid of destinations (2-col):** Aeris World · Goals · Wrapped · Accounts · Import statement · SMS review · Settings — each a square tile with icon + one-line description.
- Sign out at the bottom, destructive-styled, confirm dialog.

### 5.8 Aeris World (gamification hub)

- **Hub:** parallax header with the mascot in its current evolution + Aura balance counter (✦) + level bar.
- **Avatar store:** carousel of skins, locked ones show Aura price, "Equip" with bloom.
- **Challenges:** active cards with live progress and time-left ring; create-challenge wizard (template chips: "No X for N days", "Keep CAT under ₹N").
- **Bosses:** each budgeted category as a monster card with a shield (HP = cap remaining); hits animate as spend chips away; month-end victory = confetti + Aura.
- **Garden:** full-bleed canvas, plants per ~120 Aura, day/night matches theme, gentle sway; new plants sprout with a grow animation; share-screenshot button.
- **Future Self:** scrolling story of projected savings ("At this pace: ₹86K saved by Dec") on `grad/midnight`.
- **Customize:** card show/hide + drag-reorder (new) + accent color wheel + **theme: Light / Dark / OLED / System (new)**.

### 5.9 Wrapped

- Full-screen story pager on `grad/midnight`: top category, biggest splurge, busiest day, best no-spend streak, total saved — each pane a bold typographic poster with one stat. Share-as-image per pane. Progress dots top; tap sides to navigate.

### 5.10 Settings

Grouped glass sections:

1. **Automation** — SMS auto-read toggle (with restricted-settings guidance flow retained), Backfill 90 days (progress + clear result messaging retained), Background activity (OEM guidance).
2. **Appearance (new)** — Theme: System/Light/Dark/OLED · Accent color · Reduce motion.
3. **Alerts** — Smart reminders, budget alerts, check-in reminder (individual toggles — new granularity).
4. **Privacy & Security** — App lock, Mask amounts default, Encrypt legacy data, Recovery key re-display (auth-gated, new), Blocked senders list (managed view).
5. **Data** — Export Excel, Encrypted backup, Restore, **Export CSV (new)**.
6. **About** — version, licenses, privacy policy.

---

## 6. Component Library ("Flow Kit")

Every component specced in light + dark + OLED:

`HeroModule` · `StatChip` (signed money chip, the universal money atom) · `RingGauge` (sizes S/M/L, risk-shift) · `StreakDots` (7, Sat-anchored) · `GlassCard` · `GradientCard` · `SegmentedPill` · `FilterChipRow` · `TxnRow` (+swipe states) · `DetailSheet` · `AmountPad` (with inline math) · `CategoryGrid` · `RadialFab` (5-action fan) · `MascotAvatar` (6 moods × 4 evolution stages) · `ProgressBanner` · `InsightCard` (severity edge) · `BossCard` · `PlantSprite` set · `StoryPane` (Wrapped) · `EmptyState` (illustration + one CTA) · `SkeletonRow/Card` · `ConfettiBurst` · `UndoSnackbar` · `CoachTooltip`.

---

## 7. Haptics Map

| Event | Haptic |
|---|---|
| Card/chip press | Light impact |
| Save / check-in / mark-received | Medium impact + ink bloom |
| Streak milestone, boss defeat, goal complete | Success pattern (double tick) |
| Delete / destructive confirm | Heavy single |
| Chart scrub | Selection ticks per data point |
| Error | Notification-error buzz |

---

## 8. Accessibility (non-negotiable)

- Contrast ≥ 4.5:1 for text in all three themes (chips ≥ 3:1 with weight compensation).
- Dynamic type to 130% without truncating money figures (figures scale, layouts reflow).
- Every chart has a **spoken summary** semantic label ("Food is your top category at 34%, ₹4,300").
- Touch targets ≥ 48 dp; swipe actions duplicated in the detail sheet for switch-access users.
- Reduce-motion variant for every animation listed in §3.
- Privacy-mask state announced to screen readers as "amounts hidden".

---

## 9. Feature → Redesign Traceability

| Existing feature | Lives in 2.0 |
|---|---|
| SMS auto-import + review + blocked senders | Settings/Automation + SMS Review (unchanged flows, new chrome) |
| Voice / quick add / manual add | [+] radial FAB |
| Privacy eye | Status row, global |
| Streak + check-in + week dots | Home card 4 (merged) |
| Total + category budgets, auto-suggest | Home ring strip + Budgets push screen |
| Donut/bars/heatmap/trend/in-out/merchants/cumulative/radar | Insights · Charts |
| Predictions/anomalies/recurring/recommendations/cashflow | Insights · AI |
| Assistant chat | Insights · AI pinned input |
| Lent ledger | Activity · Lent (+ partial payments, reminders, due dates) |
| Subscriptions | Activity · Subs |
| Goals | Me grid + Home card |
| Aeris World (store/challenges/bosses/garden/future/customize) | §5.8, all retained |
| Wrapped | §5.9 |
| Accounts, statement import | Me grid |
| Excel export, backup/restore | Settings/Data |
| App lock, encryption, recovery key | Settings/Privacy + auth ceremony |
| Home widget (streak + budget left) | Unchanged data; restyle to glass card with ring |
| Dark/light | Now three themes + in-app toggle |

Nothing is removed; everything is re-homed with intent.
