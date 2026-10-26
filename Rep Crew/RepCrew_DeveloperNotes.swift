//
//  RepCrew_DeveloperNotes.swift
//  Rep Crew
//
//  Developer Notes — Persistent Memory for AI Assistants
//  Created: 2026 OCT 22 (Claude Code)
//

// ============================================================================
// MARK: - PROJECT IDENTITY
// ============================================================================
//
//  Name:           Rep Crew
//  Subtitle:       Daily Accountability (App Store subtitle, 20 of 30 characters)
//  Bundle ID:      com.accountability.dailyrepcrew (his, 2026-10-22: "i want to remove
//                  nightgard and replace it with accountability"). Was com.nightgard.RepCrew
//                  through build 16; that build is a separate app on his 16e and still
//                  holds the Pushups challenge.
//  Xcode project:  Daily Rep Crew Accountability.xcodeproj, target + scheme of the same
//                  name, home-screen name "Daily Rep Crew Accountability" (his renames).
//  Platform:       iOS — iPhone only to start
//  Version:        1.0
//  Deployment:     iOS 17.0+ (his ask: "as low as we can to start. but not too low" —
//                  17 is the floor for SwiftData and @Observable)
//  Language:       Swift 5.0, SwiftUI, SwiftData
//  App Store name: Daily Rep Crew Accountability (his pick, 2026-10-22 13:2x). "Rep Crew"
//                  was refused by App Store Connect: "The App Name you entered is already
//                  being used." The home-screen name stays Rep Crew.
//  App Store ID:   (record being created by Michael from Xcode's Validate)
//  Location:       /Users/michaelfluharty/Developer.complex/Rep Crew/  (folder name unchanged)
//  Built with:     Xcode 27.1 (27A9275)
//  GitHub:         github.com/fluhartyml/Rep-Crew (public)
//  iCloud:         iCloud.com.accountability.dailyrepcrew (CloudKit public DB) + push

// ============================================================================
// MARK: - WHAT IT IS
// ============================================================================
//
//  A bodyweight-workout challenge app for a group of friends. The idea came from a
//  friend of Michael's on FaceTime, 2026-10-22: one person sends a challenge like
//  "100 push-ups and 100 air squats a day for 14 days", the others accept, everyone
//  logs reps through the day and counts down what's left, and the crew gets told
//  when someone completes the day. Aimed at people preparing for military fitness
//  tests and at any group of friends keeping each other accountable.
//  Mentioned for later: strength log, ring goals, 2-mile run, chat.

// ============================================================================
// MARK: - COMMISSION
// ============================================================================
//
//  Michael, 2026-10-22: "this is a commision". Rep Crew is a commissioned app, not
//  one of his own App Store titles. Terms, client and ownership are not on record
//  yet; ask him, never assume.

// ============================================================================
// MARK: - ORIGIN — HIS FACETIME TRANSCRIPTION (verbatim, 2026-10-22 ~11:1x)
// ============================================================================
//
//  Michael: "i was just talking to my friend and he was talking about wanting to
//  start an app i transcribed some but not all of the facetime chat"
//
//  Not private (his word, 2026-10-22: "privacy is not needed").
//
//  --- transcription, as pasted ---
//  OK now now what was it again like describe the app to me please well know what
//  the app that you're imagining not the real app a challenge to my friends or like
//  say hey man I'm gonna do 50 push-ups today and 100 or 50 pull-ups and 100 push-ups
//  or two push-ups and then if we had it like a winter deal like we could just
//  monitor each other's progress how many we've done for the day and all that stuff
//  you know updates on your thing so if you were doing it me and you were doing it I
//  could go dude let's try to do let's try to do 100 air squats every day at 100
//  push-ups every day and then you would accept that challenge and be like all right
//  I can do it and then every day we have to login and throughout the day we subtract
//  how many push-ups we did how many pull-ups air spots all the different things and
//  then you look at black push-ups today and then maybe like at the end of it if I
//  complete all my stuff it could say a notification James completed his daily
//  challenge would you chat with each other in the app or anything like that the
//  weather texting each other I just sent you a challenge in the daily week or
//  whatever or the day I'm gonna do a push-up today whoever wins whoever I'm gonna
//  talk to Brenda yesterday about it pull up simple it does matter it's got a few
//  things in it in the app to do the pull-ups and a couple sample workout routines
//  and stuff like that but after we got it there's two apps that we got I think
//  they're 399 each but if you both together you get them both for 599 bucks but
//  then you download it how many push-ups do I do 50 push-ups 200 push-ups every day
//  for the next 14 days and then on the pull-up thing I told her I can do eight
//  pull-ups consecutive pull-ups and then tell me that I gotta do pull up pull-up
//  multiply by 4×4 push-ups times five and then the push-up times four but yeah more
//  about it and say what do you think it to do but my idea is just you can challenge
//  friends on it and you don't have to on the Apple Watch you can friends and stuff
//  and then you can challenge them to like you can share your workouts with people
//  and then you can people different things [name] what y'all do for your Navy
//  workout stuff with all those guys that are going through that program like for
//  your workout then I'll just text each other what you're doing yeah I'm thinking of
//  something like that because I think it would be useful for all the people that
//  are getting ready to go into the military each other and push each other and
//  stuff like that anyways all these people are getting ready to join veteran made
//  this regular jumping jacks situps push-ups regular workout not like benchpress
//  anything like that I guess that could be something but I think that do you have
//  like papers or worksheets do they have like a like a checklist or anything like
//  that like that they give the people like a piece of paper push-up I'll look I
//  think it might be cool
//
//  - Strength log - Complete rings 2 mile run - I'll look into it and then I'll let
//  you know to be able to challenge friends to be able to do stuff group of a group
//  of Homies that just like to work out and exercise or sit fat and want to get in
//  shape and just to keep you accountable to the group of people with the app
//  --- end ---

