# Documentation standards

- **Step docs** live at `docs/steps/<concern>/<step>.md` and keep to three sections:
  `## Why`, `## What the script does`, `## Verify`. Factual and brief.
- **Clear English, not AI prose.** Write tight, concrete sentences. AI may tighten
  grammar or tone, but do not paste raw AI output: read it and rewrite it so it stays
  clear and to the point.
- **CLI-first.** Document a console step only when the action genuinely has no CLI
  (root MFA, the IAM billing-access toggle) or when it handles a secret the baseline
  will not touch (console password, MFA enrolment). Anything else scriptable is
  documented as its CLI command.
- **No em-dashes.** Use commas, colons, parentheses, or separate sentences.
- **Links as `[text](url)`.** Never a bare URL in prose.
- **No inline `#` comments in copy-paste code blocks.** Put annotations in the
  surrounding prose; keep `<PLACEHOLDER>` tokens in the commands.
- **`docs/configuration.md` is the single source of truth** for every config
  setting: default, whether it is required, whether it is updatable, and what it is
  used for. Reference it rather than restating a setting's behaviour elsewhere.
