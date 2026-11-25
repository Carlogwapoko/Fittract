# FitTrack / Fittract

## Dokumentasyon para sa Presentation

### 1. Pamagat sa System

**FitTrack: A Personal Fitness and Health Tracking System**

Ang FitTrack usa ka cross-platform application nga gitukod gamit ang Flutter. Nakatabang kini sa mga tiggamit sa pagmonitor sa ilang adlaw-adlaw nga exercise, food intake, tubig, timbang, lakang, workout routine, ug overall fitness progress.

**Slug sa project:** `fittract`

### 2. Klase sa System

Ang FitTrack usa ka:

- **Personal health and fitness tracking system**
- **Mobile and cross-platform application**
- **User-based system** nga adunay Firebase Authentication
- **Cloud-connected application** nga adunay local data storage
- **AI-assisted meal logging system** nga makascan ug makarecognize sa food information

Ang sistema makatabang sa pag-organisar sa fitness data sa usa ka lugar. Makalog in ang mga tiggamit gamit ang email/password o Google account, ug ma-sync ang ilang information ngadto sa account kung adunay internet.

### 3. Suliran nga Gusto Sulbaron

Daghang tawo ang lisod magpadayon sa ilang fitness activities tungod kay:

- Gikapoy sila sa pagmano-mano ug pagorganisar sa workout activities.
- Lisod nila ma-monitor ang ilang adlaw-adlaw nga pag-inom sa tubig, lakang, meals, ug weight.
- Kulang sila sa nasentro nga app nga nagpakita sa tanan nga fitness progress.
- Ang manual nga pagsaysay sa calorie ug macronutrient content sa pagkaon mahimong dugay ug lisod.
- Dili tanan nga app nagsuporta sa offline access ug synchronized data taliwala sa devices.
- Ang mga routine ug schedule lisod usab na sabton kung walay klaro nga workout plan.

Ang FitTrack gitukod aron masayon, mas organisado, ug mas epektibo ang pag-monitor sa physical health ug fitness sa matag adlaw.

### 4. Target Users

#### Pangunang Target Users

- Mga estudyante nga gustong mag-healthy ug aktibo
- Mga working individuals nga gusto magtrack sa ilang exercise ug nutrition
- Mga beginner sa fitness
- Mga tawo nga nagbansay para sa weight management
- Mga atleta o active individuals nga gusto mag-monitor sa workouts ug progress

#### Secondary Users

- Mga health-conscious individuals
- Mga coaches o gym users nga naggamit ug personalized routines
- Mga tiggamit nga gusto ma-organisar ang iyang food and hydration goals
- Mga users nga gustong makakita sa ilang long-term fitness progress

### 5. Pangunang Layunin sa System

1. Makatabang sa users sa pag-set ug pag-monitor sa daily fitness goals.
2. Maghatag ug structured workout routines ug exercise schedule.
3. Mag-record sa meals, calories, protein, carbohydrates, ug fat.
4. Ma-monitor ang weight, steps, distance, active calories, ug water intake.
5. Magamit ang food scanning ug AI-assisted nutrition information.
6. Makita sa Progress tab ang improvement sa trabaho ug fitness.
7. I-secure ang account data gamit ang Firebase Authentication.
8. Magsuporta sa cloud sync ug on-device storage bisan walay internet.

### 6. Pangunang Features

#### Today / Dashboard
- Gipakita ang greeting ug current daily status
- Nagpakita sa calories, tubig, lakang, ug workout progress
- Makatabang sa pag-open sa reminders, activities, food, water, ug weight tools

#### Routines
- Makahimo ug custom workout routines
- Makasunod sa built-in exercise library
- Makagamit sa Strength, Cardio, ug Mobility routines
- Makadugang ug remove exercises sa routine

#### Schedule
- Makaplano sa workout para sa piho nga petsa ug oras
- Makakita sa scheduled activities ug daily workout plan

#### Workout Tracking
- Makastart, pause, resume, ug complete ug workout
- Makarecord sa sets, reps, weight, rest time, ug duration
- Magtala sa workout history

#### Food and Meal Tracking
- Makalog sa mga meal ug ingredients
- Makatrack sa calories ug macronutrients
- Makascan sa food photo
- Makae-edit sa detected ingredients ug quantity
- Makagamit sa manual meal entry

#### Activity and Movement Tracking
- Makatrack sa steps ug walking distance
- Makatala sa logged activities
- Makuha ang automatic activity tracking gamit ang device motion sensor ug GPS

#### Weight and Progress
- Makarecord sa weight history
- Nagpakita sa weight chart ug projected weight plan
- Makakita sa workout, step, activity, calorie, ug water progress

#### Profile and Account
- Makadugang ug personal details ug profile photo
- Makailis sa theme color ug units
- Makagamit sa email/password o Google sign-in
- Makaconnect sa cloud sync
- Makaconnect sa local account ngadto sa cloud account

### 7. Benefits sa Users

- **Mas organisado:** Naa sa usa ka application ang workout, meal, water, weight, ug progress.
- **Mas sayon:** Makagamit sa manual entry ug AI-assisted food scanning.
- **Mas accountable:** Makita sa daily progress ang users.
- **Mas accessible:** Maduol sa tiggamit ang health and fitness goals bisan sa phone, tablet, o computer.
- **Mas reliable:** Ang fitness records ma-save sa device ug ma-sync sa cloud.
- **Mas private:** Ang user data gi-isolate ug giangkon sa signed-in account.

### 8. Scope sa Project

#### Included in the System

- Authentication
- User profile
- Daily goals
- Exercise routines
- Workout schedule
- Food and calorie tracking
- Water tracking
- Weight tracking
- Step and activity tracking
- Progress monitoring
- Local data storage
- Cloud synchronization
- AI-assisted food recognition

#### Not the Main Purpose

- Walay medical diagnosis
- Walay replacement sa advice sa doctor o licensed nutritionist
- Walay real-time gym equipment integration
- Walay fully implemented system notifications; anaa karon ang in-app reminders

### 9. Technology Used

- **Frontend:** Flutter ug Dart
- **Authentication:** Firebase Authentication
- **Database:** SQLite para sa local/native storage
- **Cloud Database:** Cloud Firestore
- **AI and Food API:** Cloudflare Worker, Google Gemini, ug USDA FoodData Central
- **Other Services:** Google Sign-In, geolocation, pedometer, image picker

### 10. Presentation Summary

**FitTrack** usa ka cross-platform personal fitness tracking system nga naghiusa sa workouts, routines, schedules, water, nutrition, weight, steps, ug fitness progress. Gitukod kini aron masulbad ang problema sa manual ug fragmented nga pag-monitor sa health activities. Ginamit kini sa estudyante, professionals, beginners, athletes, ug bisan kinsa nga gustong mahimong mas organised ug consistent sa ilang fitness journey.