// ============================================================================
// MARK: - DECISIONS (his words, 2026-10-22)
// ============================================================================
//
//  Start
//  • "were going to start this app this morning"
//  • "iphone first and we will need the ios floor to be as low as we can to start.
//    but not too low." → iOS 17.
//  • Name: Sweat Pact, Pact/RepPact, Daily Reps, then Rep Crew.
//    "rep crew; daily acountability?" → "yes lets try that one".
//  • "this is a commision". "privacy is not needed" (the transcription above).
//
//  Look and logging
//  • Icon: "use the icons as presented". His light + dark 1024 set (barbell squat,
//    both opaque) and his Contents.json, byte for byte. Tinted slot empty, as he gave
//    it. The tvOS Top Shelf set in his folder is unused (iPhone only).
//  • "pact should say challenge". No "Pact" anywhere in the app.
//  • Rep buttons: "(+5)(+10)(other)(+100) because 100 is variable and the chalenge
//    goal". The last button always adds the FULL daily goal; partial amounts go
//    through Other ("if i only logged one then i used "other" and need to do 99").
//  • No save button needed: reps are stored the moment they're tapped.
//  • "put delete challenge behind a . . . and replace it with a send to crew place
//    holder". Built as a REAL Send to Crew (no-placeholders rule): the share sheet
//    with today's results. He: "good catch".
//
//  Crew
//  • "the crew leader is just the first user that downloads and sets up a challenge
//    or whoever initiates a challenge". Everyone who joins = a crew member.
//  • A new challenge assembles a crew. Members already on the app (from other
//    challenges) just get a CHECK BOX. Someone new, or without TestFlight, gets a
//    share-sheet text or email with the TestFlight beta link.
//  • "the test flight invitation link should be a string saved in the settings so it
//    can populate among all crew members so any crewmember can send anyone a
//    testflight invite". Crew member 0 = Michael, who types the link into Settings
//    once; each person who accepts an invite gets it filled in ("hot potato").
//  • "i only expect three to be in the viral test viral was a metephore".
//
//  Crew messages
//  • "i want the crew leader to be able to push announcements of maybe one string
//    that pops up on crew members phones as a notification", members can respond
//    with their own line, and members can message all participants. "im not looking
//    for a chat session, more of a sending motivationals messages to the team".
//  • Replies: two buttons on the notification, like email. Reply = just the sender
//    (leader or member). Reply All = the whole crew. Reply comes first. He: "yes".
//
//  Distribution and process
//  • "the app will be test flight for all of our discussions untill we get ready to
//    distribute to the world".
//  • His plan: get the skeleton done → first TestFlight to his friend → the friend
//    invites his friends → Michael surveys the friend → future additions come from
//    those talks → TestFlight updates go out that evening to the crew.
//  • GitHub: github.com/fluhartyml/Rep-Crew, created at his word; first private,
//    then "it can be public".

// ============================================================================
// MARK: - HOW THE CREW WORKS (as built)
// ============================================================================
//
//  Settings (gear, top left): your first name, the TestFlight link, your crew number,
//  Invite to Crew, Your crew list, and the iCloud connection status.
//
//  Invite link (Invite.swift). The share-sheet text says what the challenge is, then
//  "1. Install Rep Crew with TestFlight: <link>" and "2. Then tap this to join:
//  repcrew://join?d=<base64url JSON>". The JSON carries the sender's name, crew
//  number, TestFlight link, iCloud ID and (optionally) the challenge. Custom URL
//  scheme in RepCrew-Info.plist. No server.
//
//  Accepting (JoinView): the challenge lands on this phone with the same crewID, the
//  TestFlight link fills Settings if empty, the sender joins Your crew, this person
//  becomes crew member sender + 1, and a Membership record tells the leader's phone.
//
//  iCloud (CrewCloud.swift): CloudKit PUBLIC database, container
//  iCloud.com.accountability.dailyrepcrew. Record types:
//    CrewChallenge  name = crewID; the challenge + memberIDs checked by the leader.
//    Membership     name = crewID.memberID; written by whoever joins.
//    CrewMessage    crewID, text, senderID, senderName, kind (announcement / message /
//                   reply), toID ("all" or one person), sentAt, title.
//  Home pulls in new members and "Invitations" (challenges you were checked for) on
//  launch, on return to the app, and on pull-to-refresh.
//
//  Notifications (CrewMessages.swift): CloudKit subscriptions, one per crew for
//  messages to everyone and one for replies to you. Category CREW_MESSAGE with text
//  actions Reply and Reply All. The leader's button says Send an Announcement; a
//  member's says Message the Crew. Each challenge shows its last 10 messages.
//  Settings → Notifications (NotificationSettings.swift). His word, 2026-10-23: "the team
//  leader toggles on and off only ones they are a member of, same for crew members"; coaches
//  ("god mode") can also get notices for every challenge.
//  🟡 BUILT 2026-10-23, not tested. One switch per subscription; off deletes it, on saves it,
//  and launch only re-creates the ones still on. Your challenges: crew-<crewID> (+ oneway-) per unfinished
//  challenge on this phone (messages + "finished today"), on by default. General: to-me,
//  invites, join-requests (leaders only), on by default. Coach only (GodMode.isOn): coach-<crewID>
//  per public challenge you're not in, crewID == X AND kind == "finished" AND toID == "all", off
//  by default. Saved in AppStorage: notificationsOff (IDs switched off), coachNotificationCrewIDs
//  (crews a coach switched on). Launch also deletes crew-/coach- subscriptions for crews no longer
//  on the phone or listed. No schema change (crewID, kind, toID already QUERYABLE).
//  ⚠️ Untested: a coach's notice keeps Reply / Reply All (same category), so a coach can reply
//  into a crew they aren't in.
//  Reply in the app + one-way announcements. His word, 2026-10-23: "yes add reply and reply all
//  in the app and the announcer can toggle one way announcement or replies enabled".
//  🟡 BUILT 2026-10-23, not tested. Long-press someone else's message → Reply (kind reply, toID =
//  sender) or Reply All (kind reply, toID "all"), same CrewCloud.send the lock screen uses. The
//  leader's announcement sheet has Allow replies (on by default, remembered in AppStorage
//  announcementAllowsReplies). Off sends kind "announcementOneWay" (existing STRING field, no schema
//  change), shown as 📣 like any announcement, with no Reply / Reply All in the app. Its notification
//  comes from a second subscription per crew, oneway-<crewID> (kind == "announcementOneWay", category
//  CREW_ANNOUNCEMENT, no actions); crew-<crewID> now adds kind != "announcementOneWay". Both follow the
//  challenge's one switch. ⚠️ Build 48 and older: an unknown kind reads as .message, so a one-way
//  announcement shows as a plain message (sender name, no 📣) and its notification still offers
//  Reply / Reply All, until that phone runs this build and re-saves crew-<crewID>.
//  God mode announcements, two separate cases (his words, 2026-10-23: "yes, god mode can announce" ·
//  "god mode where it goes to all crew" · "both are two separate cases of need").
//  🟡 BUILT 2026-10-23 (builds 59–60), not tested. (1) One challenge: a coach gets Send an
//  Announcement in any challenge's messages, same as its leader. (2) All crews: Settings → Coach Mode
//  → Announce to All Crews sends kind announcementOneWay with crewID "all-crews". Every phone keeps an
//  all-crews subscription (senderID IN him + coaches, category CREW_ANNOUNCEMENT), switch "Coach
//  announcements" in Settings → Notifications, on by default; it shows in every challenge's messages,
//  only when CloudKit's creator is a coach or him. Always one way: no Reply All to every phone.
//  ⚠️ Phones get it only after running build 60+ once (that saves the subscription).
//
//  Crew Directory (CrewDirectory.swift). His words, 2026-10-23: thumbnails, preferred contact on the
//  list, tap the name for the profile, Save to Contacts with the photo.
//  🟡 BUILT 2026-10-23 (build 61), not tested. People icon on Home. Everyone in your challenges (leader
//  + Membership, minus banned and blocked, minus you). New: Profile.contactPreference (STRING) — Settings →
//  Your profile → Preferred contact; the profile shows "Prefers …" and a Text button. Save to Contacts
//  already carried the photo.
//
//  Coaches only (ContactSeal.swift). His words, 2026-10-23: "every textbox has a privacy toggle but
//  the coache or coaches can overide the toggle and see" · coaches are made by long-press, nothing else.
//  🟡 BUILT 2026-10-23 (build 62), not tested on a device; seal/open round trip checked on the Mac.
//  Phone, email and FaceTime each get a Coaches only switch. A private field goes up blank and lives in
//  Profile.sealed, encrypted per coach + the owner (Curve25519 → HKDF → ChaChaPoly). Each phone's key
//  sits in iCloud Keychain; a coach's phone publishes CoachKey (coachkey.<ID>) on launch. Members re-seal
//  when the coach keys change. ⚠️ Schema: CoachKey, Profile.contactPreference, Profile.sealed are in
//  CloudKit-Schema.ckdb — import and deploy to Production BEFORE uploading build 61+, or profile saves fail.
//
//  ⚠️ The local store (challenges, reps) must stay OFF iCloud:
//  ModelConfiguration(cloudKitDatabase: .none). Without it, the iCloud entitlement
//  makes SwiftData try to sync it, fail, and open EMPTY (build 12).

