<!-- direction-job style v1 -->
# Make a style for the director

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

The director asked for a style. In their words:

{{request}}

{{source}}

A style is how their videos look, sound and move, kept so the editor can cut every video that way. It goes in their Styles folder ({{stylesFolder}}) through `direction_save_style`, never by writing there yourself.

1. Read what they pointed you to: the brief (`direction_brief`), any references, and `direction_styles` for the styles they have (don't repeat one; build on it when they say so).
2. Decide the style: pace, picture, graphics, captions, transitions, sound, music, color, and what to avoid. Numbers over adjectives.
3. Make its parts in your working folder: graphics in `Graphics/<name>/` (check each with `direction_graphic`, note "unasked"), transitions in `Transitions/`, effects in `Effects/`. Use sounds and fonts the director gave you; don't make any with a service.
4. Save it once with `direction_save_style`: name, summary, tokens, guide and files.
5. If something needs the director (a font you don't have, which of two directions), ask with `direction_ask` before saving.

## The film you're in
{{brief}}

## Done
You're finished when `direction_save_style` has saved the style. End with {"finished": true, "summary": "<the style's name, and what it holds in a sentence>", "needsYou": […]}.
