# Themes

A theme is a skin over the 20 roles. It never renames a role: inboxes, status files, `claude -n` names and the plan
files keep the role ids (Relay, Dispatcher, BuilderHeavy, ...). A theme only says what is shown: a character name, a
colour and an icon on the statusline, the board and the pane titles, and a voice for the roles that chat with you.

## Choosing a theme

- `SABHA_THEME=<theme or preset>` in `sabha.conf`, or `bin/sabha init --theme <name>`.
- `/sabha-theme` (or `bin/sabha-theme`): `list` shows the themes and your presets with the current one starred, `show
  [name]` prints the 20 resolved rows, `use <name>` validates and sets `SABHA_THEME`. Names, colours and icons change at
  the next refresh; a voice applies when a role next starts fresh.

Shipped: mahabharat, avengers, hogwarts, middle-earth, plain. `plain` is the default and shows the role ids.

## Theme file

`themes/<id>.theme`. The id is lowercase letters, digits and dashes, starting with a letter. Comment lines start with `#`.
Header lines `key: value` and then exactly 20 rows, one per role:

    title: Avengers
    author: claude-sabha
    category: heroes
    fan: yes
    description: Earth's mightiest roles: Marvel heroes assigned by temperament.
    licence: MIT
    Jarvis|Relay|#2A9DB5|avengers/relay|Polished and courteous; a dry butler's wit.

    Character|DefaultRole|#RRGGBB|icon|voice

- Header: all six keys, once each; `fan` is `yes` or `no`; title at most 60 characters, description at most 200.
- Character: one ASCII word of letters and digits starting with a letter, at most 20 characters, unique in the file
  (case-insensitively). Copies show as `Name-1`.
- DefaultRole: each of the 20 role ids exactly once.
- Colour: `#RRGGBB`, readable on dark terminals and on a white page.
- Icon: `-` (the role's generic icon, `icons/plain/<roleid>.png`) or a stem such as `avengers/relay` whose
  `icons/<stem>.png` exists.
- Voice: how the character talks, in at most 200 printable ASCII characters, no `|`; it may be empty. Style only: no
  instructions, no "I am the real ...", no stereotypes. The job beats the voice. A voice reaches the opening prompt of
  Relay, Tutor and Coach only, the roles that chat with you; files, commits and code stay plain. Each role's job line is
  fixed and ships with sabha (the role card in `template/impl/protocol/`), not with the theme.

## Presets and layers

What is shown is built in three layers, each over the one before: the default (`plain.theme`), a theme (each character
takes its default role), then a preset: your diffs, kept in `~/.config/claude-sabha/presets/<name>.preset`. Shipped
files are never edited. A preset names any character from any theme (a multiverse team) and edits fields:

    theme: mahabharat
    BuilderHeavy|avengers:Hulk
    Relay|hogwarts:Hedwig
    Hulk.name|Gada
    Hulk.voice|Short, loud, cheerful.

- `theme:` is the base theme (default `plain`); roles you do not mention keep it.
- `Role|theme:Character` gives that role the character from that theme, with its colour, icon and voice.
- `Character.field|value` edits one field (`name`, `colour`, `icon`, `voice`) of the character you gave a role, addressed
  by its original name, so `Hulk.voice` still works after `Hulk.name`.
- Two roles may end up with the same name; routing uses the role id, so it works, and `/sabha-theme` warns.
- A theme and a preset of the same name: the theme wins.

## Checking a file

`bin/sabha-theme validate <name or file>...` is the one validator (CI, local use, and any directory submission). A
`.theme` is strict: any problem refuses it (exit 1). A `.preset` is lenient: a bad voice, name, colour or icon is a
warning, so your own file still loads; an unknown role, theme or character is always an error. The voice, title and
description are also checked for words and signs that read like an instruction (ignore, override, instruction, prompt,
system, secret, token, http, `<`, `>`, `$`, quotes, backticks and the like).

## Adding your own

For yourself: write a preset. For a shared theme: copy `plain.theme` to `themes/<id>.theme`, fill in the header and all 20
rows, run the validator, and send a pull request. Fan themes set `fan: yes`, use names only (no images, logos or quotes)
and honour takedown requests.

## Disclaimer

The avengers, hogwarts and middle-earth themes are fan themes. Character names belong to their owners; claude-sabha is not
affiliated with or endorsed by them.