// ============================================================================
// MARK: - BUILD LOG
// ============================================================================
//
//  1  7d3ca92  Solo challenges: create, log reps, what's left, About with build.
//  2  987ab26  His icon set, as presented. On his iPhone 16e.
//  3  c936aca  New-challenge placeholder: "Name, like 14-Day Push-up Challenge". On 16e.
//  4  f06fee8  "Other" kept on one line (it wrapped "Othe / r" on the 16e). On 16e.
//  5  b9e6411  Rep buttons +5 · +10 · Other · +daily goal; undo on the "to go" line.
//              Never installed on its own; build 6 includes it.
//  6  b0b7645  Delete Challenge into the … menu (still confirms); Send to Crew share
//              button. On his 16e ~12:16.
//  7–9         Developer notes only.
//  10 d6be5f7  Crew invites: Settings + TestFlight link, Invite to Crew, repcrew://
//              join link, Join sheet. On his 16e ~12:38; Pushups challenge survived.
//  11          Developer notes only.
//  12 ddd5c8f  iCloud: crew check boxes, Invitations, Membership records. ⚠️ OPENED
//              EMPTY (SwiftData tried to sync the local store). Store on the phone
//              untouched since 12:38; backed up to the Mac before any fix.
//  13 4b1d8a1  Fix: local store opts out of iCloud. On his 16e 13:03; challenge back.
//  14          Developer notes only.
//  15 88e220b  Crew messages: announcements, Message the Crew, Reply / Reply All on
//              the notification; push notifications on. On his 16e 13:13.
//
//  His first real challenge: "Pushups challenge", 7 days from Oct 22, 100 a day.
//
//  Tested so far: invite link round trip and message text (swiftc); repcrew://
//  registered (simulator offered "Open in Rep Crew"); app opens with data intact on
//  the 16e. NOT tested yet, and each needs a SECOND phone on another iCloud account:
//  tapping Accept, whether Messages makes repcrew:// tappable, check boxes reaching
//  a member, notifications arriving, Reply / Reply All. CloudKit queries may also
//  need queryable indexes (crewID, toID, leaderID, memberIDs) in the CloudKit Console;
//  if so, the error shows in Settings → iCloud.

// ============================================================================
// MARK: - BEFORE THE FIRST TESTFLIGHT
// ============================================================================
//
//  1. Michael: create the Rep Crew record in App Store Connect (reserves the name).
//  2. Michael (his sign-in): CloudKit Console → deploy the schema to PRODUCTION, with
//     indexes. TestFlight builds use Production, not Development. Repeat whenever the
//     crew data changes shape.
//  3. Switch aps-environment to production for the TestFlight build (archive does
//     this through the distribution profile).
//  4. Claude, at his word only: upload. Then Michael turns on the public link; Apple's
//     beta review for outside testers takes about a day.
//  5. Michael pastes the public link into Settings — he is crew member 0.
//  The app can't create TestFlight invites; only the developer can, in App Store
//  Connect. Public link cap is 10,000 testers (he expects three).

