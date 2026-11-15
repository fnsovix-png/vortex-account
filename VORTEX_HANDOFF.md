# Vortex handoff

Read this whole file before doing anything. It replaces the original chat, which lived on a Shadow cloud PC whose subscription is ending.

## What Vortex is

A private music app for the owner and their family only. It should feel like Spotify but better, on Android, Windows, iPad and iPhone. It searches YouTube Music's catalog, plays audio, and has synced lyrics, accounts, friends, chat, playlists, styles and in-app updates.

Features the owner asked for, which must keep working: all songs and artists; artist pages with songs ranked from the top, plus albums that play only that album; search for songs, artists and albums; playlists with custom names and any cover; animated synced lyrics; space bar play/pause; loop that doesn't break pause; working next and previous; profiles showing a friend's current song and listening time; Discord/TikTok-style chat; saved data such as Made For You; styles (Original always stays, Shooting Stars, Honey Bear, Spider, Sakura, Galaxy, Inferno, Neon) with their own play buttons and volume; custom fonts; custom wallpapers with the whole UI matching their colors; settings; the Vortex logo with no background shape; one install forever, with an update popup showing version, update log and an Update button, including on the sign-in and sign-up screens.

## How to work with the owner

- They are not a developer. Use plain words, short steps, and exact clicks. Never tell them to use a terminal if you can avoid it.
- Whenever they paste code from another AI, do not use it as-is. Treat it as an idea, check it against the real project, and rewrite it better. Pasted code has repeatedly been older than the project, and has had hardcoded tokens, broken URLs and fake logins.
- Read the real files first. Disk is the source of truth.
- Be honest about what was and wasn't tested. Never say something works if you only tested part of it. A past mistake: calling on-device audio working after fetching only 1 KB.
- Their family rejected invite codes. Do not bring them back.
- They do not want to pay anything. Do not recommend paid options as the default, and flag anything that may cost money.
- Do not ship new builds for every change. They want updates through the in-app popup. A hand install should only be needed when an old version genuinely can't update.
- UI must be clean and non-generic. They hate "AI slop": gradient text, glowing glass cards, tilted art, spaced-out capital labels, big "Featured" cards. Keep it flat, sharp and restrained, with radius around 8 to 10.
- Never mention servers on user-facing screens. Sign-in and sign-up must read like Spotify. Errors say things like "Check your internet connection and try again."

## Hard limits

- Do not bypass YouTube's bot checks: no cookies, no PO tokens, no residential proxies, no IP tricks. Tell the owner plainly if something would require this.
- On-device YouTube fetching with youtube_explode_dart was tried and removed. Google served 1 KB and then returned 403. Do not retry it.
- Never create accounts for the owner or enter payment details.
- Never publish or upload `.build/helper_secrets.json`, the Android debug keystore, the helper zip, or the project zip. They hold private keys. Moving them between the owner's PCs is the owner's job, by hand.

## Current state (2026-11-06)

- App version 1.2.3, live at https://twilight-meadowland-265.fly.dev
- Fly.io app `twilight-meadowland-265`, region `iad`, 1 GB volume `vortex_data` mounted at `/data`, shared-cpu-1x 512 MB, auto-stop on so it sleeps when idle. Owner is on Fly.io and must check billing themselves.
- Android 1.2.3 and Windows 1.2.3 have the Fly address built in. Download at `/download/Vortex-Phone.apk`, `/download/Vortex.apk`, `/download/Vortex-Windows.zip`.
- iPad and iPhone use the website through Add to Home Screen. A real iOS app needs a Mac and Apple's $99/year account. iOS project files exist in `app/ios` but have never been compiled.

### Waiting on the owner

1. Vortex Helper must run on their real home PC. It wasn't confirmed connected when this was written. Check with `GET /health`, which returns `audio_helper`.
2. **No account exists yet.** `/data` holds the owner's old data: `history.json` (about 79 plays), `profile.json`, `recommendations.json`, `images/`. The first account created claims it. So never create a test account on Fly before the owner has one. If you must test first, move those files aside over SSH and put them back.
3. Their home PC lags, so they use it only for the helper unless they choose otherwise.

### The open problem: song playback

