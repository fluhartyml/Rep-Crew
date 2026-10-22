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
//  Bundle ID:      com.nightgard.RepCrew
//  Platform:       iOS — iPhone only to start
//  Version:        1.0
//  Deployment:     iOS 17.0+ (his ask: "as low as we can to start. but not too low" —
//                  17 is the floor for SwiftData and @Observable)
//  Language:       Swift 5.0, SwiftUI, SwiftData
//  App Store ID:   (not submitted — name not yet reserved in App Store Connect)
//  Location:       /Users/michaelfluharty/Developer.complex/Rep Crew/
//  Built with:     Xcode 27.1 (27A9275)

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
//  ⚠️ PRIVATE. This is speech-to-text of a private call and names real people.
//  It is here because he asked for it. This repo has no remote; never publish it,
//  never quote it in App Store copy.
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
//  and then you can people different things Hannah what y'all do for your Navy
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
//  • "were going to start this app this morning"
//  • "iphone first and we will need the ios floor to be as low as we can to start.
//    but not too low." → iOS 17.
//  • Name: went through Sweat Pact, Pact/RepPact, Daily Reps, then Rep Crew.
//    "rep crew; daily acountability?" → "yes lets try that one".
//  • Icon: "use the icons as presented". His light + dark 1024 set (barbell squat,
//    both opaque) and his Contents.json, copied byte for byte. Tinted slot empty, as
//    he gave it. The tvOS Top Shelf set in his folder is unused (iPhone only).
//  • "pact should say challenge". No "Pact" anywhere in the app.
//  • Rep buttons: "(+5)(+10)(other)(+100) because 100 is variable and the chalenge
//    goal". The last button always adds the FULL daily goal; partial amounts go
//    through Other ("if i only logged one then i used "other" and need to do 99").
//  • "put delete challenge behind a . . . and replace it with a send to crew place
//    holder". Built as a REAL Send to Crew (no-placeholders rule): the share sheet
//    with today's results. He: "good catch".
//  • Crew roles: "the crew leader is just the first user that downloads and sets up
//    a challenge or whoever initiates a challenge". Everyone who joins = member.
//  • Distribution: "the app will be test flight for all of our discussions untill we
//    get ready to distribute to the world".

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
//              button. On his 16e 2026-10-22 ~12:1x.
//
//  His first real challenge on the 16e: "Pushups challenge", 7 days from Oct 22,
//  100 push-ups a day.

// ============================================================================
// MARK: - CREW + TESTFLIGHT PLAN (proposed, not built)
// ============================================================================
//
//  • The app can't create TestFlight invites; only the developer can, in App Store
//    Connect.
//  • Install: a TestFlight PUBLIC LINK (up to 10,000 testers, after Apple's beta
//    review, ~1 day for outside testers).
//  • Join: the leader taps Invite to Crew and sends a crew link (iCloud sharing,
//    CloudKit, works on iOS 17). The friend installs from TestFlight, then taps the
//    crew link to join. Proposed: both links in ONE invite message.
//  • TestFlight builds use CloudKit PRODUCTION. Deploy the schema to Production
//    before every upload that changes the crew data.
//  • His steps: create the App Store Connect record (it also reserves the name).
//    Nothing gets uploaded without his word.
//  ⬜ Open: can members edit the challenge, or only the leader? · He hasn't said
//     whether to plan invites this way.

// ============================================================================
// MARK: - ROADMAP
// ============================================================================
//
//  1. ✅ Solo challenges on one iPhone. Create a challenge (days, start date, daily
//        goal per exercise), log reps (+5/+10/Other/+goal, undo), see what's left
//        today, day-by-day record, Send to Crew (share sheet), About with build number.
//  2. ⬜ Crew: leader invites, members join, everyone sees each other's progress
//        (iCloud sharing).
//  3. ⬜ "Completed today" notifications to the crew.
//  4. ⬜ TestFlight public link + App Store Connect record.
//  5. ⬜ Later ideas from the call: strength log, rings, 2-mile run, chat.

// ============================================================================
// MARK: - HOUSE RULES THAT APPLY HERE
// ============================================================================
//
//  • 18 pt minimum text — use AppFont, never .caption/.footnote/.body.
//  • Build number = git commit count, via Scripts/post-commit. Run
//    Scripts/install-hooks.sh on every clone. Never hand-stamp.
//  • No placeholders or dead buttons — every control does something real.
//  • Every setting persists across launches (@AppStorage), never plain @State.