// ============================================================================
// MARK: - ROADMAP
// ============================================================================
//
//  1. ✅ Solo challenges on one iPhone. Create, log reps (+5/+10/Other/+goal, undo),
//        what's left today, day-by-day record, Send to Crew, About with build number.
//  2. ✅ Crew invites with the hot-potato TestFlight link. (built, untested on 2 phones)
//  3. ✅ Crew check boxes through iCloud. (built, untested on 2 phones)
//  4. ✅ Crew messages + Reply / Reply All. (built, untested on 2 phones)
//  5. ✅ First TestFlight. Build 21 in external review (external tester group); internal works (his
//        word 2026-10-22 16:2x).
//  6. ✅ Leaderboard — everyone sees each other's reps for the day (Leaderboard.swift).
//     Widened 2026-10-22 ~21:1x, his word: "i want the crew that have access to the app see
//     all of the challenges where they can see other crew members status" · "the crew is the
//     app downloader". Every challenge is published to CrewChallenge (with endsAt); Home lists
//     everyone else's under "Crew challenges", each opening to its board. Needs queryable
//     CrewChallenge.endsAt in the Production deploy.
//     His word, same evening: "i want the leaserboards to be grouped by if the user is a
//     member of the challenge and the grouping of all other challenges" → Home sections
//     "Your challenges" · "Other challenges" · "Finished". "we need to have a public/prifate
//     toggle when creating each challenge" → Challenge.isPublic (default on), CrewChallenge
//     isPublic 1/0; private ones are left off "Other challenges". ⚠️ The record still sits in
//     the CloudKit PUBLIC database, so "private" hides it in the app, not from the database.
//     His word: a one-person challenge is "a personal goal or some call it a personal
//     tryumph. others may want to join in ... it would cause viral participation" → boards
//     show with one person. "yes build it with the glyph maybe a home glyph for non home
//     sheets so you can always find your way home" → chart.bar glyph opens Leaderboards
//     (Your challenges · Other challenges); house glyph on every pushed screen pops to Home.
//     ✅ Step 2, his ask: a button on someone else's challenge to ask its leader to "tap in
//     and join". Built 2026-10-22 ~22:3x (JoinRequests.swift; compiles, untested on 2 phones).
//     Ask to Join → JoinRequest record → leader notified ("<name> asked to join"); leader's
//     challenge shows "Asking to join" with Approve / Decline. Approve adds them to
//     CrewChallenge.memberIDs (their Home Invitations offers Accept) and sends a ✅ "You're in"
//     message; Decline adds them to CrewChallenge.declinedIDs. New type JoinRequest +
//     CrewChallenge.declinedIDs → need a second Production deploy after first use.
//        Built 2026-10-22 ~21:00, compiles; untested on 2 phones. New iCloud record type
//        Progress (crewID, memberID, name, dayNumber, reps, complete, streak) — needs
//        queryable crewID + dayNumber, and Membership.crewID, in the Production deploy.
//  7. ✅ "Completed today" notification ("James completed his daily challenge"). Built 22:4x:
//        CrewMessage kind .finished ("🏁 Name — Finished today: …"), once per challenge day.
//  8. ✅ Watch sets + Health (rings), built 22:4x, compiles, untested on device. iPhone: Start Set
//        timer → RepEntry + HKWorkout (start/end only, no calories) — SetTimer.swift. Watch:
//        target "Rep Crew Watch" (com.accountability.dailyrepcrew.watchkitapp, embedded),
//        live HKWorkoutSession (time + calories) → Health; reps → iPhone via WatchConnectivity
//        (WatchBridge.swift). ⚠️ The Watch app has NO ICON — his to supply (Image Playground);
//        App Store upload will likely refuse it without one.
//  9. ⬜ Later ideas from the call: strength log, 2-mile run.
//  10. ✅ Photo board per challenge (PhotoBoard.swift, built ~21:4x, compiles; untested).
//        Long-press a thumbnail → Save to Photos; save button in the full-size view too (his:
//        "i want anyone to be able to long press on a photo or something similar to save to
//        their camera roll"). Poster deletes own; leader hides others' via PhotoRemoval.
//        New iCloud types CrewPhoto + PhotoRemoval (queryable crewID) for the Production deploy.
//      Photo board per challenge (his, 2026-10-22 ~21:3x): "photo board or photo thumbnails
//        for a challenge, maybe the crew is at a gym doing challenges together perhaps a
//        crewmember takes a picture of the team on the treadmills or someone doing swiming
//        laps". Crew adds from camera or library; thumbnails on the challenge; tap = full size.
//  11. ✅ Built ~21:5x (Moderation.swift; compiles, untested). Leader: long-press a board row →
//        Remove from Challenge; photo menu → Remove Photo and Ban. CrewBan record, honored only
//        when the leader wrote it; hides their rows, photos, messages; banned phone keeps its own
//        reps and shows "The leader removed you". Everyone: Block (this phone only, Settings →
//        Blocked → Unblock) on board rows and photos.
//      Leader kick / ban (his): "the leader can kick ban anyone that posts pervy pictures".
//        Leader also removes the photo.
//  12. ✅ Report a photo (built ~21:5x): Report record (kind, photoID, crewID, senderID,
//        senderName, reporterID, reportedAt) → CloudKit Console until god mode; photo hidden
//        for the reporter. Guideline 1.2 as read 2026-10-22 asks for: (1) a filter for
//        objectionable material ⬜, (2) report + timely response ✅ report / ⬜ his response,
//        (3) block abusive users ✅, (4) published contact info ✅ fluharty.me/support/repcrew (his pick)
//        + email, in About → Need help?
//        New iCloud types CrewBan + Report for the Production deploy.
//  14. ✅ Sign in with Apple (SignIn.swift, built ~22:1x, compiles; untested). His words:
//        "have a new crewmember register via apple" · "let apple handle the new user
//        validation so when we kick or ban it has weight" · "were not the apple id police we
//        are making our honest best effort to protect our crew members." Name scope only, no
//        email. RootView gates the app; credential state checked each launch (revoked →
//        sign in again); an invite link opened before sign-in is held. Entitlement
//        com.apple.developer.applesignin added (automatic signing registered it).
//  13. ✅ God mode (his, 2026-10-22): "i plan on having 'god mode'" · "my apple id gets god
//        permissions". Built 22:5x (GodMode.swift): Settings → God Mode → Reports (remove photo,
//        remove + ban); god's removals/bans honored like the leader's everywhere; god can remove
//        messages and ban on any challenge. ⚠️ GodMode.ids is EMPTY until his iCloud IDs are read
//        off his 16e (stored as "myCloudID"); Development and Production may differ — unverified.
//  17. ✅ Coaches (his, 23:1x): "a crew leader … gets moderator permissions for their only
//        challenges. my coach mode is for any challenge and i should be able to grant and ungrant
//        coach permissions to worthy individuals". CoachGrant (coach.<ID>; coachID, name), counted
//        only when HE wrote it. He: long-press a board row → Make / Remove Coach; Coach Mode →
//        Coaches list. Coaches: Reports + moderation on every challenge. Every removal/ban/grant
//        check now uses CloudKit's creatorUserRecordID, never a self-reported field.
//        CoachGrant needs a Production deploy after first use.
//  15. ✅ Leader moderation of messages (his: "the crew leader needs kick ban and moderator
//        permissions to remove announcements or photos"): Remove Message / Remove and Ban on a
//        message's long-press. MessageRemoval record (crewID, messageID, removedBy).
//  16. ✅ Photo filter (guideline 1.2): Apple's SensitiveContentAnalysis — blocks posting and hides
//        flagged photos, but ONLY on phones with Sensitive Content Warning on (Apple's design).
//  Camaraderie ideas (Claude-proposed 2026-10-22, he hasn't picked any): high-five a
//  teammate's row (one-tap notification) · "crew's all in" celebration when the last person
//  finishes · "just finished" alerts (= item 7) · welcome on the board when someone joins.
//  ⬜ Open question: can members edit a challenge, or only the leader?
//
//  TestFlight: ⚠️ SUPERSEDED 2026-10-22 ~22:2x, his word: "dont send to testflight unless
//  you built everything". Upload only when every item he asked for is built; list them first.
//  (Was, ~20:1x: upload every tested build to TestFlight right away, without asking.)
//  Build 39 bb2e19f uploaded 22:15. Production schema deployed by him 22:20 (CrewMessage,
//  CrewPhoto, Progress); CrewBan, PhotoRemoval, Report, JoinRequest still to deploy.
//  "we push to test flight and pull to our local devices and public beta testers
//  get them when apple approves" · "we could forget to upload the latest build if we held
//  off". Internal testers install right after processing; external waits on Apple review.