YouTube answers `Sign in to confirm you're not a bot` for cloud servers, on every device. Fly.io is blocked for audio; search, lyrics and browse work there. The Shadow PC was blocked on and off.

The current fix is `helper.py`, running on the home PC. The owner wants songs with the PC off, for free, on mobile data at school. They've been told plainly that all songs, PC off and free can't all be had together without bypassing YouTube's checks. Options given:

- An old laptop or spare PC left plugged in as the helper ($0 if they have one). This was the recommendation.
- Their main PC as helper, when it's on (ready now).
- A Raspberry Pi (about $50 to $100 once).
- Free legal catalogs like Audius or Jamendo (not mainstream artists).
- Uploading their own music files.
- Apple Music or Spotify inside Vortex (paid per person, big rebuild). The owner refused paid options.

### Known not tested

- The update popup installing on a real device. The next released version is its first real test.
- Sound in the Windows and Android apps through the helper.
- Screen-off playback and lock-screen controls on Android.
- Anything in real Safari, including whether sound needs a tap first.
- The helper on real home internet. It worked with the helper on the Shadow PC, relaying full audio with seeking.

## How it fits together

- `main.py`: FastAPI server. SQLite at `$VORTEX_DATA/vortex.db`, per-user files in `users/<id>/`. Session tokens go in the `key` query parameter. Serves the web build at `/` and packages at `/download/...`, and `/release` for updates.
- `helper.py`: runs on the home PC. Starts a Cloudflare quick tunnel with bundled `cloudflared.exe`, registers its URL with Fly every 45 seconds using the helper secret, and serves `/audio/{id}`. Fly relays audio through it, and falls back to fetching itself when the helper is offline.
- `app/`: Flutter client.
  - `lib/main.dart` shell, nav, keyboard shortcuts (space, arrows)
  - `lib/auth.dart` sign-in and sign-up. Press and hold the logo opens the hidden server screen.
  - `lib/player_controller.dart` player, queue, loop, session, presence
  - `lib/api.dart`, `lib/models.dart`
  - `lib/screens.dart` home, search, library
  - `lib/now_playing.dart`, `lib/lyrics.dart`, `lib/artist.dart`, `lib/playlists.dart`, `lib/social.dart`, `lib/profile.dart`, `lib/settings.dart`
  - `lib/appearance.dart` styles and decorations. `lib/fx.dart` mesh background, palette from covers and wallpapers.
  - `lib/update_dialog.dart`, `lib/updater*.dart` update popup and installers
  - `test/generate_icons_test.dart` regenerates icons, then run `tool/flatten_ios_icons.ps1`

Windows audio uses `just_audio_media_kit` because `just_audio_windows` never played. Phones use `audio_service` directly through `lib/media_controls_io.dart`, so the media card drives Vortex's own queue. `android/app/src/main/res/raw/keep.xml` must stay: without it the release build deletes the card's button icons and the card silently disappears. An Android emulator (`vortex_test`, run with `-gpu host`) is on this PC for testing against a local server: `adb shell dumpsys media_session` shows what Android sees.

## Vortex Anime

`anime_app/` is a separate Flutter app (`com.shadow.vortex_anime`) using the same account, profile, friends and chat through `main.py`. Its list lives at `/animelist`. Release with `build_anime_release.ps1` (versions in `anime_app/CHANGELOG.json`), which writes `dist/VortexAnime.apk`, `dist/VortexAnime-Windows.zip`, `dist/anime_release.json` and `anime_app/build/web` (served at `/anime/`). The update popup reads `/release/anime`.

