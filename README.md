# Fair Split 🧾

A premium, modern cross-platform mobile application designed for splitting **Ethiopian ERCA standard receipts** proportionally. Built with **Flutter & Dart**, powered by **Google's Gemini 2.5 Flash** multimodal intelligence.

---

## 🌟 Key Features

* **Live In-App Camera scan**: Focus, align, and photograph ERCA standard fiscal receipts directly inside the app viewfinder frame (no third-party camera apps redirection).
* **AI Receipt parsing**: Powered directly from your phone by Gemini 2.5 Flash, extracting restaurant names, subtotal, service charges, VAT rates, and line items automatically.
* **Proportional Splitting Math**: Allocates service charges and taxes proportionally based on each person's exact items subtotal.
* **Largest-Remainder Rounding**: Reconciles fractional decimals down to the cent, ensuring the sum of all parts matches the receipt target total exactly (no rounding leaks!).
* **State Persistence**: Zentralized Zustand-like state architecture persisted on-device via `shared_preferences` (recents list, history log).
* **Copy & Share Breakdown**: Custom text templates pre-formatted to copy and share directly to telegram, WhatsApp, etc.

---

## 🚀 Getting Started

### Prerequisites
* Flutter SDK (v3.18.0+ or compatible)
* Android SDK (API Level 21+) / Xcode for iOS
* A physical Android or iOS device connected via USB Debugging.

### Configuration
1. Obtain a free Gemini API key from [Google AI Studio](https://aistudio.google.com/).
2. Create a file named `assets/env.json` at the root of the project (this file is excluded from Git to prevent secret leakage):
   ```json
   {
     "GEMINI_API_KEY": "YOUR_GEMINI_API_KEY"
   }
   ```

### Installation
1. Install project dependencies:
   ```bash
   flutter pub get
   ```
2. Run unit tests to verify the splitting math core:
   ```bash
   flutter test
   ```
3. Deploy and run on your physical phone:
   ```bash
   flutter run
   ```

---

## 🧪 Technical Structure

* `lib/splitting_algorithm.dart`: Core TypeScript-migrated mathematical rounding algorithm.
* `lib/main.dart`: Complete app state manager, camera controller, Gemini proxy client, and the 6 UI layouts.
* `test/splitting_algorithm_test.dart`: Vitest-equivalent assertions ensuring perfect proportional allocations.
* `assets/env.json`: Private runtime configurations (ignored by `.gitignore`).
* `assets/icon.png`: Brand asset image used for native launcher packaging.
