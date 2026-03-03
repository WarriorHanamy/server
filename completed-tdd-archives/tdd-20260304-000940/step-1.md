# Step 1 - Understand Intent

## Functional Requirements

### FR-1: Simplify FeatureSpec dataclass structure
The FeatureSpec dataclass should contain only two fields:
- name: str - the feature name
- dim: int - the feature dimension

All other fields (dtype, description) must be removed.

### FR-2: Remove dtype and description references
All code references to dtype and description fields must be removed from:
- FeatureSpec class definition
- FeatureValidationResult (expected_dim/actual_dim should remain)
- _load_metadata() parsing logic
- Any other code that uses these fields

### FR-3: Update _load_metadata() to parse low_dim format
The _load_metadata() method in FeatureProviderBase must parse metadata in the format:
```python
{'low_dim': [{'name': '...', 'dim': N}, ...]}
```
instead of the current format with dtype and description fields.

## Assumptions

- The low_dim format is used for training exports and is the desired metadata format
- FeatureValidationResult's expected_dim and actual_dim fields are still needed for validation reporting and should NOT be removed
- Both FeatureSpec definitions (feature_provider_base.py and model_schema.py) need to be updated consistently
- The frozen=True parameter in model_schema.py's FeatureSpec should be retained
