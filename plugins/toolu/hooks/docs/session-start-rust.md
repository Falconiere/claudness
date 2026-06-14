## Rust notes
- Rust tests live in `tests/` — no inline `#[cfg(test)]`.
- No `#[allow(...)]`/`#[expect(...)]` — fix the warning, don't suppress.
- Use `cargo nextest run`; never plain `cargo test`.
