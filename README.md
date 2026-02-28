# NutriBuddy 🥗

An AI-powered nutrition tracking Flutter app built for the AMD Challenge. NutriBuddy uses Google Gemini AI to analyze food from photos or text, provide personalized dietary advice, and help users stay on track with their health goals.

---

## Features

### AI-Powered Food Analysis

- **Camera / Gallery scan** — take or upload a photo of any food item to get instant nutritional breakdown (calories, protein, carbs, fats, etc.)
- **Text analysis** — type a food name or paste a full recipe to get nutrition info
- **Recipe Healthify** — paste a recipe and get a healthier version with substitutions

### Personalized Health Coaching

- **AI chat assistant** — conversational nutrition coach with persistent context (last 5 exchanges)
- **Goal-aware recommendations** — advice is tailored to your active health challenges
- **Health profile** — enter age, gender, height, and weight; the app calculates your BMI and personalizes daily targets accordingly

### Health Challenges

Choose one or more challenges to focus your nutrition goals:
| Challenge | Description |
|---|---|
| ⚖️ Weight Loss | Reduce calorie intake and maintain healthy weight |
| 💪 Muscle Gain | Increase protein intake for muscle building |
| 🥗 Balanced Diet | Maintain balanced macronutrient ratios |
| 🍬 Low Sugar | Reduce sugar consumption |
| ❤️ Heart Health | Focus on low sodium and healthy fats |

### Daily Nutrition Tracking

- Tracks calories, protein, carbs, and fats against personalized daily goals
- Logs confirmed meals and updates running totals in real time
- Nutrition history stored in the cloud and viewable per day

### Authentication & Cloud Sync

- **Google Sign-In** — full account with cross-device sync
- **Guest / Anonymous** — try the app with no account; upgrade later without losing data
- **Cloud Firestore** — challenges, health profile, daily totals, and food history all synced automatically

---

## Tech Stack

| Layer          | Technology                         |
| -------------- | ---------------------------------- |
| Framework      | Flutter (Dart)                     |
| AI / Vision    | Google Gemini (`gemini-1.5-flash`) |
| Authentication | Firebase Auth (Google + Anonymous) |
| Database       | Cloud Firestore                    |
| Local storage  | `shared_preferences`               |
| Image picking  | `image_picker`                     |

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.10
- A [Firebase project](https://console.firebase.google.com/) with **Authentication** (Google + Anonymous) and **Firestore** enabled
- A [Google Gemini API key](https://aistudio.google.com/app/apikey) (free tier available)

### 1. Clone the repository

```bash
git clone https://github.com/Harshcoder9/AMD-Challenge.git
cd "AMD-Challenge"
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Set your Gemini API key

Open [lib/main.dart](lib/main.dart) and replace the placeholder on line 21:

```dart
const _kGeminiApiKey = 'YOUR_GEMINI_API_KEY_HERE';
```

> Leave it as `'YOUR_GEMINI_API_KEY_HERE'` to run in **demo mode** (simulated AI responses, no key required).

### 4. Configure Firebase

Follow the steps in [FIREBASE_SETUP.md](FIREBASE_SETUP.md) to:

1. Create a Firebase project
2. Enable Google Sign-In and Anonymous auth
3. Create a Firestore database
4. Replace `lib/firebase_options.dart` with your project's generated options

### 5. Run the app

```bash
# Android
flutter run -d android

# iOS
flutter run -d ios

# Windows desktop
flutter run -d windows

# Web
flutter run -d chrome
```

---

## Project Structure

```
lib/
├── main.dart                   # App entry point, AI logic, home screen
├── firebase_options.dart        # Firebase project configuration
├── challenges_screen.dart       # Health challenge selection UI
├── screens/
│   ├── sign_in_screen.dart      # Google / Guest sign-in screen
│   ├── health_profile_screen.dart  # User profile setup
│   └── settings_screen.dart     # Account management & preferences
└── services/
    ├── auth_service.dart        # Firebase Auth wrapper
    ├── firestore_service.dart   # Firestore CRUD & data models
    └── nutrition_calculator.dart # BMI & daily goal calculations
```

---

## Firebase Security Rules (Production)

Before deploying to production, update your Firestore rules to:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      match /{document=**} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
  }
}
```

---

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

---

## License

This project was created for the AMD Challenge. All rights reserved.