// ============================================================================
// MARK: - NEW MEMBER APPLICATION + WELCOME LETTER (his, 2026-10-24 ~08:4x)
// ============================================================================
//
//  His words: "it used to be a form email written by the sysop when the sysop created the bbs and
//  there was also a new user email the new user had to write to the sysop" · "maybe the new user
//  application is integrated with their new profile? … some just goes to the head coach" · "not a
//  gate at least not for me" · "yea". 🟡 BUILT (Application.swift), not run on any device:
//  • Sign in with Apple now asks for name + email. After the name, a one-time "Welcome to the Crew"
//    screen: email (Apple's, editable), why joining, fitness goals, onboarding ideas — coaches only,
//    sealed — plus the same profile section as Settings. Send or Not Now; no gate. Existing members
//    see it once too.
//  • Coaches: notification "<name> joined the crew" (Settings → Notifications → New crew members);
//    tapping it opens Coach Mode → New Crew Members. Each application → Send Welcome Letter opens Mail
//    with the letter (Welcome Letter, editable, starter text included), from his own address.
//  ⚠️ Schema: new CrewApplication type in CloudKit-Schema.ckdb — import to Development, deploy to Production.
//  ⚠️ Answers wait on the phone until a coach key is loaded. Production may give him a different ID
//    than GodMode.ids (unverified); if Coach Mode is missing on TestFlight, nothing reaches him there.
//  ⬜ FUTURE (his idea, not built): every head coach runs their own board, like starting a BBS
//    ("wildcat or renegade"), with their own switch to require approval of new members.
//

// ============================================================================
// MARK: - CHALLENGES LIVE IN ICLOUD (his, 2026-10-24 ~07:3x)
// ============================================================================
//
//  Found: he deleted the app on one phone and reinstalled from TestFlight; every challenge on
//  that phone was gone (the store was phone-only, `.none`, since build 12). His words: "the
//  challenges should be in the cloud … so when one phone is removed they still live on" ·
//  "icloud is the bridge between piers so if a pier deleted their app it doesnt effect the rest
//  of the crew". His "yes" 2026-10-24.
//  🟡 BUILT, not run on any device:
//  • RepCrewApp: the store syncs to the person's PRIVATE iCloud database (same container).
//    Models got defaults + optional to-many relationships, which CloudKit needs; stored names kept
//    so an existing store keeps its data. If iCloud can't open it, the same file opens phone-only
//    and Settings → iCloud says so.
//  • CrewRestore.swift: on every sync, challenges you lead or joined that are in the crew's shared
//    space but not on this phone are rebuilt, with your days from Progress where the per-exercise
//    split is certain. Your own iCloud copy wins over a rebuilt one. A deleted challenge is added
//    to the declined list so it isn't rebuilt (this phone only).
//  ⚠️ Schema: the private database's types (CD_Challenge etc.) are created in Development by the
//    first Debug-build sync; then Deploy Schema Changes to Production (his sign-in) before
//    TestFlight can back anything up. Until then TestFlight opens and works phone-only.
//  ⚠️ NOT changed, Claude's finding after the yes: identity stays the CloudKit user ID, not the Sign
//    in with Apple ID. The CloudKit ID is the same on every phone and every reinstall of the same
//    Apple ID; it differs only between Development (Xcode builds) and Production (TestFlight), which
//    is why his two phones look like two Michaels. God mode and bans check it server-side
//    (creatorUserRecordID); a self-reported Apple ID could be faked. Raised with him.
//

