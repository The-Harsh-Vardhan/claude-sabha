# Themes

A theme is a display skin: it renames the 20 roles on screen and gives each one a colour and a one-line persona.
Scripts, roles and models stay the same; only names, colours and personality change.

## File format

`themes/<name>.theme`: lines starting with `#` are comments. Exactly 20 other
lines follow, one per role, keyed by the plain role name (Relay, Dispatcher,
Architect, BuilderHeavy, BuilderPrecise, Reviewer, Writer, Runner, Scribe,
BackendCritic, FrontendCritic, SecurityCritic, ScopeCritic, BlindReviewer,
Keeper, Observer, Housekeeper, Tutor, Watcher, Coach):

    Role|ThemedName|#RRGGBB|persona

The plain role names are the ids the plan files, inboxes, status folders and role cards use; the theme only
changes what is shown. With no `SABHA_THEME` set the roles show their plain names.

- ThemedName: one word matching `^[A-Za-z][A-Za-z0-9]*$`, unique in the file,
  with no dash (copies are named `Name-1`).
- Colour: `#RRGGBB`, readable on dark terminals and on a white web page.
- Persona: at most 70 characters, one line, no `|`.

## Choosing a theme

Set `SABHA_THEME=<name>` in `sabha.conf`, or run `bin/sabha init --theme <name>`.
Available: mahabharat, avengers, hogwarts, middle-earth, plain. `plain` is the default.

## Adding your own

Copy `plain.theme` to `themes/<yourname>.theme`, change the names, colours and
personas, keep all 20 lines in order, then select it as above.

## Disclaimer

The avengers, hogwarts and middle-earth themes are fan themes. Character names
belong to their owners; claude-sabha is not affiliated with or endorsed by them.
