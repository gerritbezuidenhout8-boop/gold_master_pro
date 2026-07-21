# Connecting Firebase (optional, still $0)

The app is fully usable without Firebase — the journal is local-first.
Connect Firebase when you want **sign-in** and **cross-device journal
sync**. Everything below fits inside the free **Spark** plan (Auth up to
50k monthly users, Firestore free quota, no credit card). Do **not**
enable Cloud Functions — that requires the Blaze plan; our alerts design
uses Cloudflare Workers instead (build-order step 6).

These steps need YOUR Google account, so they can't be automated.

## 1. Create the project

```sh
npm install -g firebase-tools
firebase login                       # opens the browser, sign in with Google
dart pub global activate flutterfire_cli
cd C:\dev\gold_master_pro
flutterfire configure --platforms=android,web
```

Pick "create a new project" (e.g. `gold-master-pro`). This writes
`lib/firebase_options.dart` and the Android config. Windows desktop is
not supported by most Firebase plugins — leave it local-mode.

## 2. Add the packages

```sh
flutter pub add firebase_core firebase_auth cloud_firestore
```

In `lib/main.dart`, before `runApp`:

```dart
WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

## 3. Enable sign-in

Firebase console → Authentication → Sign-in method → enable
**Email/Password** and (optionally) **Google**.

## 4. Journal sync

Implement the existing interface (see `lib/services/journal_store.dart`)
and swap it in after sign-in — nothing else in the app changes:

```dart
class FirestoreJournalStore implements JournalStore {
  FirestoreJournalStore(this.uid);
  final String uid;
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('users/$uid/journal');

  @override
  Future<List<JournalEntry>> load() async {
    final snap = await _col.get();
    return [for (final d in snap.docs) JournalEntry.fromMap(d.data())];
  }

  @override
  Future<void> save(List<JournalEntry> entries) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final e in entries) {
      batch.set(_col.doc(e.id), e.toMap());
    }
    await batch.commit();
  }
}

// after sign-in:
JournalStore.instance = FirestoreJournalStore(user.uid);
```

(Deletions need a tombstone or doc-diff pass — refine when implementing.)

## 5. Security rules (Firestore → Rules)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

## Cost guard

Spark has no card on file, so overruns are impossible — Firebase just
throttles. Keep candles OUT of Firestore (market data stays in the app /
Binance); Firestore is for user data only.
