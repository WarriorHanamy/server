# Scenario: Discover latest revision by timestamp
- Given: A artifacts_root directory with policies/<task>/ subdirectory containing multiple revision directories
- When: Calling RevisionDiscoverer.discover_latest(artifacts_root, task)
- Then: Returns the path to the revision directory with the latest timestamp

## Test Steps

- Case 1 (happy path): Multiple valid revisions exist, return the one with latest timestamp
- Case 2 (no valid revisions): Task directory exists but no valid revisions, return None
- Case 3 (empty task directory): Task directory is empty, return None
- Case 4 (task directory missing): Task directory does not exist, return None
- Case 5 (single valid revision): Only one valid revision exists, return it
- Case 6 (some invalid revisions): Mix of valid and invalid revisions, filter correctly and return latest valid

## Status
- [x] Write scenario document
- [x] Write solid test according to document
- [x] Run test and watch it failing
- [x] Implement to make test pass
- [x] Run test and confirm it passed
- [x] Refactor implementation without breaking test
- [x] Run test and confirm still passing after refactor
