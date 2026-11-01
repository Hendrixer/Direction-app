# Mac conventions

Direction is a native Mac app first. Everything here applies across rooms and overrides room specs when they disagree. If a Mac user would expect it, Direction does it.

## Windows

- **One main window** (`Window` scene, id `main`): the Films list when no film is open, otherwise the film. Its frame is saved and restored between launches (`setFrameAutosaveName`). Minimum 1180 × 740 pt.
- **Custom 52 pt titlebar** over a full-size content view. The system traffic lights stay system-drawn, centered vertically in the bar at x 20.
- **Double-clicking the empty titlebar** does what System Settings › Desktop & Dock › "Double-click a window's title bar to" says (`AppleActionOnDoubleClick`): Zoom (default, also used for Fill), Minimize, or nothing. Dragging the empty titlebar moves the window. Controls in the titlebar don't drag.
- **Full screen** through the green button, View › Enter Full Screen (`⌃⌘F`), or the Screening dock. Screening in full screen hides the menu bar and Dock.
- **⌘W** closes the film back to Films. Closing the last window doesn't quit; clicking the Dock icon brings the main window back.
- **Settings is its own window**, the `Settings` scene: Direction › Settings… (`⌘,`). Toolbar tabs; the window title is the selected tab's name; the last tab is remembered; changes apply immediately (no OK or Cancel); `esc` and `⌘W` close it. Width 720 pt, height fits the pane and animates between tabs.
- **Sheets** attach to the main window and block only that window. `esc` cancels; `⌘↩` confirms. Popovers close on `esc` or a click outside.
- **No window tabs** (`tabbingMode = .disallowed`): a film is one window.

## Menu bar

Standard menus in standard order: Direction, File, Edit, View, Film, Cut, Playback, Window, Help. The full item list with shortcuts is in `system.md`. Required basics:

- **Direction:** About Direction, Settings… `⌘,`, Services, Hide `⌘H`, Hide Others `⌥⌘H`, Show All, Quit `⌘Q`.
- **File:** New Film `⌘N`, Open… `⌘O`, Open Recent (system-managed, via `NSDocumentController.noteNewRecentDocumentURL`), Close Film `⌘W`, Bring Footage… `⇧⌘I`, Share… `⇧⌘S`, Deliver… `⇧⌘E`.
- **Edit:** Undo `⌘Z` and Redo `⇧⌘Z` for every director action (write, edit or drop a note, circle a take, lock a scene, accept an answer, pick an option), plus Cut, Copy, Paste, Select All, Find `⌘F` (finds lines in Script, notes in Notes, takes in Dailies), Emoji & Symbols.
- **View:** the six rooms (`⌘1`–`⌘6`), Show or Hide Notes Sheet `⌥⌘S`, Command Menu `⌘K`, Keyboard Shortcuts `?`, Enter Full Screen `⌃⌘F`.
- **Window:** Minimize `⌘M`, Zoom, Fill, Center, Bring All to Front, the open windows.
- **Help:** Direction Help, Keyboard Shortcuts, Connect an Editor…

Every menu item has a matching context-menu item or button where it applies, and vice versa. Unavailable items are disabled, not hidden.

## Keyboard

- Everything can be done from the keyboard. With Full Keyboard Access on, every control is reachable with Tab and shows the Gate focus ring (2 pt text-1, 2 pt offset).
- `space` plays and pauses everywhere except in text. `J` `K` `L` shuttle. `←` `→` step a frame, `⇧←` `⇧→` a second. `↑` `↓` jump scenes. `N` marks. `esc` steps back out: closes overlays, ends region drawing, then ends screening.
- `↩` in a note field adds the note; `⇧↩` adds a new line. `⌘↩` runs the window's primary action.
- Room-scoped single keys never fire while a text field has focus.

## Documents and files

- `.direction` packages open from Finder, from the Dock, and with `open`. The Info.plist declares the document type. A film appears in Open Recent the moment it opens.
- Drop footage files or folders onto the window or the Dock icon to bring footage. Originals are linked, never copied or changed (unless Settings › Storage says to copy).
- Saving is automatic and continuous. There's no Save command; every change is written at once.

## System integration

- **Dock badge:** how many things wait for the director (questions plus unreviewed answers). Cleared when none are waiting.
- **Notifications** (UserNotifications) for a cut ready, an editor question, a can't-do and a delivery finishing, each switchable in Settings › Notifications and held during screenings when asked. Clicking one opens the film in the right room. They respect Focus.
- **Sleep:** while playing or screening, the display stays awake (`ProcessInfo.beginActivity` with `.idleDisplaySleepDisabled`); it's released on pause.
- **Quit** with a delivery running asks first: "Quit and stop delivering?"
- **Opening another film** (or a new one, or going back to Films) with a delivery running asks the same way, since closing a film stops its delivery: "Open “Teaser” and stop delivering?" with **Stop and Open** (or **Stop and Close**) and **Keep Delivering**. Keep Delivering leaves the film open and delivering.
- **Appearance:** dark only by design (`.darkAqua`), because footage is judged against black.
- **Accessibility:** VoiceOver labels on every control and mark (the marks' shapes are announced: "Director's mark at 01:12:08", "Editor's suggestion"), Reduce Motion (no shimmer, fades for slides and the sweep), Reduce Transparency (glass becomes solid steel-3), Increase Contrast (hairlines use line-2). Icon-only buttons have help tags (tooltips) with their shortcut.
- **Pointer:** I-beam in text, resize cursors on region and range handles, a pointing hand on nothing (Mac controls don't use it).
- **Trackpad:** two-finger horizontal scroll on the strip or picture scrubs; pinch on the strip zooms it in time.
- **Spelling:** note fields check spelling and grammar as you type, like any Mac text field.
