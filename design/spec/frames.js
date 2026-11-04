// Every frame in the spec, in flow order. index.html reads this; so can tools.
// size defaults to 1440x900 (main window, points). spec = file in specs/ that documents the frame.
window.FRAMES = [
  { id: "01-films-empty", group: "Start", title: "Films, first launch", spec: "start.md" },
  { id: "02-films", group: "Start", title: "Films, list", spec: "start.md" },
  { id: "02-films-no-picture", group: "Start", title: "Films, no picture yet", spec: "start.md" },
  { id: "03-brief", group: "Start", title: "The brief", spec: "start.md" },
  { id: "04-footage-drop", group: "Start", title: "Script or footage", spec: "start.md" },
  { id: "05-footage-logging", group: "Start", title: "Logging footage", spec: "start.md" },
  { id: "06-assembling", group: "Start", title: "Building the assembly", spec: "start.md" },
  { id: "06-assembly-question", group: "Start", title: "The assembly asks", spec: "start.md" },
  { id: "06-assembly-ready", group: "Start", title: "The assembly is ready", spec: "start.md" },

  { id: "07-dailies", group: "Dailies", title: "Dailies, circling takes", spec: "dailies.md" },
  { id: "08-dailies-take", group: "Dailies", title: "Dailies, one take open", spec: "dailies.md" },
  { id: "09-dailies-unsorted", group: "Dailies", title: "Dailies, unsorted footage", spec: "dailies.md" },


  { id: "13-screening", group: "Cut", title: "Watching through", spec: "cut.md" },
  { id: "14-screening-quiet", group: "Cut", title: "Watching through, controls hidden", spec: "cut.md" },
  { id: "15-screening-mark", group: "Cut", title: "Watching through, mark dropped", spec: "cut.md" },
  { id: "16-watch-back", group: "Cut", title: "Back from watching through", spec: "cut.md" },

  { id: "17-notes-drafts", group: "Cut", title: "Notes, drafts after watching through", spec: "cut.md" },
  { id: "18-notes-writing", group: "Cut", title: "Writing a note", spec: "cut.md" },
  { id: "19-notes-region", group: "Cut", title: "Drawing a region", spec: "cut.md" },
  { id: "20-notes-questions", group: "Cut", title: "The editor's questions", spec: "cut.md" },
  { id: "21-notes-outside", group: "Cut", title: "Outside notes inbox", spec: "cut.md" },
  { id: "22-turnover", group: "Cut", title: "Turnover sheet", spec: "cut.md" },
  { id: "23-readback", group: "Cut", title: "Read-back, waiting for your OK", spec: "cut.md" },
  { id: "24-readback-adjust", group: "Cut", title: "Read-back, adjusting a line", spec: "cut.md" },

  { id: "25-cutting", group: "Cutting", title: "Editor cutting", spec: "cutting.md" },
  { id: "26-cutting-cant", group: "Cutting", title: "Editor can't do a note", spec: "cutting.md" },
  { id: "27-cutting-conflict", group: "Cutting", title: "Two notes conflict", spec: "cutting.md" },
  { id: "28-cutting-error", group: "Cutting", title: "Cut failed", spec: "cutting.md" },

  { id: "29-changes", group: "Cut", title: "A new cut arrived", spec: "cut.md" },
  { id: "30-changes-options", group: "Cut", title: "Two options", spec: "cut.md" },
  { id: "31-play-changes", group: "Cut", title: "Play changes", spec: "cut.md" },
  { id: "32-changes-thread", group: "Cut", title: "Replying to an answer", spec: "cut.md" },
  { id: "33-history", group: "Cut", title: "Every cut", spec: "cut.md" },

  { id: "34-lock-scenes", group: "Finish", title: "Locking scenes", spec: "finish.md" },
  { id: "35-lock-picture", group: "Finish", title: "Lock picture", spec: "finish.md" },
  { id: "36-finish", group: "Finish", title: "Finishing checklist", spec: "finish.md" },
  { id: "37-export", group: "Finish", title: "Deliver, choosing outputs", spec: "finish.md" },
  { id: "38-delivered", group: "Finish", title: "Delivered", spec: "finish.md" },

  { id: "39-share", group: "Share", title: "Share a screening link", spec: "share.md" },
  { id: "40-share-viewer", group: "Share", title: "Screening link in a browser", spec: "share.md" },
  { id: "41-agent-popover", group: "Share", title: "Editor popover", spec: "share.md" },

  { id: "42-settings-general", group: "Settings", title: "Settings, General", spec: "settings.md", size: "940x789" },
  { id: "43-settings-editor", group: "Settings", title: "Settings, Editor", spec: "editor.md", size: "940x789" },
  { id: "43-editor-per-job", group: "Settings", title: "Engines, Change per job…", spec: "editor.md", size: "524x410" },
  { id: "44-settings-cutting", group: "Settings", title: "Settings, Cutting", spec: "settings.md", size: "940x789" },
  { id: "45-settings-notifications", group: "Settings", title: "Settings, Notifications", spec: "settings.md", size: "940x789" },
  { id: "46-settings-shortcuts", group: "Settings", title: "Settings, Shortcuts", spec: "settings.md", size: "940x789" },
  { id: "47-settings-storage", group: "Settings", title: "Settings, Storage", spec: "settings.md", size: "940x789" },
  { id: "48-settings-sharing", group: "Settings", title: "Settings, Sharing & account", spec: "settings.md", size: "940x789" },

  { id: "49-command", group: "System", title: "Command menu", spec: "system.md" },
  { id: "50-shortcuts", group: "System", title: "Keyboard shortcuts", spec: "system.md" },
  { id: "51-offline", group: "System", title: "Offline", spec: "system.md" },
  { id: "52-media-missing", group: "System", title: "Footage missing", spec: "system.md" },
  { id: "53-menus", group: "System", title: "Context menus", spec: "system.md" },

  { id: "54-settings-engines", group: "Settings", title: "Settings, Engines", spec: "settings.md", size: "940x1651" },

  { id: "56-editor-setup", group: "Editor", title: "Who's editing? (setup)", spec: "editor.md" },
  { id: "57-editor-working", group: "Editor", title: "The editor at work", spec: "editor.md" },
  { id: "58-editor-stopped", group: "Editor", title: "The editor stopped", spec: "editor.md" },

  { id: "59-dailies-shots", group: "Footage", title: "Dailies, a take's shots", spec: "footage-index.md" },
  { id: "60-dailies-search", group: "Footage", title: "Dailies, search footage", spec: "footage-index.md" },

  { id: "61-changes-made", group: "Made", title: "Changes, made music", spec: "made-media.md" },
  { id: "62-notes-spend", group: "Made", title: "Notes, a spend question", spec: "made-media.md" },
  { id: "63-look", group: "Looks", title: "The Look sheet", spec: "looks.md" },
  { id: "64-changes-graphic", group: "Graphics", title: "Changes, a title's words", spec: "graphics.md" },
  { id: "65-settings-styles", group: "Styles", title: "Settings, Styles", spec: "styles.md", size: "940x789" },
  { id: "66-brief-style-list", group: "Styles", title: "The brief's style list, open", spec: "styles.md", size: "460x420" },

  { id: "70-script-empty", group: "Script", title: "Script, no script yet", spec: "script.md" },
  { id: "71-script-drafting", group: "Script", title: "Script, the editor writing the picture", spec: "script.md" },
  { id: "72-script-notes", group: "Script", title: "Script, your pass: a cell, notes, a question", spec: "script.md" },
  { id: "73-script-pass", group: "Script", title: "Script, after the editor's pass", spec: "script.md" },
  { id: "77-script-find", group: "Script", title: "Script, finding a word", spec: "script.md" },
  { id: "78-script-story", group: "Script", title: "Script, from a story", spec: "script.md" },
  { id: "74-breakdown-draft", group: "Breakdown", title: "Breakdown, the draft", spec: "breakdown.md" },
  { id: "75-breakdown-ready", group: "Breakdown", title: "Breakdown, before the shoot", spec: "breakdown.md" },
  { id: "76-breakdown-coverage", group: "Breakdown", title: "Breakdown, after the shoot", spec: "breakdown.md" },
];
