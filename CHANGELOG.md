# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

### Fixed

- **After a release the web app loads the new version on the next visit (OPH-273).** The
  edge in front of the site kept the app's code for four hours whatever the server said, so a
  browser that had opened the app shortly before a release went on running the old one —
  About showed the previous version. Every file under `/app` now reaches the browser with the
  server's own `no-cache, must-revalidate`.

## [1.14.0] — 2026-09-28

### Added

- **The device keeps an extension request's tags (OPH-350).** Local schema v36 adds a
  nullable column to the extension's request table holding the request's tag names as a JSON
  list; the applier fills it from what the server sends, and a request already on the device
  fills in the next time the server sends it. The migration test's v24 fixture drops the new
  column and asks that it opens empty and fills; the v34 fixture now drops everything added
  after v34 — it had kept a later column, and the step that added it again failed the open.

- **The enterprise page's enquiry form can ask for a verification (EE-232).** Built with
  `VITE_SALES_CAPTCHA_PROVIDER` (`turnstile` or `hcaptcha`) and `VITE_SALES_CAPTCHA_SITE_KEY`,
  the form draws the provider's box, holds the send button until it is ticked, sends its
  answer with the enquiry and draws a fresh box after every attempt; a box that cannot load
  says so next to it, and the e-mail address below stays the way through. Built without
  them — the default — nothing changes: no script, no box, no field. A refused verification
  now reads as its own message rather than as a refused field.

- **A file the server itself receives is stored through one guarded path.** An
  attachment on an arriving email has no app or browser that could upload it, so the
  server writes it — and it now meets exactly the checks an upload from the app meets:
  the size limit, the type decided by the file's first bytes rather than its name (a
  photo sent as `invoice.pdf` is kept as the photo it is), and the storage quota,
  measured on the bytes. Nothing else can write a file this way; an app, an API key or
  an MCP client still uploads its own files directly.

- **Someone outside can send a photo with their request.** A public request
  page can now take one image or PDF, up to 5 MB. What it is gets decided by
  the file's first bytes rather than by its name, so a `.pdf` that is really a
  photo is stored and opened as a photo. A file we cannot accept never costs
  you the request: the words still arrive, and the page says which part did
  not.

  These files are marked as coming from outside and are never served back
  anonymously. On the request itself the desk now sees its attachments —
  which it never could before — and the ones a stranger sent say so, in
  words about where they came from rather than a claim about whether they
  are safe. A server can have them virus-scanned on the way in: a file the
  scanner flags is never kept, and the words "not scanned" appear only on a
  file that was not.

- **One link, several things to ask about — and the answer before the
  question.** A public link can now open onto a chosen set of topics instead
  of one: the visitor picks, then fills in the form. The older single-topic
  link is unchanged and is still what you get by default. The page also
  searches the answers that have been published for those topics, so somebody
  about to write in can read the fix instead — and the desk can see how often
  that happened.

  It all still works with JavaScript switched off, because the page is not
  allowed to run any: the search is an ordinary form, the results are links,
  and nothing about the visitor is stored anywhere — no cookie, no tracking.

- **The answer somebody worked out once, written down.** A desk can now keep
  its own answers: what people see, where it happens, and the fix. An article
  starts as a captured QUESTION — the method this follows says knowledge gets
  written while the work is still open, not in a documentation session nobody
  schedules — so a solved request turns into one with a single button, taking
  the comment you point at as the solution. Publishing is a separate
  permission from writing, because "is this fix right" and "is this ready for
  someone outside to read" are different judgements, made by different people.

  Reading and searching work with no signal, which is the point: the person
  who needs the answer is usually standing next to the machine. Search matches
  the way somebody types — `yazici` finds `Yazıcı` — and while you work a
  request, the articles that match it appear beside it.

- **The equipment register, and a QR label that opens it.** Machines, vehicles,
  computers and tools now have a place to live, with the filter a maintenance
  desk cannot get from a spreadsheet: what is about to run out. Each asset
  prints a QR label that a phone's own camera opens straight to its card — no
  extra app, and the tag is printed in text beside the code because a label on
  a lathe gets wet and scratched. When a warranty or a calibration is coming
  up, whoever holds the machine hears about it once; renewing the date arms
  the reminder again.

- **The list you already have in Excel can be loaded in.** Upload a CSV, read
  a line-by-line report of what will be created, updated or refused, and only
  then approve it — nothing is written before that. Turkish column headings
  and `31.12.2027` dates are understood as they are typed, because converting
  a thousand rows by hand defeats the point.

