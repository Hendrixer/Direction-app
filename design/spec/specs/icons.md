# Icons

The frames draw icons from the SVG sprite in `gate.js` (`#i-<id>`). In the app, use the SF Symbol listed here. Don't ship the SVGs.

| Size class | Point size | SF Symbol config |
|---|---|---|
| `.ico.s` | 12 | `.font(.system(size: 11, weight: .medium))` |
| `.ico` | 15 | `.font(.system(size: 13, weight: .medium))` (default) |
| `.ico.l` | 18 | `.font(.system(size: 16, weight: .medium))` |
| `.ico.xl` | 28 | `.font(.system(size: 24, weight: .regular))` |

The rendering mode is monochrome and the color is inherited (`.foregroundStyle(.secondary)` unless the frame colors it). The minimum target is macOS 14 (SF Symbols 5).

**Three icons are custom and are not SF Symbols.** Ship them as template assets in the asset catalog:
- **`circle`:** the hand-drawn grease-pencil circle around a circled take. It's 38×30, stroke 1.8, amber, drawn as an open loop that overshoots. The path is in `gate.js`.
- **`gem`:** the editor's diamond. Draw it as a 45°-rotated rounded square, not `suit.diamond`, because the proportions matter. When it's 8 pt or smaller, use the `.mk.gem` shape in code instead of an image.
- **`mark`:** the director's pin. Use the `.mk.pin` shape in code (a rounded teardrop, amber). The SF Symbol `mappin` is for menus only.

| Icon id | Meaning | SF Symbol |
|---|---|---|
| play | Play | `play.fill` |
| pause | Pause | `pause.fill` |
| back | Back / reverse | `backward.fill` |
| fwd | Forward | `forward.fill` |
| plus | Add | `plus` |
| check | Accept, done, found | `checkmark` |
| x | Close, decline | `xmark` |
| lock | Locked scene or picture | `lock.fill` |
| unlock | Unlock | `lock.open` |
| region | Region anchor | `viewfinder` |
| range | Range anchor | `arrow.left.and.line.vertical.and.arrow.right` |
| turn | Turn over | `arrow.right` |
| exit | End screening | `rectangle.portrait.and.arrow.right` |
| circle | Circled take | **custom** (see above) |
| script | Script room, a script file | `doc.text` |
| strike | Strike a line | `strikethrough` |
| hold | Hold a passage | `curlybraces` |
| move | Move a paragraph | `arrow.up.and.down` |
| quote | Other readings | `quote.opening` |
| share | Share | `square.and.arrow.up` |
| link | Link, URL | `link` |
| gear | Settings, General tab | `gearshape` |
| search | Search, command menu | `magnifyingglass` |
| down | Disclosure, pop-up | `chevron.down` |
| right | Next, submenu | `chevron.right` |
| left | Previous | `chevron.left` |
| more | More actions | `ellipsis` |
| film | Film, scene, Cutting tab | `film` |
| folder | Folder, library location | `folder` |
| import | Bring footage | `square.and.arrow.down` |
| clock | Moment anchor, timecode | `clock` |
| ask | Question, help | `questionmark.circle` |
| warn | Warning, missing, can't | `exclamationmark.triangle` |
| revert | Revert this change | `arrow.uturn.backward` |
| reply | Reply | `arrowshape.turn.up.left` |
| eye | Watched, preview | `eye` |
| person | Outside person, viewer | `person` |
| people | Sharing tab, viewers | `person.2` |
| bell | Notifications tab | `bell` |
| keyboard | Shortcuts tab | `keyboard` |
| disk | Storage tab, offline drive | `externaldrive` |
| wave | Audio, waveform | `waveform` |
| speaker | Volume | `speaker.wave.2` |
| cc | Captions | `captions.bubble` |
| color | Color grade | `circle.lefthalf.filled` |
| titles | Titles | `textformat` |
| export | Deliver, export | `square.and.arrow.up.on.square` |
| full | Full screen | `arrow.up.left.and.arrow.down.right` |
| grip | Drag handle | `line.3.horizontal` (reorder rows); in lists use the system reorder control |
| note | Note, whole-cut note | `text.bubble` |
| mark | Director's mark | **custom shape**; `mappin` in menus |
| gem | Editor | **custom shape**; `diamond.fill` as a fallback in menus only |
| brief | The brief | `doc.plaintext` |
| takes | Dailies, takes grid | `square.grid.2x2` |
| setup | A setup named with "@" | `video` |
| take | A take named with "@" | `play.rectangle` |
| split | Compare A/B | `rectangle.split.2x1` |
| history | Cut history | `clock.arrow.circlepath` |
| offline | Offline | `wifi.slash` |
| trash | Drop, delete | `trash` |
| sidebar | Toggle sidebar | `sidebar.left` |
| sliders | Kind, options | `slider.horizontal.3` |
| cmd | Command key | `command` |
| star | (unused; reserved) | `star` |

For `hold`, use **`curlybraces`**. It reads as a bracketed passage at 13 pt, and the text-3 tint keeps it quiet.
| stack | Settings, Footage tab | `film.stack` |
| key | Settings, Services tab; Add Key… | `key` |
| grid | Contact sheet button (frame 59) | `square.grid.2x2` |
| cursor | Words button on a graphic answer (frame 64) | `character.cursor.ibeam` |
| terminal | Open Terminal (frames 56, 58) | `apple.terminal` |
| stop | Stop the editor (frame 57) | `stop.fill` |
| out | Get a key (opens a web page) | `arrow.up.right.square` |
| copy | Copy an install command (frame 56) | `doc.on.doc` |
