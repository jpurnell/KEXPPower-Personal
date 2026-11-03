---
paths:
  - "Sources/**/*.swift"
  - "Tests/**/*.swift"
---
# Swift Development Rules

Follow the coding standards in `development-guidelines/rules/coding_rules.md`.

## Mandatory

- No force unwraps, no `try!`, no force casts
- Guard clauses for validation, early returns over nesting
- Division safety: check for zero before dividing
- Swift 6 strict concurrency compliance
- All public APIs need DocC comments (see `development-guidelines/rules/docc_guidelines.md`)

## Testing (TDD)

Follow `development-guidelines/rules/test_driven_development.md`:
- Write failing tests BEFORE implementation
- Test golden path, edge cases, invalid inputs
- Use deterministic test data (no random values)
- Floating point: use accuracy-based assertions, not exact equality

And `development-guidelines/rules/correct_answers.md` for what those tests must claim:
- Every assertion must be able to fail for the reason its test is named for
- Expected values come from a closed form, enumeration, or published reference — never
  from the code's own output
- Tolerances are measured from observed worst cases, never widened to make a run pass
- Optional features are tested by comparison against the same run with them disabled
- Anything that generates its own inputs needs a seeded generator, not only fixtures