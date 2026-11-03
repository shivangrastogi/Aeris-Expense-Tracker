Using the **AERIS design system already created in this project** (Graphite dark + Porcelain light, steel-blue accent, Plus Jakarta Sans, rising-line-and-dot motif, no neon, no emoji), design these screens on a Pixel 8 frame (412 × 915 dp), in **both Dark and Light**, as a clickable prototype. Bottom navigation: floating pill with Home · Activity · [+] · Insights · Me.

Sample data (India, ₹): user Shivang; salary ₹85,000 credited on the 1st; this month spent ₹38,517 of a ₹60,000 budget; 13 days left; accounts HDFC ••4521 "HDFC salary" (balance ₹85,610.82) and SBI ••8208; card HDFC Credit ••1234 with ₹12,345 due on 5 Nov; rent ₹12,000 split with Rahul and Amit (Rahul paid back, Amit owes ₹4,000); recent: Swiggy ₹486, Uber ₹1,200, Zomato ₹544, Ola ₹203, Myntra ₹2,199, BigBasket ₹1,140.

## 1. Home (the flagship screen — make it beautiful)
Top to bottom, scrollable, large-title header collapsing on scroll:
- Header: avatar initial "SR", "Good evening" + "Shivang"; three round icon buttons with labels on long-press: notifications (with dot), hide amounts (eye), Ask Aeris (sparkle).
- **Hero card** (the one place the hero gradient appears, softly): overline "SPENT · THIS MONTH" + range pill "This month ▾"; the amount ₹38,517 in Display-amount; a budget progress bar shaped like the logo's rising line ending in a dot; "₹21.5K left of ₹60K" and "₹1.7K/day · 13 days"; a small trend chip "12% less than last month" (green, trending-down icon).
- **Finish setting up** card (only for new users; show a second Home variant with it): "2 of 5" + progress; rows with ticks for done items: Read bank SMS, Catch UPI app payments, Add monthly income, Set a monthly budget, Turn on reminders; "Hide" action.
- **Balances** card: "Balances · from bank SMS"; rows: HDFC salary ••4521 ₹85,610.82 "as of today, 11:59 AM"; SBI ••8208 ₹12,345.67; card row "HDFC card ••1234 · ₹12,345 due 5 Nov · min ₹620" (amber); "Owed to you ₹4,000 · from Amit" row.
- **Where it went**: three category rings (Rent ₹4K, Groceries ₹5.1K, Food ₹4.9K of ₹9K budget), "See all".
- **Momentum**: Saved 55% (₹46.5K kept) · Streak 6 days · Goal 45% "Goa trip" with a thin bar; one line "At ₹42.8K/month you'll have ₹8.1L by Dec 2027 →".
- **Needs attention** slot: one alert card at a time (e.g. "Shopping is ₹698 over budget" with "See budget").
- **Recent**: 5 transaction rows grouped under "Today" / "Yesterday" with day totals; "See all".
- Empty/new-user variant: hero shows ₹0 with "Set a monthly budget to see what's safe to spend", Momentum shows "—" "No spends yet", and a "Log your first expense" card.

## 2. Quick-add radial menu
Tap and hold "+": the screen dims, six round actions fan out on an arc above the button with labels: Voice, Quick, Scan, Spent, Received, Lent. The "+" rotates to "×". Plain surface discs with a coloured icon (no glow).

## 3. Add transaction (full form)
Segmented "Expense | Income" at top with close (×) and mic. Big centred amount field "₹ 0" with calculator keys (+ − × ÷). Recent merchant chips ("Swiggy · ₹486"). Merchant field with live suggestions. Category chips row (horizontally scrollable, "More" opens a grid sheet). When: chips Today / Yesterday / Pick date + time chip. Account dropdown (optional). Note. Toggles row: Scan receipt, Repeats monthly, Split with friends, Lent or borrowed. Sticky bottom primary "Save expense". Show a filled-in state and a validation error state.

## 4. Quick add
A compact sheet: amount keypad first, then three most-likely categories as big buttons, merchant optional, "Save". Built for 3-second entry.

## 5. Voice add
Full-screen: a calm waveform (thin rising-line style, not neon) responding to voice, live transcript "Paid 450 for groceries at BigBasket", parsed preview card below (₹450 · Groceries · BigBasket · Today) with "Save" and "Edit". Language chip "English / हिन्दी".

## 6. Scan (screenshot / receipt)
Camera/gallery picker → result: the image thumbnail on top, extracted fields (amount, payee, date, UPI ref) as editable rows with confidence ticks, "Save transaction".

## 7. Import bank statement
Step 1 pick file (PDF / CSV / Excel, password field for protected PDFs); Step 2 preview table of parsed rows with duplicates greyed ("Already in AERIS"), category column editable, totals; Step 3 "Import 42 transactions" with progress.

## 8. Review imports (swipe deck)
Header "Review imports · 2 pending". A large card: amount −₹486, merchant "Swiggy" (editable), the original SMS in a small quote block, "Add as" category chips (selected Food), source line "From HDFC SMS · 2:08 PM". Actions: "Ignore" (outline) and "Add as Food" (primary); hint "Swipe right to add, left to ignore". Stack of the next card peeking behind. Empty state "All caught up" with a tick.

## 9. Notification centre
Title + "Mark all read"; filter chips All · Unread · Money · Bills · People; cards with icon tile, title, body, action link and unread dot: "2 transactions to review", "HDFC card bill due in 2 days — ₹12,345", "Low balance on SBI ••8208 — ₹850", "₹4,000 owed to you — Amit", "Shopping budget exceeded". Empty state.
