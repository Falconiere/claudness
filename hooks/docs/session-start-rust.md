## Rust notes
- Rust tests must live in `tests/` dir — no inline `#[cfg(test)]`.
- No `#[allow(...)]` or `#[expect(...)]` in Rust — fix the warning, don't suppress it.
- Use `cargo nextest run` for tests; never plain `cargo test`.