// ============================================================================
// MARK: - SHAKEDOWN BUGS — FIRST CALL WITH OUTSIDE TESTERS (2026-10-23 ~10:32)
// ============================================================================
//
//  Source: a recorded call between Michael and two testers (kept private; names
//  left out, his word: "names are superfluous"). Which TestFlight
//  build they were on: not stated. None of these is looked at in code yet.
//
//  1. ✅ FIXED 2026-10-23 (build 51 + schema deployed to Production 13:12): every CrewChallenge
//        save had been BAD_REQUEST, so the type never existed. Proven: Hannah's TestFlight
//        challenge reached James and his 16e lists all three. Was: Messages and challenges don't reach the other phone. Friend never saw his
//        messages or his swim challenge, even after relaunching; friend's new public
//        push-ups challenge didn't reach him.
//        His word: "the leader boards were supposed to show to all crew users not just
//        challenge participants because the crew person could see another crew
//        challenge and request to join in". Built in 27–29 (0bf1bc5, b1ae23c, 8ecf12f);
//        the friend saw the public/private toggle, so they had ≥ 28. So the code is in
//        their build and still didn't show. Lead (Claude inference, unchecked): the
//        22:20 Production deploy listed CrewMessage, CrewPhoto, Progress — not
//        CrewChallenge, which "Other challenges" reads. ⚠️ Unlikely now: he thinks the
//        two testers saw each other's activity and only he saw nothing. Better lead
//        (Claude inference, unchecked): his 16e runs the Xcode-installed build →
//        CloudKit DEVELOPMENT (Coach Mode showed "Development" 10-22); TestFlight
//        builds use PRODUCTION. Separate databases. Test: TestFlight build on his 16e.
//        Tested 11:4x: TestFlight 48 on his 16e (app deleted, reinstalled) shows no
//        public challenges; Settings → iCloud "Connected to iCloud", no error. Back to
//        the Production lead: crewChallenges() catches .unknownItem (what a missing
//        record type returns) and returns [] silently — CrewCloud.swift ~L119. Same in
//        refreshPending, members(). ⬜ App bug either way: surface that error.
//        CONFIRMED 11:56 on his screen: Production Record Types = CrewMessage,
//        CrewPhoto, Progress, Users only. CrewChallenge and Membership missing.
//        Fix: Deploy Schema Changes (Development → Production), his sign-in.
//  2. 🟡 BUILT 2026-10-23, not tested (his "yes do B"): Messages never makes repcrew:// tappable
//        (Claude inference). The share text now says: install TestFlight, then find the challenge
//        under Other challenges and tap Ask to Join. ⚠️ Private challenges have no way in from the text.
//        Was: In-app Share Challenge link won't open for a new tester. On the second tester's phone
//        it wasn't tappable ("the words aren't blue"); it showed as a picture card
//        "Join the Daily Rep…". She got in only when he texted his TestFlight link.
//  3. 🟡 BUILT 2026-10-23, not tested: "anonymous" is not in the code; the name was most likely empty
//        (Apple gives it only on the first sign-in) → "A crew member". Claude inference. Now the app
//        asks for a name whenever it's missing (NameView). Was: Sender shows as "anonymous" on a shared challenge / message.
//  4. 🟡 BUILT 2026-10-23, not tested: the transcript shows the prompt DID appear and he said no; iOS
//        never asks twice. The note now names Settings → Health → Data Access & Devices. Was: Save Set never prompted for Health: "set wasn't saved to Health · allow Rep
//        Crew to save workouts". Friend turned it on by hand in Settings → Health.
//        Whether the workout then landed in Health: unchecked.
//  5. ❓ He didn't get the 🏁 finished notification; the second tester did. They said it was their
//        challenge, not his. He: "I should be able to see everything" (god mode).
//        Open: should god/coach get finished-today on every challenge?
//
//  Feature asks from the same call (not bugs):
//  • Profile page per crew member (his, 2026-10-23 ~11:2x): "the crew each need a
//    profile page and on the profile page would be the links to contact phone email
//    facetime voice or facetime video". 🟡 BUILT 2026-10-23, not tested (Profile.swift):
//    Settings → Your profile (photo, phone, email, FaceTime); tap a name on a leaderboard,
//    or long-press a crew message → View Profile. Profile record = profile.<iCloud ID>
//    (the bare ID collides with the Users record). ⚠️ Schema: Profile is new — import to
//    Development and deploy to Production before TestFlight. Sign in with Apple gives name only
//    (no email, by his earlier choice), so phone/email must be entered by the member;
//    LOCKED, his word: "they have to manually add their contact info that way they can
//    omit or use alternate contact info". Every field optional; a button shows only
//    when that member filled it in.
//    His word, same minute: "i want their profile to have a contact photo of their
//    choice". Camera or library. His word 2026-10-23: "yes give them the photo board
//    protections coach level remove" → 🟡 BUILT: ContentFilter, Report (kind "profile" in
//    Coach Mode → Reports), Block, coach removal via PhotoRemoval removed.<photoID>.
//    His word: "they should be able to export (maybe import) from/to apple contacts so
//    they can invite someone to the crew". Export = save a member's profile card to
//    Contacts (his). Import = pick a contact → send the invite. LOCKED 2026-10-23: his
//    "maybe" meant "if possible", and it is. Apple's CNContactPickerViewController doc
//    (read 2026-10-23): the app "does not need access to the user's contacts and the
//    user will not be prompted for 'grant permission' access. The app has access only
//    to the user's final selection." Use single selection only.
//    LOCKED, his word: "i want it to be one contact and not all contacts". One contact
//    per pick or save; the app never requests access to the whole address book.
//    🟡 BUILT 2026-10-23, not tested: profile → Save to Contacts (CNContactViewController
//    forUnknownContact); challenge → Invite a Contact (picker, one phone or email → Messages
//    compose, or a mailto: link for an email). ⚠️ NSContactsUsageDescription added only as a
//    crash guard in case iOS asks when saving the card; the app never requests access itself.
//  • Two-way Health sync so other push-up apps and Rep Crew share counts. His word:
//    "two way sync would be prefered but not a deal breaker". Checked Apple's
//    HKQuantityTypeIdentifier list 2026-10-23: no push-up/rep count type exists
//    (pushCount = wheelchair pushes, per Apple's doc). Workouts (time, calories) can
//    cross both ways; reps cannot. LOCKED, his word 2026-10-23: keep the built
//    workout write to Health. ("Don't add Health read" superseded by his two-column
//    mapping below.)
//    His idea (OPEN): "can they list in two colums colum one is health app data and
//    colum two is crew app data and they match colum a with colum b". Column A =
//    Health workouts by type + source app; Column B = the member's Rep Crew
//    exercises; member pairs them by hand. His word: "if the crew app doesnt have a
//    workout that matches health apps column a crew app can create a new crew
//    challenge as needed" → unmatched A row offers New Challenge from it. Feasible (needs Health READ of workouts —
//    the plan says "read nothing unless he asks later"). LOCKED, his word 2026-10-23
//    ("lock in 022g"): build the matching screen; Health READ of workouts is approved.
//    LOCKED, his word: "colum a is the data source of truth" — the member matches A's
//    data to B's; Rep Crew counts what Health recorded and never edits or invents it.
//    LOCKED, his word 2026-10-23 ~14:15: how a matched workout counts is the MEMBER's
//    choice — "maybe a toggle left for the crew member to decide" / "if in doubt let the
//    user decide" (a standing design rule: unsure → make it the user's setting). Health
//    workouts carry time + calories, no reps; options: off, checks off the day, minutes,
//    calories.
//    🟡 BUILT 2026-10-23, not tested (HealthMatch.swift; compiles). Settings → Health → Match
//    Health Workouts, and the same link on every unfinished challenge. Column A = last year of
//    workouts by type + source app, minus Rep Crew's own (source bundle ID starts with ours, or
//    brand "Rep Crew"); Column B = exercises of unfinished challenges. Each A row → one exercise,
//    or "New Challenge from <workout>" (prefilled, 1 a day, paired on save). New pairings start
//    Off. Pairings are SwiftData (new @Model HealthMatch, cascade with its ExerciseGoal).
//    Checks off the day → ExerciseGoal.isMet is true that day. Minutes / Calories → summed per day,
//    shown on the goal and under your name on the board (board still ranks by reps). Health read
//    asked in the same prompt as saving sets; Home/detail only ask once something is paired.
//    ⚠️ Schema: Progress gains minutes + calories (INT64) — import to Development, deploy to
//    Production. Until then a Production save retries without them, so reps still post.
//    ⚠️ Untested: what Health returns when read is denied (expected: empty list), calories from
//    apps that store energy only as samples, a workout spanning midnight (counts on its start day).
//  • Teams / groups for large crews (his idea, 2026-10-23 ~14:20, OPEN — after this TestFlight
//    round). His words: "since the crews could potentially become large should we somhow have
//    group flags of some sort? groups or teams?" and "if the app were to go viral and smittys
//    'team' is his emediate family and if i were to send an invite link for test flight to my
//    neighbor and smitty sent out invites to his friends, it seems like factions naturally start
//    forming". Real scaling issue behind it: today everyone sees every challenge under Other
//    challenges. Option floated (not decided): record who invited whom so each invite chain lands
//    in its own group by default; and/or leader-assigned teams with a team total on the board.
//    Open question to him: teams competing, or just grouping a big list?

