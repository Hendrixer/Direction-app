# Sounds and images the director keeps

The Library window (Window › Library) holds Direction's own transitions, moves and effects, the techniques the editor learned for the director, and the director's own **sounds** (music beds, stings, sound effects) and **images** (logos, stills, overlays). Sounds and images are kept outside any film, so they're there for every film and can be added without one. None of them is footage: they're never logged as takes, transcribed, synced or indexed.

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

One line says it all, as the Library shows it and the editor reads it: "Music · 2:14 · 92 BPM · D minor · piano, strings · no vocals", "Image · 1200 × 400 with transparency · reads "MOSS"".

## Naming and using one

- "@Name" in a note or the brief names a sound or image like a technique (`LibraryCatalog.entries`, `explain`). Direction's own names win over a file called the same.
- The editor lists them with `direction_library` (kind and words narrow it) and brings one in with `direction_import` `{library: "Name"}`. The film gets its own copy in `<film>.direction/Library/Sounds` or `Library/Images` (`MediaAsset.fromLibrary` names the file), so it plays and delivers whatever happens to the library later. Asked again, by name or by the shelf's path, it's the copy already in.
- Music is placed with `placeMusic`, an effect with `overwrite` on A3, an image with `cutaway` and `reframe`.
- Moving one to the Trash from the Library leaves the films that used it with their copies.
