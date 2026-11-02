<!-- direction-job breakdown v1 -->
# Break down "{{film}}"

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

{{task}}

The breakdown is the director's plan for the shoot: every picture in the A/V script as a shot, grouped by setup (a place and its light, set up once), each with where its picture comes from. The shot numbers Direction gives become the slates the director says on camera, and Dailies files takes by them.

1. Read the script and the breakdown with `direction_breakdown` (`includeScript: true`), and the film's style with `direction_style`. The brief is below.
2. Group by setup with `direction_breakdown_update`: one setup per place and light ("Desk at night", "On camera, day"), with what it needs (time of day, light, props, what's on the screen). Narration recorded on its own is a setup of its own, source sound. Screen recordings, shots to make and footage the director said they have go in setups with `noCamera`.
3. A shot for every row's picture: the rows it plays under, what we see, size, move, seconds (the rows' seconds, unless the picture should run longer), and its source. A picture that runs across several rows is one shot; a row that cuts between two pictures has two. Titles, graphics and anything that can be made in Direction's graphics are source make with no estimate (they're free); a made shot needs a `makePlan` and an `estimate` from `direction_estimate`. Don't make anything now.
4. What the director set by hand stays theirs unless a note asks. Once it's OK'd, numbers are slates: never move a shot to another setup; add a new one instead.
5. Answer every note listed below: change the shots it names, then reply in one sentence. Ask on a shot (`questions`) when only the director can choose.

## The notes
{{notes}}

## The brief
{{brief}}

## Done
You're finished when every row has a shot and every note has a reply. End with {"finished": true, "summary": "<setups and shots in a sentence, and what it takes to shoot>", "needsYou": […]}.
