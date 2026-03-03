# Scenario: Parse revision name to extract timestamp
- Given: A revision directory name in format {task_name}-{timestamp}-{hash}
- When: Calling RevisionDiscoverer._parse_revision_name(revision_dir_name)
- Then: Returns a datetime object representing the timestamp

## Test Steps

- Case 1 (standard format): Valid format with timestamp, extract correctly
- Case 2 (invalid format): Missing timestamp part, return None
- Case 3 (malformed timestamp): Timestamp not in expected format, return None

## Status
- [x] Write scenario document
- [x] Write solid test according to document
- [x] Run test and watch it failing
- [x] Implement to make test pass
- [x] Run test and confirm it passed
- [x] Refactor implementation without breaking test
- [x] Run test and confirm still passing after refactor
