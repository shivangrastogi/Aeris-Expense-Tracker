# AERIS Expense — Mobile Companion

> Android-first personal-finance app that **auto-reads your bank/UPI SMS**,
> stores transactions in **Firebase**, renders **7 chart types** via
> `fl_chart`, and surfaces **on-device statistical predictions +
> recommendations** so you stop manually entering anything.

Built with **Flutter 3.19+ / Dart 3.3+**. Companion to the AERIS desktop
assistant.

---

## ✨ What it does

| Feature | Where |
|---|---|
| Email/password + phone-OTP auth | `lib/services/auth_service.dart` |
| Profile create + edit (display name, phone, income) | `screens/profile/` |
| **Auto-import bank SMS** (SBI, HDFC, ICICI, AXIS, Kotak, IDFC, IndusInd, Yes, PNB, BOB, Paytm, PhonePe, GPay, Cred, Slice, Niyo) | `services/sms_parser.dart` + `sms_service.dart` |
| **Dedupes** so the same alert isn't double-imported | Firestore `processed_sms/` ledger |
| Per-transaction merchant + category auto-classification | `models/category.dart` (200+ keywords across 13 categories) |
| Manual review screen — confirm/edit anything auto-imported before it finalises | `screens/sms_inbox/sms_review_screen.dart` |
| 7-chart analytics tab (pie, bar, dual-line trend, income-vs-expense, top merchants, cumulative, radar) | `screens/analytics/analytics_screen.dart` |
| Per-category monthly **budgets** with burn-rate visual + pace alerts | `screens/budgets/` |
| **AI insights tab** — month-end forecast, per-category EMA forecast, anomaly z-score detection, recurring-payment detection, recommendation engine | `services/prediction_service.dart`, `services/recommendation_service.dart` |
| Settings — request/revoke SMS permission, backfill 90-day history | `screens/profile/settings_screen.dart` |

## 🧠 How the AI works (no ML black box)

On-device, dependency-free, pure-function — fast even on a low-end phone:

| Technique | What it powers |
|---|---|
| Burn-rate × history blend | "Estimated June spend" hero card |
| **Exponential moving average** per category | Next-month per-category forecast |
| **Z-score** within category | "Unusually large food spend" anomalies |
| **Day-of-month clustering** | "Netflix charges you on the 5th every month" recurring detection |
| Pace × budget cap | "On track to exceed groceries budget by 18%" warnings |
| Savings-rate × income | "Saving rate below 10% — set a budget" recommendation |

Everything is in `lib/services/prediction_service.dart` and
`lib/services/recommendation_service.dart` — see the docstrings, they
explain the rationale.

## 📁 Layout

```
mobile/aeris_expense/
├── pubspec.yaml
├── README.md                          ← you are here
├── android/
│   └── app/
│       ├── build.gradle.kts
│       └── src/main/
│           ├── AndroidManifest.xml    ← SMS + Firebase permissions
│           └── kotlin/com/aeris/expense/MainActivity.kt
├── lib/
│   ├── main.dart, app.dart
│   ├── core/                          theme, routes
│   ├── models/                        Transaction, Budget, Category, UserProfile, Insight
│   ├── services/                      auth, firestore, sms, parser, prediction, recommendation
│   ├── providers/                     Riverpod state — auth, txns, budgets, analytics, insights
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── auth/                      login, signup, OTP
│   │   ├── home/                      dashboard + bottom-nav shell
│   │   ├── transactions/              list, add, detail
│   │   ├── analytics/                 7 charts
│   │   ├── budgets/                   list, edit
│   │   ├── insights/                  AI cards
│   │   ├── profile/                   profile, edit, settings
│   │   └── sms_inbox/                 review pending imports
│   ├── widgets/                       reusable tiles, chart card, stat card
│   └── utils/                         formatters
└── test/                              parser + prediction tests
```

## 🚀 Setup

### 1. Flutter

Install Flutter ≥3.19 from <https://docs.flutter.dev/get-started/install>.

```powershell
cd mobile\aeris_expense
flutter pub get
```

### 2. Firebase project

1. Create a Firebase project at <https://console.firebase.google.com>.
2. Enable **Authentication → Email/Password** (and optionally Phone).
3. Enable **Cloud Firestore** in production mode (rules below).
4. Add an Android app inside the project with package name
   `com.aeris.expense` and download `google-services.json`.
5. Drop `google-services.json` into `android/app/`.
6. Install the FlutterFire CLI and run inside the project root:
   ```powershell
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   This writes `lib/firebase_options.dart`. Then change `main.dart` to use
   `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.

#### Firestore security rules (paste into the Rules tab)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
      match /{coll}/{docId} {
        allow read, write: if request.auth != null && request.auth.uid == uid;
      }
    }
  }
}
```

### 3. Run on a real device

The Android emulator can't receive SMS, so plug in a real phone and:

```powershell
flutter devices                      # confirm your phone is listed
flutter run -d <device-id>
```

First launch will prompt for:
- Sign in / sign up
- "Allow AERIS to access SMS?" — **grant it.** This is the magic ingredient.
- Optionally "Allow notifications" for budget alerts.

The app will then backfill the last 30 days of bank SMS into transactions
and listen for new alerts in real time.

### 4. Build a release APK

```powershell
flutter build apk --release --target-platform android-arm64
```

The APK lands in `build/app/outputs/flutter-apk/app-release.apk`.
Side-load it onto your phone or upload to the Play Console.

> ⚠️ Play Store policy: apps requesting `READ_SMS` go through extra review.
> You'll need a privacy policy URL and a use-case justification. For
> personal use / side-loading, you're fine.

## 🧪 Tests

```powershell
flutter test
```

There are two real test files:

- `test/sms_parser_test.dart` — fixtures for HDFC / SBI / ICICI / Paytm
  debits, salary credits, and OTP/promotional rejections.
- `test/prediction_service_test.dart` — burn-rate forecast, anomaly
  detection, recurring detection, EMA forecast.

## 🛣 Roadmap (parts I intentionally left for later)

- **Real TFLite model** for category classification — current keyword map
  is ~85% accurate; a small distilled BERT would push it past 95%.
- **PDF statement import** — many users want bulk-import from a PDF
  e-statement. `pdfx` + a layout-aware parser would handle this.
- **Web dashboard** — Firebase + Flutter Web means the same Firestore
  data can render a richer desktop view.
- **Multi-account aware budgets** — currently global; per-account caps
  would help users who route categories through specific cards.
- **Encrypted local cache** — Firestore offline persistence already
  caches, but SQLCipher would make on-device data encrypted at rest.

## ❓ Why Android-only?

iOS **forbids third-party apps from reading SMS** — Apple gives that
privilege to first-party Messages + Mail + Wallet only. There is no
workaround. If you want iOS, the architecture changes: you must either
have the user forward bank emails to a parser endpoint, or use Account
Aggregator / Plaid-style consented bank-account APIs. Both are out of
scope here.

---

*Companion app to the AERIS desktop assistant — same project root,
`../core/phone_bridge.py` can also receive transaction events from this
app if you want desktop notifications.*
