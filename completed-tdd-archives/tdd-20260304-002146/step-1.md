# Step 1 - Understand Intent

## Functional Requirements

### FR-1: Discover latest revision by timestamp
`RevisionDiscoverer.discover_latest(artifacts_root, task)` should scan the directory
`<artifacts_root>/policies/<task>/`, find all valid revision subdirectories, sort them
by timestamp (extracted from directory name) in descending order, and return the path
to the latest revision directory. Returns None if no valid revisions are found.

### FR-2: Parse revision name to extract timestamp
`RevisionDiscoverer._parse_revision_name(revision_dir_name)` should extract the timestamp
from a revision directory name in the format `{task_name}-{timestamp}-{hash}` and return
a datetime object for sorting purposes.

### FR-3: Validate revision directory contents
`RevisionDiscoverer._validate_revision(revision_path)` should check that a revision
directory contains both required files: `model.onnx` and `observations_metadata.yaml`.
Returns True if both files exist, False otherwise.

### FR-4: Export RevisionDiscoverer from features module
RevisionDiscoverer should be exported from `features/__init__.py` to make it easily
importable.

## Assumptions

- Revision directory format is `{task_name}-{timestamp}-{hash}` where timestamp is in ISO 8601
  format (e.g., `20260303T110451Z`)
- The artifacts_root parameter is the base directory containing `policies/` subdirectory
- If the task directory does not exist, should return None (no valid revisions found)
- If task directory exists but contains no valid revisions, should return None
- Timestamp extraction should be robust enough to handle the expected format
- Validation is strict - both files must be present, not just one
