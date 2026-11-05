<!-- direction-job breakdown v6 -->
# Break down "{{film}}"

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

{{task}}

The breakdown is the director's plan for the shoot: every picture in the A/V script as a shot, grouped by setup (a place and its light, set up once), each with where its picture comes from. The shot numbers Direction gives become the slates the director says on camera, and Dailies files takes by them.

1. Read the film's style with `direction_style`; the brief is below. The director watches the breakdown fill in, so build it as you read: `direction_breakdown` with `includeScript: true` gives the breakdown and a page of 40 rows (`from`, then its `next`). Add that page's shots with one `direction_breakdown_update`, then read the next page. Start within your first minute; never plan the whole script before the first page is in.
2. Group by setup: one setup per place and light ("Desk at night", "On camera, day"), with what it needs (time of day, light, props, what's on the screen). Narration recorded on its own is a setup of its own, source sound. Screen recordings, shots to make and footage the director said they have go in setups with `noCamera`.
3. A shot for every row's picture: the rows it plays under, what we see, how to get it on the day, what it's for (when what we see doesn't say), size, move, seconds (the rows' seconds, unless the picture should run longer), and its source. A picture that runs across several rows is one shot; a row that cuts between two pictures has two. Titles, graphics and anything that can be made in Direction's graphics are source make with no estimate (they're free); a made shot needs a `makePlan` and an `estimate` from `direction_estimate`. Don't make anything now.
4. Write for a director who's never been on a set, as the skill shows: plain words, no crew shorthand (locked off, plate, cover, matte, layer, roll), every recording its own shot (never Take A and Take B), the script's moments by what happens in them rather than row numbers, and other shots by the numbers Direction last gave them. Fix whatever `toFix` lists.
5. In a film from a story (`kind: "story"`), read the writer's notes (`storyNotes`, with the first page) for the film's rules and what's still to decide. Talk in someone's own words is shot with sound: an on-camera setup that gives them room to talk (the mic, time for takes, what to ask), or, recorded on its own, a setup with one shot, source sound.
6. What the director set by hand stays theirs unless a note asks. Once it's OK'd, numbers are slates: never move a shot to another setup; add a new one instead.
7. Answer every note listed below: change the shots it names (or all of them, when it's about the whole breakdown), then reply in one sentence. Ask on a shot (`questions`) when only the director can choose; never ask what the brief lists under Already decided, which includes every question they answered on the script.

## The notes
{{notes}}

## The brief
{{brief}}

## Done
You're finished when every row has a shot and every note has a reply. End with {"finished": true, "summary": "<setups and shots in a sentence, and what it takes to shoot>", "needsYou": […]}.
