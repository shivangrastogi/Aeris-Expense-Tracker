Design a complete, production-ready design system for **AERIS**, a flagship Android personal-finance app for India. This system will be reused for every screen of the app, so make it thorough, consistent and buildable. Show it as a design-system page (tokens + components), in both Dark and Light themes side by side.

## Brand & mood
- Name: AERIS. Logo: a steel-blue "A" whose crossbar is a rising line ending in a dot (growth). Use the uploaded app icon.
- Mood: flagship fintech — the polish of Apple Wallet, the clarity of Revolut, the restraint of Nothing OS. Confident, calm, premium, trustworthy. Private by design (end-to-end encrypted).
- Hard rules: no neon, no glows, no rainbow gradients, no cartoon mascots, no emoji in UI chrome. Colour only where it means something.
- Signature motif: the logo's **rising line + dot**. Use it subtly — progress bars that end in a dot, trend sparklines, the active-tab indicator, loading states. Never decorative clutter.

## Colour tokens (give exact hex for both themes)
Dark ("Graphite") — the hero theme:
- background #0E1013 · surface #16191E · surface-raised #1D2127 · surface-sunken #0A0C0F · hairline #2A2F37
- text-primary #ECEEF1 · text-secondary #9AA2AE · text-tertiary #6B7380
- accent (steel blue) #6E9EE0 · accent-pressed #5A8AD0 · on-accent #0E141C · accent-soft (12% tint)
- hero gradient (only on the main balance/spend card and primary CTA): #7AA6DA → #4F86C6, very soft
- semantic: success #5CB88A · warning #D6A453 · danger #E0766D · info #7AA6DA
Light ("Porcelain"):
- background #F4F5F7 · surface #FFFFFF · surface-raised #FFFFFF with soft shadow · hairline #E3E6EB
- text-primary #12161C · text-secondary #5E6978 · text-tertiary #8A93A0
- accent #2F66AE · on-accent #FFFFFF · semantic: success #2E8656 · warning #A9711C · danger #BF433A
- Money rules: money IN = success green with "+"; money OUT = primary text colour with "−" (spending is normal, not an alarm); danger red only for over-budget / overdue / destructive.
- Category palette (muted, colour-blind safe, 8 hues in this fixed order): steel #5F8CCB, terracotta #C97A52, teal #2FA287, ochre #B0902F, rose #C9789A, sage #5F9A4C, iris #8A7ED3, brick #C96A66 — plus neutral grey #8B93A1 for "Other". Category icons sit in a 40 dp rounded square filled with the hue at 14% and the icon in the full hue.

## Typography (Plus Jakarta Sans, tabular numerals for all money)
- Display-amount 44/48 Bold (hero spend), Amount-L 28/32 Bold, Amount-M 20/24 Semibold
- Headline 24/30 Bold (−0.5 tracking) · Title 18/24 Semibold · Body 15/22 Regular · Body-S 13/18 · Label 12/16 Semibold · Overline 11/14 Bold +0.8 tracking caps
- Show the ₹ symbol slightly smaller and lighter than the digits in big amounts.

## Shape, space, depth
- 8 dp grid; screen side margin 20 dp; card padding 16–20 dp; section gap 24 dp.
- Radius: cards 20 · sheets 28 (top) · buttons 16 · chips/pills 12 · inputs 14 · small tiles 12.
- Depth: in Dark, depth by tone (surface → raised) plus a 1 dp hairline, no shadows. In Light, one soft shadow (y 6, blur 18, 8% ink) for cards; sheets slightly more.
- Glass: only the floating bottom navigation and bottom sheets may use a subtle frosted blur. Nothing else.

## Components — show every variant and state (default, pressed, disabled, focused, loading, error)
1. Buttons: primary (accent fill), secondary (tonal), outline, text, destructive, icon button, floating "+" action (56 dp, hero gradient, opens radial quick-add).
2. Bottom navigation: floating pill, 4 tabs (Home, Activity, Insights, Me) with a centre gap for the "+"; active tab = accent icon + label + the rising-line indicator.
3. Top app bars: large-title (collapses on scroll), standard with back, with actions (text actions, not just icons).
4. Cards: base card, hero card (gradient sheen), stat tile, list-group card (iOS-style grouped rows), alert card (warning/danger tint), empty-state card.
5. List rows: transaction row (category tile, merchant, sub-line "Food · 2:07 PM · PhonePe", amount right with +/−, optional "Review" pill), settings row (icon, title, subtitle, chevron / switch / value + dropdown), person row (avatar initial, name, amount, action).
6. Inputs: text field, amount field (big centred ₹ amount with calculator keys + − × ÷), search field, dropdown, date/time chips (Today, Yesterday, Pick date), segmented control, switch, checkbox, slider.
7. Chips: filter chips, choice chips (category chips with icon), status pills (Pending amber, Paid green, Overdue red, Review accent).
8. Sheets & dialogs: bottom sheet with drag handle, confirm dialog, destructive confirm (type-to-confirm), recovery-key dialog (key in 4-char monospace blocks + Copy + "I've saved it" checkbox).
9. Feedback: toast/snackbar (floating, with action), inline banner (info/warning), progress bar (rising line + dot), circular ring (budget ring with category icon in centre), skeleton loaders, pull-to-refresh.
10. Data viz: donut (category split, 2 dp gaps, centre total), bar chart (rounded 4 dp tops), line/area trend (2 dp line, soft fill), sparkline, calendar heat map, progress ring. Minimal axes, no heavy grid, legends with direct labels.
11. Avatars & tiles: initial avatar, category tile, bank/account tile (masked "••4521"), app-source badge (GPay, PhonePe, Paytm as small monochrome glyphs).
12. Privacy: every amount has a "hidden" variant (₹••••) for the hide-amounts mode.

## Motion (document as specs)
- Standard ease: cubic(0.2, 0, 0, 1), 250 ms; enter 300 ms; exit 200 ms.
- Amounts count up on first show (600 ms); rings and bars fill once.
- Radial "+" menu: actions fan out on an arc with 30 ms stagger; the "+" rotates to "×".
- Sheets spring up; list items fade + slide 8 dp; tab switches cross-fade.
- Respect "reduce motion": no count-ups or springs.

## Accessibility
- Text contrast ≥ 4.5:1, large numbers ≥ 3:1; touch targets ≥ 48 dp; works at 1.3× font scale without clipping; never colour alone (icons + labels with status colours).

Deliver: the token tables (both themes), the type scale, spacing/radius/elevation, every component with its states, and the motion spec — one consistent, beautiful system page.