- **A request can say which machine it is about, and the machine remembers.**
  Requests now carry the equipment they concern, and every piece of equipment
  keeps the list of requests it has caused — including the ones already
  archived, which is the whole point: most of a machine's history is in the
  past. Alongside it are the twelve-month counts that answer the question
  nobody could ask before, namely whether a machine should be replaced rather
  than repaired again. Change windows can say which machines they touch, too.

- **A request now shows everything it caused, and a way to say it has come
  back.** The request screen lists all the work opened from it rather than one
  piece, and can open another without leaving the page. Where a request is
  waiting on something, it says what. And when the same matter turns up again,
  one action opens a new request carrying the old one's summary and ties the
  two together — the old one is left exactly as it was, because a request that
  was finished stays finished.

- **The search reachability gate refuses an exemption that is no longer true
  (OPH-348).** An entity may be exempt from having a screen that searches it,
  with a written reason ("no screen yet"). When a screen started calling it,
  the gate stopped looking at the exemption and carried the stale reason
  green. It now fails, naming the caller, until the exemption is deleted; the
  extension's change entity lost its exemption this way.

- **The device keeps which machine a draft request is about (OPH-349).** A
  request written with no signal waits on the phone as a draft, and a draft can
  now be written from a machine's card; the machine travels with it, so the
  request that arrives later is tied to the machine like one filed online. The
  one extension table the device writes into rather than mirrors, so the value
  is the device's own and a pull no longer takes it back off the draft on
  screen. Kept from local schema v35. The migration test gained a fixture for a
  device holding an unsent draft — the only kind that runs the new step — and
  deleting the step turns it red.

- **The device keeps what kind of work an extension's request is (OPH-346).**
  The server sends it with the request, and the queue filters by it with no
  signal, so the value lives in the local copy. Kept from local schema v34. A
  request already on the device fills in the next time the server sends it.
  The migration test's device-that-already-holds-requests fixture grew with it,
  and deleting the new step turns that test red.

- **The device keeps who asked for an extension's request, and where the
  answer goes (OPH-344).** The server always sent both; the local copy dropped
  them, so a screen with no signal could not show them. Kept from local schema
  v33. A request already on the device fills in the next time the server sends
  it. The migration test gained a fixture for a device that already holds such
  requests, the only kind that runs the column steps; it proved two older steps
  that no test had ever run.

- **The device's local copy learned one more kind of record (OPH-327).** An
  extension can register an entity that lives on the phone beside tasks and
  notes — pulled, searched by the same folded-text rules, and readable with no
  signal. The schema step is per entity rather than one step for several,
  because their shapes are decided by the features that add them and those
  land at different times. Nothing changes for an install without the
  extension: the table is there and stays empty.

- **A file can be attached to things the extension adds, not just the four core
  ones (OPH-325).** What a file may hang on is now a registry rather than a
  fixed list, so an extension can register its own kind and the upload, the
  read surface and the cascade all work without core naming it. The column
  stopped being an ENUM to allow it; the values core itself accepts are
  unchanged, and a kind nobody registered is still refused.
- **Search reaches what the extension stores (OPH-326).** The device's search
  runs off a registry of searchable entities instead of a hand-written list per
  table, so a kind the extension adds is findable with everything else, by the
  same folded-text rules. Local-first is unchanged: the query never leaves the
  device.
- **A push can say that a notification is waiting (OPH-329).** The wire
  contract has a third type, carrying an identifier and — when it should be
  seen — one fixed sentence chosen from the catalogue. Nothing about what
  happened travels with it: the device fetches the row itself. ADR-0038 said
  the payload had two types and it now says three.
- **A "+" on the home-screen widget (OPH-333).** Tapping it opens the app with
  the new-task sheet already up — the same sheet as the Home "+" button, with
  the same day pre-filled. It is a shortcut into the app rather than a way to
  add from the widget itself: a widget cannot take typed text, so nothing is
  created until you save. On iPhone it sits in the date header of the large
  sizes and in a narrow column of its own on the medium one; on Android it
  closes the header.
