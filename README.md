# FitTrack

## Data storage and services

FitTrack keeps an on-device copy of profiles, goals, preferences, routines,
schedules, meals, water, activity, steps, weights, workout history, and meal
photos, and synchronizes account data to that user's `users/{uid}` Firestore
document. On Android and other native targets, account fields and fitness
records are stored in a local SQLite database. Existing account snapshots in
SharedPreferences are migrated to SQLite on startup; session, sync-status, and
device-preference metadata remain in SharedPreferences. Meal photos are stored
in that user's `foodImages` subcollection,
separately from the account snapshot. Sync is user-scoped, conflict-checked,
and real-time while signed in. If the network is unavailable, changes remain
on the device and the Profile screen reports sync status; logging out attempts
a final sync and warns if it cannot complete.

Email/password verifiers remain salted PBKDF2-HMAC-SHA256 hashes on-device and
are never uploaded. Email/password and Google identities use Firebase
Authentication. Existing local email accounts can be linked from Profile after
the user verifies their password and confirms the upload. The app's Firebase
project configuration targets `fittrack-mydatabase`; Firebase Hosting continues
to serve the public terms and privacy pages.

Deploy the user-isolated Firestore rules with:

```powershell
firebase deploy --only firestore:rules --project fittrack-mydatabase
```

In Firebase Authentication, enable the Email/Password and Google providers.
The same Firebase project must have its default Firestore database enabled.

## Configure Google sign-in (Android)

FitTrack uses Firebase Authentication with Google as its sign-in provider.
Android uses the native Google account picker and exchanges its ID token with
Firebase Authentication, avoiding the browser redirect flow that can fail in
Android APKs with a missing OAuth state. iOS uses Firebase's native provider
flow, web uses Firebase's Google popup, and other supported native targets use
`google_sign_in` with Firebase Authentication.

Before signing in with Google:

1. In the Firebase Console, create or select your Firebase project and add an
   Android app with the package name `com.example.fittract`.
2. Download that app's `google-services.json` and place it at
   `android/app/google-services.json`.
3. In **Authentication → Sign-in method**, enable the **Google** provider.
4. Confirm the Google provider setup is complete in Firebase Authentication,
   including the project's support email and OAuth configuration.
5. Register the SHA-1 certificate for each signing key used to build the APK.
   You can find the local debug certificate with `cd android` followed by
   `.\gradlew signingReport`.
6. Download `google-services.json` again after enabling Google sign-in. It
   must include the web OAuth client used to request the Firebase ID token.
7. Rebuild the Android app after changing its Firebase configuration.

The Google Services Gradle plugin (`android/app/build.gradle.kts`) applies
only when `google-services.json` exists. If sign-in configuration is
missing or incomplete, the rest of the app remains usable and the Google
sign-in button displays a setup message (`googleAuthErrorMessage` maps
configuration error codes to setup hints).

iOS additionally requires:

- `ios/Runner/GoogleService-Info.plist` added to the Xcode project, and
- a `CFBundleURLTypes` entry with the Google reversed client ID.

Google accounts authenticate through Firebase and automatically sync their
fitness records to their private Firestore document.

The login and registration screens follow the device color scheme by default;
the existing in-app dark-mode setting can still force dark mode. The public
policy pages are hosted on Firebase Hosting:

- Terms of Service: https://fittrack-mydatabase.web.app/terms
- Privacy Policy: https://fittrack-mydatabase.web.app/privacy

The policy pages still contain the requested placeholders for FitTrack's legal
operator name, privacy contact email, and governing jurisdiction. Replace
those placeholders and review the policies for legal accuracy before treating
them as final.

Manual meal entry uses the authenticated Cloudflare Worker in `worker/`.
Firebase Authentication ID tokens are verified against Google's Firebase
Secure Token signing keys. The Worker sends food photos to Google Gemini for
food/ingredient recognition and for comparing edited ingredients with the
photo. For nutrition it searches the USDA FoodData Central Foundation and SR
Legacy datasets (five results), selects the closest generic/raw-or-cooked food,
then fetches that food's detail record for per-100 g calories, protein,
carbohydrates, and fat. Those values are scaled by each ingredient's weight;
repeated USDA lookups are cached briefly in the Worker. Gemini estimates are
clearly identified when USDA has no matching data.
Detected ingredients and quantities remain editable before saving. Meal
records, meal photos, and photo-validation results are kept on-device and
synchronized to the user's Firestore data. The Worker does not write or retain
meal records or photos.
The app shows a one-time privacy notice before the first scan. Quantities in
millilitres are treated as approximately 1 ml = 1 g; countable items use
estimated piece weights.

