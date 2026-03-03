# Scenario: Remove dtype and description references
- Given: Code references dtype and description fields in multiple places
- When: All dtype and description references are removed
- Then: No code references dtype or description fields

## Test Steps

- Case 1 (happy path): feature_provider_base.py compiles without dtype/description references
- Case 2 (edge case): model_schema.py compiles without dtype/description references

## Status
- [x] Write scenario document
- [x] Write solid test according to document
- [x] Run test and watch it failing
- [x] Implement to make test pass
- [x] Run test and confirm it passed
- [x] Refactor implementation without breaking test
- [x] Run test and confirm still passing after refactor

**IMPORTANT**: Only update above status when a step is confirmed complete. Do not hallucinate.