- **A widget per project, and two on the lock screen (OPH-336).** Each widget
  you place can now show everything, as before, or a single project — so two
  widgets can follow two projects, each named at the top in its own colour.
  On iPhone, iPad and Mac it is the widget's "Edit" (iOS 17 / macOS 14 and
  later); on Android, long-press the widget and reconfigure it (before Android
  12 the choice appears as you place it). A widget you never set keeps showing
  everything. The iPhone lock screen gains two small widgets: the next task
  and when it is due — overdue first, and saying "Overdue" in words, since the
  lock screen draws in one tint — and today's open count. Which tasks belong to
  which list is still worked out in the app, never in the widget.
- **A private widget, and a compact one (OPH-337).** Settings › General has a
  Widget card with two switches. "Private widget" shows "Private task" in
  place of every title — on the home screen, on the lock screen, in every
  project's widget — and it does that before anything is written for the
  widget, so the titles never leave the app at all; the counts, times and
  colours stay. It is also why the app now reads that setting before it
  writes a widget's data, even at start-up. "Compact widget" draws tighter
  rows with slightly smaller type, and never shrinks the circle you tap.
- **A project's tasks can be sorted (OPH-338).** The Tasks tab of a project
  has the same sort button as Home, at the end of its add-a-task row, with
  the same choices — date, priority, title, and reversed. It shares Home's
  choice, so both lists are always in the same order; until now the tab was
  simply in the order the tasks were created, newest first. Finished tasks
  still sink to the bottom whatever the order.

### Changed

- **A deploy no longer ships an extension commit whose own CI has not passed
  (OPH-345).** The core half of a release only reaches a server through the
  release gate; the extension half was fetched from whatever its ref pointed
  at. Now the deploy resolves that ref to one commit first, before any build,
  and continues only if that commit's run of the extension's CI workflow
  (`DEPLOY_OVERLAY_CI_WORKFLOW`, default `EE CI`) succeeded — a red, still
  running, never run or unreadable result stops it, with the reason in the
  job summary. The server is then handed that exact commit, not the ref, so
  what was checked is what ships. **Operators:** the extension token
  (`DEPLOY_OVERLAY_TOKEN`) now needs to read Actions runs as well as contents
  (fine-grained: Actions + Contents, read-only; classic: `repo`); without it
  the deploy stops and says so.

- **A server whose extension cannot be served now refuses, instead of serving
  the plain build's rules (OPH-343, ADR-0041).** An extension brings its own
  rules — who may delete what, which writes a device may push. Until now, if
  one failed to load, the API carried on without them, and a member it had
  restricted was served with the plain build's wider rights. Now, when an
  extension is enabled and fails to load — or is missing while the database
  holds migrations it wrote, or `EE_REQUIRED=true` says it must be there —
  every request except `/health/*` answers **503 `EXTENSION_UNAVAILABLE`**, and
  `/health/ready` answers 503 with the reason under `checks.extension`. A plain
  install (no extension, or `EE_REQUIRED=false`) is unchanged, byte for byte.
  Deploys that ship an extension set `EE_REQUIRED=true` themselves.

- **The app knows whether the server answered the last time it asked
  (OPH-342).** Most of the app works offline and never needs to know. A
  screen that writes straight to the server does: it can now grey itself out
  before it is pressed, and say why, instead of failing after someone typed a
  paragraph. The answer comes from the traffic the app already makes, not
  from the phone's network icon — hotel wi-fi is a network that reaches
  nothing.
- **The widget documents say what shipped (OPH-339).** The README gains a
  Widgets section; the widget design notes, the product spec and the roadmap
  were read against the code and corrected where they described a plan rather
  than the build — the widget's thirty-day horizon, the "+" that opens the app,
  the Android drawing layer, the Mac's one remaining signing step.
- **The Mac app needs macOS 12 or later.** The Flutter toolchain raised its own
  minimum, and the Mac build had not been run since the push-notification work,
  so the project and its CocoaPods lock now say what the build already did.
- **The Mac app is ready for its widget (OPH-335).** It now writes the widget's
  data and receives the widget's taps itself — the widget library the phones
  use has no Mac side, so on a Mac those writes had been failing silently. The
  widget arrives once its extension is signed with the developer account.
- **The documented extension surface matches what the code offers (OPH-328).**
  The seam reference lists the two registries above, and the attachments page
  stopped describing a shape that had been out of date since July.
- **The generated API reference follows the registry change (OPH-325).**
  `docs/openapi.json` and `docs/API.md` no longer enumerate the four attachment
  targets, because the route no longer promises exactly those four.

### Fixed