// ============================================================================
// MARK: - PLAN: LEADERBOARD + WATCH + HEALTH (his, 2026-10-22 ~20:00)
// ============================================================================
//
//  LEADERBOARD (his: "i would insist on a leaderboard")
//  • Crew listed in numerical order by TODAY'S reps. Resets every morning.
//  • Never label places — no 1st/2nd/3rd, no medals. "i would imply the ranking and not
//    be explicit."
//  • Not the whole-challenge total: "that would ... promote discouraging the last one ...
//    if the underdog was always last even though they had a good day."
//  • Each row: name, today's reps, streak 🔥 if any. Header: "Day 9 of 30 · Crew 3/4 ✓".
//
//  RINGS — imply, never say (his: "we would never say 'close your rings' or any trade
//  marks ... it closes rings on the watch and health app")
//  • No Apple trademarks or ring artwork in the app. The rings close because real workouts
//    land in Health.
//
//  WATCH + HEALTH
//  • Watch app: "Start set" runs a real HKWorkoutSession (strength training). Watch
//    measures time + calories → saved to Health → rings move. Reps go to Rep Crew.
//  • iPhone without a Watch: the same "Start set" timer, saved as a workout with real
//    start/end only → Exercise credit, no calories. NEVER invent time or calories.
//  • Health permission: write workouts only. Read nothing unless he asks later.
//    SUPERSEDED 2026-10-23: read workouts + active energy approved for the matching screen.
//  • Sources (2026-10-22, not yet tested on a device): Apple Support "How to manually add
//    a workout in the Health app" — calories earn Move, start/end time earns Exercise;
//    Apple's archived ActivityRings sample — a workout saved on Watch counts toward the
//    rings; Apple DevRel on the developer forums — rings reflect data saved to HealthKit.
//  • Today RepEntry holds only a count — no duration. The set timer is what supplies it.

