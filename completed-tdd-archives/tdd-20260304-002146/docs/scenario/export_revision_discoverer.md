# Scenario: Export RevisionDiscoverer from features module
- Given: RevisionDiscoverer class is implemented in revision_discoverer.py
- When: Importing from features module
- Then: RevisionDiscoverer is available in __all__ exports

## Test Steps

- Case 1 (import from features): Can import RevisionDiscoverer directly from features module
- Case 2 (__all__ contains name): RevisionDiscoverer is listed in __all__

## Status
- [x] Write scenario document
- [x] Write solid test according to document
- [x] Run test and watch it failing
- [x] Implement to make test pass
- [x] Run test and confirm it passed
- [x] Refactor implementation without breaking test
- [x] Run test and confirm still passing after refactor