- **An account of your own no longer shows a team's controls (EE-290).** On a server that
  also serves teams, somebody with only a personal workspace met a "Requests" tab that could
  list nothing and send nothing, and Settings rows for running a team — services, SLA
  management, the team's AI keys, identity sources, the mail relay, public request links,
  outgoing webhooks, approvals, the audit log — over screens that could not load. The tab now
  appears only on a team's own address, those rows only for that team's owner or admins, and
  a web address left on the tab moves to Home. Inside a team, a personal task no longer wears
  the team's history button or people card. A server running without the enterprise
  extension shows none of it, whatever license it was left, and the Notifications group's
  subtitle names what the page holds.

- **On the web, "Open settings" in the alarm fix sheet no longer opens a dead tab
  ([#19](https://github.com/mahirozdin/alliswell/issues/19)).** The sheet sent every browser to an
  iPhone settings address. It now tells the three cases apart: a browser that has not been asked
  gets an "Allow notifications" button that asks; one that has blocked the site gets the address
  bar steps to unblock it and a "Check again" button; and one that cannot receive notifications at
  all (Safari on an iPhone outside the Home Screen) says how to get them, with no button. The
  Settings row now updates after the sheet fixes something.

- **The quick-access button stays under your finger while you drag it
  ([#17](https://github.com/mahirozdin/alliswell/issues/17)).** It used to fall behind — the
  faster the drag, the further — and a quick release could park it on the side you had just
  left. It now follows the finger exactly, from the first pixels of the drag, and lands on the
  side you let go of.

- **The enterprise page's list caught up with the app again.** Change management and
  problem records had moved into the app while the page still called them "API only";
  both are now listed as in the app, each naming the one part that still goes through the
  API (moving a change along; a problem's root cause and status). A live list across
  several units, which the page said did not exist, is listed as there, and three shipped
  capabilities that were missing are added: incidents apart from service requests, archived
  requests that stay readable, and the absence calendar. Two lines said more than the
  product does and now say less: the SLA line names what is still entered through the API
  (target durations, shifts, holidays), and the partners line no longer offers a
  per-customer SLA, which nothing can attach yet.

- **The enterprise page says what is there today.** Its "what is not in it yet?" answer
  still named an asset register, change approvals, a satisfaction survey and requests by
  e-mail — all shipped since — and its offline line promised that requests are edited with
  the internet down (tasks and notes are; a request is read offline, a new one waits as a
  draft, and writing to one needs a connection). The page's claims about the product are
  now built from one capability list, where each item says whether it is in the app, API
  only, in pilot or not there. The package table gains a row for every module, and the
  copy check refuses a page whose "not yet" answer, capability rows or offline sentences
  differ from the list, or whose other answers say something is missing.

- **CI and `docker-compose` pull MinIO from Chainguard's registry (OPH-347).**
  MinIO
  no longer publishes a public image: quay.io's `minio/minio`, which replaced
  Docker Hub's in 1.10.2, now issues a token and still answers 401 for the
  manifest. Both API jobs died on the container start before a single
  integration test ran, and a fresh `docker compose up` would have hit the
  same wall. `cgr.dev/chainguard/minio` is the same server; the
  storage-backed integration tests passed against it before the switch. The
  compose service runs as root so that a data volume written by the old
  image stays readable.
- **On Android, three things the app asks for in the background never
  happened (OPH-341).** Ticking a task's circle on the home-screen widget, the
  six-hourly refresh that re-arms your reminders without opening the app, and
  the midnight redraw that moves the widget to the new day all send a message
  to one small receiver — and that receiver had never been declared, so every
  one of those messages went nowhere, silently, since each of them shipped. It
  is declared now, open to this app only, and a test reads the manifest so it
  cannot quietly go missing again. The iPhone was not affected.
- **The Android widget turns the day over by itself (OPH-334).** Its groups —
  overdue, today, this week — used to stay on yesterday until the app was
  opened or a six-hourly background turn happened to run. A one-time job now
  asks for a refresh shortly after local midnight and schedules the next one,
  and every background refresh ends by redrawing the widget. It is not
  to-the-minute: Android may hold it until the phone's next maintenance window.
- **A link that starts the app now lands where it points (OPH-333).** Opening
  the app from a widget row, a calendar event or a printed label while it was
  not running could end on Home instead of the task: the link arrived while the
  session was still being restored, and nothing kept it. It now waits and is
  followed once you are signed in.
