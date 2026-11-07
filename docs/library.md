# Sounds and images the director keeps

The Library window (Window › Library, and the same library as a page in Settings › Library, where an entry opens as its own page) holds Direction's own transitions, moves and effects, the techniques the editor learned for the director, and the director's own **sounds** (music beds, stings, sound effects) and **images** (logos, stills, overlays). Sounds and images are kept outside any film, so they're there for every film and can be added without one. None of them is footage: they're never logged as takes, transcribed, synced or indexed.

## Where they live

- `~/Movies/Direction/Sounds` and `~/Movies/Direction/Images`, beside Styles and Techniques (`SharedSettings.soundsFolder`, `imagesFolder`; `DIRECTION_SOUNDS_PATH` and `DIRECTION_IMAGES_PATH` override them, and a test process gets folders of its own).
- Each file is kept as the director brought it. A file dropped in the folder in the Finder is on the shelf too.
- What Direction measured and what the director wrote about each is in the folder's `.library.json`, keyed by file name (`MediaLibrary`, `ShelfItem`).

## Bringing them in

- Drop files on the Library window, or Add Sounds or Images…. Sounds go to Sounds and pictures to Images; anything else is refused with its name. The same file again is the one already there; another with the same name becomes "Name 2".
- Music dropped on a film goes to Sounds instead of the footage, when Apple's sound classifier hears music in most of it and speech in little (`LibraryMeasuring.isMusic`; recordings over 15 minutes are taken as talk). A toast says so and offers Bring In as Footage.

## What Direction measures

`LibraryMeasuring` runs in the background when the window opens or the app comes back, for anything new or changed since it was measured:

- **Sounds:** length, and its level over time for the waveform (up to 96 bars). Music also gets its tempo, key (12 s or longer), integrated loudness, up to four instruments heard in a quarter of its seconds, and whether a voice sings. A sound effect gets what it sounds like ("whoosh"). The first measure decides music or sound effect (music in half its seconds and 4 s or longer); after that the kind is the director's.
- **Images:** size, whether any of it is see-through, and the words in it. A see-through image is read over white and over black, since a logo is often dark on nothing.

