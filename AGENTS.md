# MoonCedar — Agent Guide

A [MoonBit](https://docs.moonbitlang.com) project implementing the [Cedar](https://www.cedarpolicy.com) policy engine.

## Project Structure

- Each sub-package directory (`ast/`, `parser/`, `evaluator/`) has a `moon.pkg` file listing its dependencies. Each package has blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in `_wbtest.mbt`).

- The module root has `moon.mod` with module metadata and external dependencies.

- Dependency chain: `ast` (no internal deps) → `parser` (depends on `ast`), `evaluator` (depends on `ast`) → root `mooncedar` (re-exports all three).

## Coding Style

- Prefer MoonBit idiomatic patterns: use `for match` style over `while`/`loop` for `ArrayView`/`StringView` iteration.
- Keep parser code functional with `continue`/`break` in `for` expressions, avoiding imperative mutable accumulator loops.
- Follow the existing project conventions: `@ast.` prefix for cross-package imports, `pub(all)` for public API, record update `{ ..self, field: value }` for builder methods.
- Use `guard ... else { raise ... }` for early-exit validation instead of nested `if`/`match`.
- MoonBit code is organized in block style separated by `///|`. Block order is irrelevant; process block by block independently during refactoring.
- Keep deprecated blocks in a `deprecated.mbt` file in each directory.

## Tooling

Run these steps in order before committing (mirrors CI):

1. **`moon check --deny-warn`** — type-check and lint; fail on warnings.
2. **`moon fmt`** — format all source files. CI runs `moon fmt --check`; ensure
   no diff locally first.
3. **`moon info`** — regenerate `.mbti` interface files. CI runs
   `git diff --exit-code` after `moon info`; if `.mbti` files changed, commit
   them. If nothing changed, the change has no visible API impact (typically a
   safe refactoring).
4. **`moon test`** — run all tests. When snapshot outputs change intentionally,
   run `moon test --update` to refresh them and commit the updated snapshots.

- `moon coverage analyze > uncovered.log` — find code not covered by tests.

**Testing conventions:**
- Prefer `inspect`-based snapshot tests. Run `moon test --update` to generate expected output, then verify with `moon test`.
- Use `assert_eq!` in loops where each snapshot may vary.

## Checkpoint Maintenance

After completing a new feature, bug fix, or significant refactor, update `checkpoint.md`:

- New/modified files in the project structure section
- Updated test counts and pass/fail status
- Any newly completed or newly pending items
- Keep the "待实现" (TODO) section current
