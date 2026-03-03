# Scenario: Validate revision directory contents
- Given: A revision directory path
- When: Calling RevisionDiscoverer._validate_revision(revision_path)
- Then: Returns True only if both model.onnx and observations_metadata.yaml exist

## Test Steps

- Case 1 (valid revision): Both files present, return True
- Case 2 (missing model): Only observations_metadata.yaml exists, return False
- Case 3 (missing metadata): Only model.onnx exists, return False
- Case 4 (both missing): Neither file exists, return False
- Case 5 (extra files present): Both required files plus extra files, return True

## Status
- [x] Write scenario document
- [x] Write solid test according to document
- [x] Run test and watch it failing
- [x] Implement to make test pass
- [x] Run test and confirm it passed
- [x] Refactor implementation without breaking test
- [x] Run test and confirm still passing after refactor
