Using the **AERIS design system already created in this project** (Graphite dark + Porcelain light, steel-blue accent, Plus Jakarta Sans, rising-line-and-dot motif, no neon, no mascots, no emoji), design these screens on a Pixel 8 frame (412 × 915 dp), in **both Dark and Light**, linked as a clickable flow.

Sample user: Shivang Rastogi, shivang@example.com, India (₹).

## Screens

1. **Splash** — graphite background, the "A" logo centred (112 dp, rounded square), the wordmark "AERIS" typing in beneath, a thin rising-line loader. Under 1 second; feels instant.

2. **Welcome / sign-in hub** — top: logo + "AERIS". Headline "Money that tracks itself." Sub-line "Private. Automatic. Encrypted on your phone." A tasteful abstract hero: three stacked translucent cards (a transaction row, a budget ring, a balance) drifting slightly, in muted steel tones. Primary button "Create account", secondary "I already have an account". Footer: lock icon + "End-to-end encrypted · your data stays yours".

3. **Log in** — email field, password field with show/hide eye, "Forgot password?" text button, primary "Log in" (loading state), error state ("That password isn't right"). Note under the title: "Your password also unlocks your encrypted data."

4. **Create account** — full name, email, password with live rules checklist (8+ characters, a letter, a number — each ticks green as met), show/hide eye, primary "Create account". Info card: key icon + "Next you'll get a Recovery Key — the only way back in if you forget your password."

5. **Save your recovery key** (full screen, cannot be skipped) — explanation, the key shown as 6 monospace blocks (e.g. K7QX-29MD-…) in a sunken panel, "Copy" and "Save as image" buttons, checkbox "I've saved my recovery key", primary "Continue" enabled only when ticked.

6. **Unlock your data** (new phone / after reinstall) — "Welcome back, Shivang", password field, "Unlock", link "Forgot password? Use recovery key" → **Recovery** screen: recovery key input (auto-formats blocks), new password, "Restore access".

7. **App lock** — biometric prompt over a blurred app preview: logo, "AERIS is locked", fingerprint icon button "Unlock", "Use PIN" text button.

8. **Onboarding — 5 steps** (one per screen, progress = 5 small rising segments at top, "Skip for now" top-right, primary "Continue" bottom). Each step: a 64 dp icon tile, headline, short body, and an action that does its job right there, then shows the real result (green tick line, or an amber line if denied).
   - Step 1 "Private by design" — lock icon; explains on-device reading + encryption.
   - Step 2 "Read bank SMS" — SMS icon; button "Allow SMS access"; success "SMS reading is on"; denied "Not allowed — you can turn it on later in Settings". Show a tiny example: a bank SMS bubble turning into a transaction row.
   - Step 3 "Catch UPI app payments" — bell icon; "Google Pay, PhonePe and Paytm often send no bank SMS"; button "Open notification access"; small row of monochrome app glyphs.
   - Step 4 "Your monthly income" — big amount input "₹ 85,000", helper "Used for your savings rate. Optional."
   - Step 5 "Stay on top" — alarm icon; three example reminder chips ("Rent due tomorrow", "HDFC card ₹12,345 due in 2 days", "Amit owes you ₹4,000"); button "Turn on reminders".
   - Final: primary "Get started".

9. **Permission explainer sheets** (bottom sheets shown before the Android system dialog): SMS (what is read / what is never read, "Only transaction messages are kept"), Notification access (which apps only), Notifications (what you'll get). Each with "Continue" and "Not now".

Design the transitions: splash → welcome fades; onboarding steps slide horizontally; the recovery key screen enters from the bottom like a sheet.