- `lib/connectors.dart` is the source registry. Each connector checks itself alone. AniList gives the catalog, Kitsu gives episode titles, thumbnails, subtitle and audio info, official YouTube playlists give video.
- `lib/watch.dart` is the Vortex player over YouTube's official iframe API (controls off, Vortex controls on top). Phones load the page inline, Windows and any hosted use load `web/player.html`. YouTube ignores `index` in `playerVars`, so a later episode needs `loadPlaylist` in `onReady`. But blocked videos only report error 150 reliably when the list is in `playerVars`, which is why both exist. Unconfirmed streams also have a 15 second time limit.
- `dist/anime_verified.json` is the confirmed list, served at `/animesources`, and it drives every "plays here" claim. To refresh it: run `tools/source_check/build_list.py` and `server.py`, load `index.html` in an Android WebView on a Canadian connection (hidden browsers won't autoplay), then run `publish.py` on `results.jsonl`. Results differ by country. It only keeps playlists starting at episode 1, in English, between 5 minutes and 2 hours. Don't assume a playlist works because AniList lists it: 16 of 565 played from Canada.
- `lib/library.dart` is My Library: the owner's own files and direct links, stored only in on-device preferences, played with `media_kit` (real subtitle, audio and quality tracks). Not yet confirmed: the picture on a real Android phone (black on the emulator, which forces software video, with sound and timer running), resume on reopening, and captions showing on screen.
- Tubi and RetroCrush were removed at the owner's request. `_removedSites` in `models.dart` filters them out of AniList's links.
- Re:ANIME, AniKoto, Anime-Sama, AnimeGG, AniWorld and Ani-Kage stay in the registry as reviewed and unavailable. There is no authorized access to their catalogs or video, so Vortex never contacts them. Don't add scraping or stream extraction for them.

## Vortex Anime App (the newer, separate anime app)

`C:\Users\User\Downloads\Vortex Anime App` is a second anime app (`com.vortex.vortex_anime`, Android + Windows) that signs in with these same accounts (profile, picture, banner, bio, pronouns, quote, status) and syncs saved shows to `/animelist`. Its update log reads `/release/vortex-anime` (`dist/vortex_anime_release.json`), with packages `dist/VortexAnimeApp.apk` and `dist/VortexAnimeApp-Windows.zip`. To release it: bump `CHANGELOG.json` in that project, run its `build_release.ps1`, copy its three `dist` files here into `dist`, then deploy as below. First deployed 2026-11-08 at 1.1.0. Its old sibling `anime_app/` and `/release/anime` are untouched.

## How to ship an update

1. Add a new top entry to `CHANGELOG.json` with higher `version` and `build`. `build` is the Android version code and must stay above 3000: phones on the old 1.2.3 phone file are at code 2006, and Android refuses a lower code. `build_release.ps1` gives both Android files the same code. Update `version:` in `app/pubspec.yaml` and the default in `lib/update_dialog.dart`.
2. For a server-only or website-only change, you may not need app packages. Devices only see the popup when `/release` shows a newer version with packages.
3. Set `VORTEX_SERVER=https://twilight-meadowland-265.fly.dev`, then run `build_release.ps1`. It needs Flutter, Visual Studio with the C++ desktop workload, Android SDK and Android Studio's JDK. Its Flutter path is `%USERPROFILE%\Documents\Codex\flutter-sdk-clean`, so fix it if Flutter lives elsewhere.
4. Deploy with `fly deploy --remote-only --ha=false --app twilight-meadowland-265`.

**Android signing:** builds use the debug keystore from the Shadow PC. It must be the same one or updates will fail to install. It is not in the project zip. The owner has to copy it by hand from Shadow's `%USERPROFILE%\.android\debug.keystore` to the same path on the new PC. Check that file exists before any Android build. If it was lost, a new build can't update existing installs, so everyone with the Android app must uninstall and reinstall once. Warn the owner before building in that case.

**Helper changes:** run `build_helper.ps1` with `VORTEX_SERVER` and `VORTEX_HELPER_SECRET` set (from `.build/helper_secrets.json`), then upload with `fly sftp put dist_helper\VortexHelper.zip /data/helper/VortexHelper.zip`.

**Setting up a new PC:** install flyctl from https://fly.io/install.ps1 after reading it, then `fly auth login`, with the owner approving in their browser. The build needs Flutter 3.47.9 (Dart 3.13.7). Windows builds need Developer Mode on, which the owner must turn on themselves.

## Lessons learned

- Temporary tunnel addresses die when a PC restarts, and installed apps saved them. The app now clears saved `trycloudflare.com` addresses.
- Windows may run out of memory on packaging after Android builds. The build script stops Gradle daemons first.
- Admin prompts time out if the owner is away. Warn them first.
- Test on real data with temporary data folders using `VORTEX_DATA` and `PORT`. Don't test on the real volume.

## What the owner asked for that isn't built

- Google and Apple sign-in (needs developer accounts).
- Forgot password (needs an email service).
- Real iOS app (needs a Mac and paid Apple account).
