# tooling/

Helper scripts that hooks and skills call into.

## Required environment variables

| Variable             | Purpose                                  |
|----------------------|------------------------------------------|
| `CONTEXT7_API_KEY`   | Authenticates `context7/search.sh`       |
| `EXA_API_KEY`        | Authenticates `exa-search/search.sh`     |

Export in your shell rc (`~/.config/fish/config.fish` or `~/.zshrc`) or load
from a secret manager (`pass`, `1password-cli`, `keyring`). Do **not** commit
a `.env` file — scripts read from `$ENV` directly.

## Tests

Run all tooling tests:

```bash
bats tooling/__tests__
```
