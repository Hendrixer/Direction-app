// Every frame in the spec, in flow order. index.html reads this; so can tools.
// size defaults to 1440x900 (main window, points). spec = file in specs/ that documents the frame.
window.FRAMES = [
  { id: "01-films-empty", group: "Start", title: "Films, first launch", spec: "start.md" },
  { id: "02-films", group: "Start", title: "Films, list", spec: "start.md" },
  { id: "03-brief", group: "Start", title: "The brief", spec: "start.md" },
  { id: "04-footage-drop", group: "Start", title: "Bring footage", spec: "start.md" },
  { id: "05-footage-logging", group: "Start", title: "Logging footage", spec: "start.md" },
  { id: "06-assembling", group: "Start", title: "Building the assembly", spec: "start.md" },

  { id: "07-dailies", group: "Dailies", title: "Dailies, circling takes", spec: "dailies.md" },
  { id: "08-dailies-take", group: "Dailies", title: "Dailies, one take open", spec: "dailies.md" },
  { id: "09-dailies-unsorted", group: "Dailies", title: "Dailies, unsorted footage", spec: "dailies.md" },

  { id: "10-script", group: "Script", title: "Script, reading", spec: "script.md" },
  { id: "11-script-marked", group: "Script", title: "Script, struck, held and moved lines", spec: "script.md" },
  { id: "12-script-readings", group: "Script", title: "Script, other readings of a line", spec: "script.md" },

  { id: "13-screening", group: "Screening", title: "Screening, playing", spec: "screening.md" },
  { id: "14-screening-quiet", group: "Screening", title: "Screening, controls hidden", spec: "screening.md" },
  { id: "15-screening-mark", group: "Screening", title: "Screening, mark dropped", spec: "screening.md" },
  { id: "16-screening-end", group: "Screening", title: "Screening, end of cut", spec: "screening.md" },

  { id: "17-notes-drafts", group: "Notes", title: "Notes, drafts after a screening", spec: "notes.md" },
  { id: "18-notes-writing", group: "Notes", title: "Notes, writing a note", spec: "notes.md" },
  { id: "19-notes-region", group: "Notes", title: "Notes, drawing a region", spec: "notes.md" },
  { id: "20-notes-questions", group: "Notes", title: "Notes, the editor's questions", spec: "notes.md" },
  { id: "21-notes-outside", group: "Notes", title: "Notes, outside notes inbox", spec: "notes.md" },
  { id: "22-turnover", group: "Notes", title: "Turnover sheet", spec: "notes.md" },
  { id: "23-readback", group: "Notes", title: "Read-back, waiting for your OK", spec: "notes.md" },
  { id: "24-readback-adjust", group: "Notes", title: "Read-back, adjusting a line", spec: "notes.md" },

  { id: "25-cutting", group: "Cutting", title: "Editor cutting", spec: "cutting.md" },
  { id: "26-cutting-cant", group: "Cutting", title: "Editor can't do a note", spec: "cutting.md" },
  { id: "27-cutting-conflict", group: "Cutting", title: "Two notes conflict", spec: "cutting.md" },
  { id: "28-cutting-error", group: "Cutting", title: "Cut failed", spec: "cutting.md" },

  { id: "29-changes", group: "Changes", title: "Changes, new cut arrived", spec: "changes.md" },
  { id: "30-changes-options", group: "Changes", title: "Changes, two options", spec: "changes.md" },
  { id: "31-play-changes", group: "Changes", title: "Play changes", spec: "changes.md" },
  { id: "32-changes-thread", group: "Changes", title: "Changes, replying to an answer", spec: "changes.md" },
  { id: "33-history", group: "Changes", title: "Cut history and changelog", spec: "changes.md" },

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
];
