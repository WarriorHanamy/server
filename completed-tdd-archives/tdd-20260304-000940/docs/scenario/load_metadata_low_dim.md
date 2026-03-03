# Scenario: _load_metadata() parses low_dim format
- Given: _load_metadata() expects old metadata format with dtype/description
- When: _load_metadata() is updated to parse low_dim format
- Then: _load_metadata() correctly parses {'low_dim': [{'name': '...', 'dim': N}, ...]}

## Test Steps

- Case 1 (happy path): _load_metadata() parses valid low_dim format correctly
- Case 2 (edge case): _load_metadata() handles empty low_dim list gracefully

## Status
- [x] Write scenario document
- [x] Write solid test according to document
- [x] Run test and watch it failing
- [x] Implement to make test pass
- [x] Run test and confirm it passed
- [x] Refactor implementation without breaking test
- [x] Run test and confirm still passing after refactor

**IMPORTANT**: Only update above status when a step is confirmed complete. Do not hallucinate.
