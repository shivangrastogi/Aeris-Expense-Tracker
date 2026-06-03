# AERIS Expense Tracking

AERIS is a dual-platform personal finance system consisting of:

- `mobile/` — Android-first Flutter expense tracker that auto-imports bank/UPI SMS and stores encrypted transaction data in Firebase.
- `website/` — React + Vite web dashboard that reads and writes the same Firebase data with end-to-end encryption in the browser.

This repository is the source for both the mobile and web companion apps.

---

## Repository structure

```
/aeris-expense-tracking-website
├── mobile/          # Flutter Android app
└── website/         # React + Vite web dashboard
```

### Subproject contents

- `mobile/`
  - `pubspec.yaml` — Flutter dependencies and project metadata
  - `lib/` — app source code
  - `android/` — Android build and permissions
  - `test/` — Flutter/Dart tests

- `website/`
  - `package.json` — web dependencies and npm scripts
  - `src/` — React app source code
  - `dist/` — built production output
  - `vite.config.js` — Vite configuration
  - `vercel.json` — Vercel deployment configuration

---

## High-level summary

### Mobile app

Built with Flutter 3.19+ and Dart 3.3+.

Key capabilities:

- Android-only SMS auto-import for bank/UPI alerts
- Firebase Authentication and Firestore storage
- Encrypted financial data model with client-side protection
- Transaction categorization and budget tracking
- Charts, insights, forecasts, and anomaly detection
- Local caching and offline-friendly sync

### Website app

A React-based dashboard built with Vite, Tailwind CSS, and Firebase.

Key capabilities:

- Shared Firebase backend with mobile app
- End-to-end encrypted browser data access
- Dashboard, charts, transactions, budgets, goals, and AI assistant
- Same account login with shared data model

---

## Mobile setup

### Prerequisites

- Flutter SDK >= 3.19
- Dart SDK compatible with Flutter
- Android device or emulator
- Firebase project with Android app configured

### Install dependencies

```bash
cd mobile/aeris_expense
flutter pub get
```

### Firebase configuration

1. Create a Firebase project at https://console.firebase.google.com.
2. Enable Authentication (Email/Password and optionally Phone).
3. Enable Cloud Firestore.
4. Add an Android app for package name `com.aeris.expense`.
5. Download `google-services.json` and place it in `mobile/aeris_expense/android/app/`.
6. Configure Firebase using FlutterFire CLI if desired:

```bash
dart pub global activate flutterfire_cli
cd mobile/aeris_expense
flutterfire configure
```

### Run locally

```bash
cd mobile/aeris_expense
flutter run
```

For a real device (recommended, because SMS import requires an actual phone):

```bash
flutter devices
flutter run -d <device-id>
```

### Build release APK

```bash
cd mobile/aeris_expense
flutter build apk --release --target-platform android-arm64
```

---

## Website setup

### Prerequisites

- Node.js and npm

### Install dependencies

```bash
cd website
npm install
```

### Run in development mode

```bash
cd website
npm run dev
```

The local site should be available at `http://localhost:5173`.

### Build for production

```bash
cd website
npm run build
```

### Preview production build

```bash
cd website
npm run preview
```

---

## Deployment notes

### Vercel

If you deploy the web app to Vercel, make sure the project is configured correctly:

- **Root Directory**: `website`
- **Build Command**: `npm run build`
- **Output Directory**: `dist`

The repository root is not itself a Node app, so Vercel must build from the `website` subfolder.

### Important

The website app depends on `package.json` and `vite` being available in `website/`. If Vercel runs at the repository root, the build will fail with `vite: command not found`.

---

## Notes on encryption and data sharing

- Mobile and web apps are designed to share the same Firebase data model.
- The web app encrypts/decrypts in the browser using client-side crypto.
- The mobile app encrypts before writing to Firestore and decrypts after reading.

---

## Useful commands

### Mobile

```bash
cd mobile/aeris_expense
flutter pub get
flutter run
flutter test
flutter build apk --release
```

### Website

```bash
cd website
npm install
npm run dev
npm run build
npm run preview
```

---

## Contribution

If you want to contribute:

1. Fork the repository.
2. Create a branch for your feature or fix.
3. Test changes in both `mobile/` and `website/` if they affect shared Firebase behavior.
4. Open a pull request describing the change.

---

## Helpful references

- Flutter docs: https://docs.flutter.dev/
- Vite docs: https://vitejs.dev/
- Firebase docs: https://firebase.google.com/docs

---

## License

Add your license information here if you want to license this repository.
