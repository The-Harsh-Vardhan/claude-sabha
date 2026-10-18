# Themes

A theme renames the 20 roles and gives each one a colour and a one-line persona.
Scripts, roles and models stay the same; only names, colours and personality change.

## File format

`themes/<name>.theme`: lines starting with `#` are comments. Exactly 20 other
lines follow, in the canonical role order (Vidur, Yudhishthira, Bhishma, Bhima,
Arjun, Sahadev, Nakul, Karna, Sanjaya, Duryodhan, Dushasan, Shakuni, Draupadi,
Gandhari, VedVyasa, Barbarika, Abhimanyu, Krishna, Ashwatthama, Dronacharya):

    CanonicalId|ThemedName|#RRGGBB|persona

- ThemedName: one word matching `^[A-Za-z][A-Za-z0-9]*$`, unique in the file,
  with no dash (copies are named `Name-1`).
- Colour: `#RRGGBB`, readable on dark terminals and on a white web page.
- Persona: at most 70 characters, one line, no `|`.

## Choosing a theme

Set `SABHA_THEME=<name>` in `sabha.conf`, or run `bin/sabha init --theme <name>`.
Available: mahabharat, avengers, hogwarts, middle-earth, plain.

## Adding your own

Copy `plain.theme` to `themes/<yourname>.theme`, change the names, colours and
personas, keep all 20 lines in order, then select it as above.

## Disclaimer

The avengers, hogwarts and middle-earth themes are fan themes. Character names
belong to their owners; claude-sabha is not affiliated with or endorsed by them.