### Deploy the food API

Install Node.js 20+ and the Wrangler CLI through the Worker package. From
PowerShell:

```powershell
cd .\worker
npm install
npx wrangler login
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put USDA_API_KEY
npx wrangler deploy
```

Enter each key only at Wrangler's secure prompt. The Firebase project ID is a
non-secret Worker variable in `worker/wrangler.toml`. Do not put provider keys
in Flutter, `.dart` files, source control, or build arguments. `wrangler deploy`
prints the Worker URL; enable the account's `workers.dev` subdomain if needed.
Verify the public health endpoint, replacing the host with the URL printed by
Wrangler:

```powershell
Invoke-RestMethod https://fittrack-food-api.<your-account>.workers.dev/health
```

The expected response is `{"status":"ok"}`. From the `worker/` directory, run
the Worker endpoint and Firebase-token verification tests with:

```powershell
npm test
```

The app defaults to the deployed public endpoint
`https://fittrack-food-api.carloplaza2023.workers.dev/api/food`. For another
Worker environment, override it at build/run time:

```powershell
cd ..
flutter run --dart-define="FOOD_API_URL=https://fittrack-food-api.<your-account>.workers.dev/api/food"
```

Use the same override when producing a release build for another environment.
For example:

```powershell
flutter build appbundle --dart-define="FOOD_API_URL=https://fittrack-food-api.<your-account>.workers.dev/api/food"
```

Then sign in to FitTrack, open **Food & meals → Log food → Add food manually**,
scan a food photo, review/edit the detected ingredient names and quantities,
and verify nutrition recalculates after edits. Also add an ingredient
manually, confirm USDA nutrition appears, and save the meal; confirm it appears
in meal history and remains after restarting the app on the same device. To
verify the API's authenticated behavior independently, invoke
`POST /api/food` with a current Firebase ID token in the `Authorization:
Bearer <token>` header and an `action` of `scan`, `nutrition`, or `match`.
Unauthenticated requests should return HTTP 401. Never paste or log a real ID
token in a terminal transcript, issue, or repository.

The Worker accepts `POST /api/food` with `action` `scan` (`imageBase64` and
`mimeType`), `nutrition` (`ingredients`), or `match` (photo fields and the
user-edited `ingredients` list).

If scanning or nutrition calculation is unavailable, users can still enter
ingredients and nutrition manually and retry. Provider quotas and pricing are
subject to Google's, USDA's, and Cloudflare's current service terms.

## Production release blockers

`android/app/build.gradle.kts` still signs release builds with the debug
key and carries the upstream TODO to add a real signing config. Before a
production release, a real keystore must be created and configured — do not
commit keystore passwords or use fabricated credentials. The application ID
is intentionally left as `com.example.fittract` for now.

## Notification status: not implemented

There is no notification plugin dependency in `pubspec.yaml` or
`pubspec.lock` (no `flutter_local_notifications` or equivalent), and no
scheduling code, so **system notifications and recurring notification
schedules are not available**.

What exists instead is honest in-app reminder UI:

- The `wr`/`wtr`/`mr` toggles in Profile control reminder *cards* rendered
  on the Today screen (`store.notes()`), labeled "(in-app)".
- The Schedule tab shows an in-app reminder toggle with copy stating that
  system notifications are not available yet.

To implement real reminders later: pick a notification plugin, add it to
`pubspec.yaml`, run `flutter pub get`, request POST_NOTIFICATIONS on
Android 13+, store a notification ID per schedule entry, and
schedule/cancel/update notifications alongside every `store.sch` mutation,
including recurrence rules and past-time handling.

## Data retention policy

`Store.applyRetention()` (in `lib/store/store.dart`) runs after every daily
rollover and is the only place that trims the unbounded collections:

- `water`: newest 90 days of dated entries (`kWaterRetentionDays`).
- `log`: newest 365 archived-day entries (`kLogRetentionDays`).
- `hist`: workouts from the last 365 days (`kHistRetentionDays`).

Entries with missing or unparseable dates are always kept; data is only
removed when it is provably older than its bound. Daily rollover itself
preserves history by archiving meals/activity/steps into `log` before the
counters reset, and never modifies `hist`.