// ============================================================================
// MARK: - CUSTOMER ASKS: SMITTY'S FACETIME (2026-10-26 ~11:55, NOT BUILT)
// ============================================================================
//
//  ⬆️ PRIORITY (his, 2026-10-26 12:1x): "these are higher priority than what we discussed
//  this morning because this morning was our R&D smitties transcript was discussion with our
//  customer." → These come BEFORE "PLAN: MANY CREWS, BY ZIP CODE" below.
//  Source: Transcription Keeper text AirDropped to ~/Downloads (text-25A1C245BA26-1.txt).
//
//  1. ORGANIZE THE HOME PAGE — Active / Available / Finished challenges
//     Problem (Smitty): "if everybody puts challenges on here I'm kind of screwed … it'll be
//     like too long … to get to the different challenges that I could join I'm scrolled to
//     bump." Michael's framing: a zillion challenges become wallpaper.
//     Ask (Smitty): "one thing that says finished challenges active challenges available
//     challenges … then you click on those and it would send you … just open up the next page."
//     Home shows your name and your active challenges up top.
//
//  2. WEEKLY SCHEDULE — pick exercises per day
//     Ask (Smitty): "a weekly schedule like Monday Tuesday Wednesday Thursday Friday and then
//     you can click which day you do … I don't think people need to do the same exercise every
//     day." Michael's reading: routines by muscle group — leg day, chest day, swim day, arm day.
//     Uses the existing exercise library.
//
// ============================================================================
// MARK: - PLAN: MANY CREWS, BY ZIP CODE (talked through 2026-10-26 ~09:15–10:25, NOT BUILT)
// ============================================================================
//
//  WHY (his question): as built, every download joins ONE crew — his. One public CloudKit
//  database (iCloud.com.accountability.dailyrepcrew), Head Coach hard-wired to his iCloud
//  ID (GodMode.ids). 100 strangers from 50 states would all share the same challenges and
//  photos. His: "we need to make 'tribes' or localize crews."
//
//  WORDS (his): a crew member name is a person; a crew name is a group of crew members.
//  The Head Coach → Crew Name screen names the group, so it stays (not renamed to
//  "Crew Member Name").
//
//  THE LADDER (his names, his ZIP idea; the 1 → 3 → 5 split was Claude's suggestion, he
//  agreed):
//    Head Coach (him, god mode)   → the continental US
//     └─ Regional Area            → ZIP 1st digit       (4     = OH, IN, KY, MI)
//         └─ Metro Organization   → ZIP first 3 digits  (452   = Cincinnati)
//             └─ Local Team       → full 5-digit ZIP    (45230 = Mt. Washington)
//                 └─ Crews → Crew Members
//  • Skip the 2-digit level: it matches no Post Office unit, so groups would cut across
//    real areas. (Claude's; he agreed.)
//  • Local Teams per ZIP: unlimited (his: "local can be infinite"). Members per ZIP:
//    unlimited — families share ZIPs.
//  • A crew is two or more people (his). The smallest group of people.
//  • Still OPEN: does a Local Team hold several crews, or is the team the crew? And how
//    many crews per ZIP — he said both "max" (one per ZIP) and "infinite"; asked, not
//    answered.
//
//  LEVEL 0 — THE FIRST DOWNLOAD (his: work from the base up)
//  • First step on first launch: type the 5-digit ZIP code (his pick over GPS — no location
//    permission). The app looks up city / county / state (Apple's geocoder, from memory,
//    NOT tested) and shows e.g. "Cincinnati, Hamilton County, Ohio"; the person confirms or
//    fixes it — some ZIPs cross county or city lines.
//  • Nobody exists yet in a new area, so there is no leader to accept anyone. The first
//    person is the catalyst: they create a challenge and become that crew's leader (his).
//  • ZIP center points let the app rank crews by distance — same ZIP first, then
//    neighbors — without anyone's exact location.
//
//  ZIP+4 — PRIVATE, LIKE THE LAST FOUR OF A SOCIAL (his)
//  • The +4 is a delivery segment (one block side, one building), close to an address.
//  • Idea (his): use it to help an orphaned crew member find a crew close by.
//  • Rule: never shown next to a name, never shared. If used at all, only on the person's
//    own phone to sort nearby crews; never saved to iCloud. The app asks for 5 digits.
//
//  PERMISSIONS — A CHAIN OF GRANTS (Claude's proposal; not yet confirmed by him)
//  • CloudKit cannot enforce "only a Texas coach edits Texas" on the server. What it cannot
//    fake is who wrote a record — the same check Crew Name already uses (GodMode.ids).
//  • He grants Regional; each coach grants only below their own level and inside their own
//    area; every phone checks the chain back to him and ignores a broken link; anyone above
//    can revoke, and everything that grant made possible goes with it.
//  • Weak spot: a rogue coach does damage in their own area until someone above revokes.
//  • OPEN: can coaches delete members' posts/photos in their area, or only manage people?
//
//  ALREADY IN PLACE: report and block (his word) — App Store guideline 1.2 for apps where
//  strangers post.
//
//  CLOUDKIT FACTS FROM THE SAME TALK
//  • Public-database storage is billed to the app's container under his Developer account —
//    not to his or any user's personal iCloud plan. Apple doesn't bill for it; the free
//    allowance grows with active users. What happens past the allowance: unverified.
//  • Photo size: 1600 px JPEG + 400 px thumbnail at 0.75 (PhotoBoard.jpegFile); estimated
//    0.3–0.5 MB per photo, so 500 photos ≈ 150–250 MB (estimate, not measured).
//  • Count: Census 2024 lists 33,791 ZIP code areas (33,300 continental); the Post Office's
//    own count is about 41,000 incl. PO-box-only ZIPs (from memory, unchecked).
//  • Reference map Claude built for this talk: "Continental US ZIP Codes" artifact (type a
//    ZIP prefix, see the area light up).

// ============================================================================
// MARK: - HOUSE RULES THAT APPLY HERE
// ============================================================================
//
//  • 18 pt minimum text — use AppFont, never .caption/.footnote/.body.
//  • Build number = git commit count, via Scripts/post-commit. Run
//    Scripts/install-hooks.sh on every clone. Never hand-stamp.
//  • No placeholders or dead buttons — every control does something real.
//  • Every setting persists across launches (@AppStorage), never plain @State.