- **Beats and bars (music):** `SongBeats` hears where every beat falls, which beats start a bar, and the bars where the song moves on (the intro ends, a build, a drop), kept as `Measured.grid` (`BeatGrid`). The beat is followed by dynamic programming over the onsets (Ellis's tracker), at the tempo whose beats and halves meet the most of what's played, so a groove of threes against twos (kicks 3 + 3 + 2 sixteenths apart) isn't heard half again too fast. Music made to a click, most library music, then gets the one steady pace its hits lie on (60% of the loudest quarter within 25 ms of its sixteenths, and half in each third of the song), so a sparse stretch can't knock a beat off; music played without one keeps the beats as followed. Bars start where the harmony changes and the low end hits; the song moves on where the bars either side are least alike (Foote's novelty over four bars a side). Music with no steady beat (ambient, a tempo that changes) has `steady: false` and no grid, and says "no steady beat" in its line instead of a tempo; the tempo shown is the grid's. Sounds measured before this listening (`Measured.version` under 2) are measured again once.
- **Checked on:** clicks and a band made at known tempos (beats within a frame, bars on the first beat, sections at known bars), a pad and a tempo change (no steady beat), and Epidemic Sound's Try Again in parts: 80.0 BPM, where the old measure said 107 (its 3 + 3 + 2 groove), every beat within 2 ms of its drum hits at the median (4.5 ms at the 90th percentile), and the song moving on at bars 5, 9, 33, 41, 61, 81 and 85, at 0:12.0, 0:24.0, 1:36.0, 2:00.0, 3:00.0, 4:00.0 and 4:12.0.

One line says it all, as the Library shows it and the editor reads it: "Music · 2:14 · 92 BPM · D minor · piano, strings · no vocals", "Image · 1200 × 400 with transparency · reads "MOSS"".

## Naming and using one

- "@Name" in a note or the brief names a sound or image like a technique (`LibraryCatalog.entries`, `explain`). Direction's own names win over a file called the same.
- The editor lists them with `direction_library` (kind and words narrow it) and brings one in with `direction_import` `{library: "Name"}`. The film gets its own copy in `<film>.direction/Library/Sounds` or `Library/Images` (`MediaAsset.fromLibrary` names the file), so it plays and delivers whatever happens to the library later. Asked again, by name or by the shelf's path, it's the copy already in.
- Music is placed with `placeMusic`, an effect with `overwrite` on A3, an image with `cutaway` and `reframe`.
- The editor reads a song's grid in `direction_library` (`measured.grid`: tempo, beats a bar, the first beat, every bar's start and the changes as `{bar, at}`; `beats: true` adds every beat) and in the line under a note or the brief that names it ("Its beat: 4 beats a bar, a bar about every 3.00 s from 0.01 s (105 bars); it moves on at bar 9 (0:24.0)…"). Once the song is placed, edits can give times as its bars (`{bar: 9}`), and `placeMusic`'s `fit` makes it a length by joining its bars (agent-timeline.md › Music).
- Moving one to the Trash from the Library leaves the films that used it with their copies.

## Songs in parts

A music library sells a song whole or in stems: its drums, bass, instruments and melody (and vocals, when it has them), each the length of the song, which play the song together. The library keeps them as one song (`Song`, `ShelfItem.song` and `part`), so the editor can play some parts in one stretch and others in the next, and they stay in time.

- **Put together by name and length.** Once its files have been listened to, music on its own is put with others when they're the same length (within 0.25 s) and named the same once the part is taken out (`Stems.read`, `Stems.found`, `MediaLibrary.groupStems`). A stem heard as an effect (drums alone can be) still counts when it's 30 s or longer, and becomes music. The part is a word in brackets, or the last word after the first that names one: Drums, Bass, Instruments, Melody, Vocals, Keys, Guitar…; "Stems" is dropped, and "Full mix", "Main" or a name with no part is the full mix. "Bass Drop" is a song. A stem that comes later joins the song when it's named as its parts are and is as long.
- **Named as the library names it.** Epidemic Sound's zip unpacks to "ES_Try Again (Instrumental Version) - mr..wav" and "ES_Try Again (Instrumental Version) STEMS BASS - mr..wav": the song is Try Again, "Where it's from" says "Epidemic Sound, by mr.", and the version stays in the name only when another song would share it ("Try Again" and "Try Again (Instrumental Version)"; `Stems.title`). A folder dropped on the Library, or chosen with Add, brings the sounds and pictures in it.
- **The director decides.** In the Library a song is one card; its detail plays each part on its own with its waveform, and the director names the song, writes when to use it (a map of the song: where the drums come in, where the big part is) and where it's from, kept on every part. Take Apart makes each part a sound on its own and keeps it so (`song` is ""). A sound's Part of a song fields join it to a song by name, as the part they say; one part of each kind.
- **Named in notes.** "@Neon Drive" names the song, "@Neon Drive Drums" one part (`LibraryCatalog.entry(_:of:)`). `direction_library` lists the song once, with its parts.
- **One grid for the song.** Once its parts are put together, the song is heard once for all of them (`LibraryMeasuring.shareSongGrids`): its beat where the drums are clearest (the Drums part, with the whole mix at half under it, so an intro without drums keeps its beats), its bars and changes in the whole mix (its full mix, or every part played together), and every part gets that grid and tempo. A part heard on its own first (drums alone can sound like no steady beat) takes the song's. Grids are kept in the cache by the files they were heard from (`SongBeats.heard`), so a film's copies of the parts are heard once too.
- **In a film.** `direction_import` with the song's name, or any part's, brings every part in, in one revision; each copy has `MediaAsset.song` and `part`, named "Neon Drive Drums". `placeMusic` with `parts` places some of them, and `parts` changes where each is heard; wherever two play at once they play the same moment of the song (agent-timeline.md › Songs in parts).
