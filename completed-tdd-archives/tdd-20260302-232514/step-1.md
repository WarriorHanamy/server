# Step 1 - Understand Intent

## Functional Requirements

### FR-1: Scan Policies Task Directory
Scan the policies/<task>/ directory to discover all revision candidate directories.
The discovery should work with a root directory path that can be outside the repository
(e.g., /shared/artifacts).

### FR-2: Parse Revision Naming Convention
Parse revision directory names following the commit-task-timestamp-hash format
into sortable fields (commit, task, timestamp, hash). The timestamp should be
converted to a datetime object for comparison.

### FR-3: Filter Valid Revisions
Filter revision candidates to only include those that have both required files:
- model.onnx (the ONNX model file)
- observations_metadata.yaml (the observations metadata file)

Candidates missing either file should be considered incomplete and rejected.

### FR-4: Select Newest Valid Revision
Among all valid revisions for a given task, select the one with the highest
UTC timestamp. If no valid revisions exist, raise an appropriate error.

## Assumptions

- The root directory path is provided as a Path object (following project conventions)
- The task name is a string (e.g., 'vtol_hover', 'vtol_nav')
- Revision directories follow the exact naming convention defined in revision.py
- Timestamps are always in UTC format (ending with 'Z')
- When multiple revisions have the same timestamp, selection behavior is undefined
  (accepting any of them is acceptable for this implementation)
- The discovery module should be deployed-side code, not inside common_root_dir
