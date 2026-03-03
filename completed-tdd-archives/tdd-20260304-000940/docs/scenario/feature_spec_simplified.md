# Scenario: FeatureSpec structure simplified to name and dim only
- Given: FeatureSpec dataclass exists with multiple fields
- When: FeatureSpec is redefined
- Then: FeatureSpec contains only name (str) and dim (int) fields

## Test Steps

- Case 1 (happy path): FeatureSpec can be instantiated with name and dim
- Case 2 (edge case): FeatureSpec rejects initialization with dtype or description

## Status
- [x] Write scenario document
- [x] Write solid test according to document
- [x] Run test and watch it failing
- [x] Implement to make test pass
- [x] Run test and confirm it passed
- [x] Refactor implementation without breaking test
- [x] Run test and confirm still passing after refactor

**IMPORTANT**: Only update above status when a step is confirmed complete. Do not hallucinate.
