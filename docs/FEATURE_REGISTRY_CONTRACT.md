# Feature Registry Contract Specification

## Overview

The `feature_registry.yaml` file defines the contract between the training-generated schema and deployment runtime. It maps each schema feature name to a canonical functional transform pipeline that constructs the observation vector from robot state data.

**Key Principles:**

1. **Registry is deployment-owned**: Versioned alongside inference code, not auto-generated
2. **Transforms are pure functions**: Each pipeline step references a registered transform
3. **Declarative composition**: Pipeline chains transforms without embedding logic
4. **Runtime augmentation**: Registry can specify context from runtime state (e.g., `last_action`)

---

## Registry Schema

### Top-Level Fields

| Field                | Type    | Required | Description |
| -------------------- | ------- | -------- | ----------- |
| `registry_version`   | integer | Yes      | Version for compatibility checks |
| `features`           | list    | Yes      | Ordered list of feature entries |

### Feature Entry Fields

| Field                | Type    | Required | Description |
| -------------------- | ------- | -------- | ----------- |
| `name`               | string  | Yes      | Feature name (must match schema) |
| `entrypoint`         | string  | Yes      | Dotted Python import path to feature function module |
| `pipeline`           | list    | Yes      | Ordered list of transform steps to build the feature |
| `description`        | string  | No       | Human-readable description of the feature |

### Pipeline Step Fields

Each item in the `pipeline` list represents one transform step with the following fields:

| Field                | Type    | Required | Description |
| -------------------- | ------- | -------- | ----------- |
| `transform`          | string  | Yes      | Name of registered transform (must exist in transform registry) |
| `inputs`             | list    | No       | RobotState keys consumed as positional arguments |
| `params`             | dict    | No       | Keyword parameters passed to the transform |
| `runtime_context`    | dict    | No       | Runtime-only context fields (e.g., action history) |

---

## Registry Format

```yaml
# feature_registry.yaml
registry_version: 1

features:
  # Example 1: Static feature with coordinate transforms
  - name: target_error
    entrypoint: neural_pos_ctrl.features.target_error
    description: "Position error vector in FLU body frame"
    pipeline:
      - transform: subtract_target
        inputs: [position_ned, target_position_ned]
      - transform: rotate_to_body
        params:
          frame: flu

  # Example 2: Feature with mathematical encoding
  - name: current_yaw_encoding
    entrypoint: neural_pos_ctrl.features.yaw_encoding
    description: "Sin/cos encoding of current yaw angle"
    pipeline:
      - transform: quat_to_yaw
        inputs: [orientation_quat]
      - transform: angle_to_sincos

  # Example 3: Feature with runtime augmentation
  - name: last_action
    entrypoint: neural_pos_ctrl.features.action_history
    description: "Previous action vector from controller history"
    pipeline:
      - transform: fetch_last_action
        runtime_context:
          buffer: action_history
      - transform: normalize_action
        params:
          scale: 1.0
```

---

## Transform Step Semantics

### Transform Execution Model

Each pipeline step is executed as a pure function with the following calling convention:

```
result = transform_name(*input_values, **params, **runtime_context)
```

Where:
- `input_values`: Values extracted from RobotState by `inputs` keys
- `params`: Static parameters defined in the registry step
- `runtime_context`: Dynamic values provided by the inference runtime (e.g., action history buffer)

### Input Resolution

The `inputs` field specifies RobotState keys to extract. For example:

```yaml
inputs: [position_ned, target_position_ned]
```

Resolves to:

```python
result = transform(robot_state["position_ned"], robot_state["target_position_ned"], **params)
```

### Runtime Context Resolution

The `runtime_context` field specifies keys to look up in the runtime context object. These are not in RobotState but are maintained by the inference pipeline:

```yaml
runtime_context:
  buffer: action_history
```

Resolves to:

```python
result = transform(context["action_history"], **params)
```

### Chaining Pipeline Steps

The output of each pipeline step becomes the first positional argument to the next step:

```yaml
pipeline:
  - transform: step1
    inputs: [field_a, field_b]
  - transform: step2
    params:
      param_x: 10
```

Executes as:

```python
temp = step1(robot_state["field_a"], robot_state["field_b"])
result = step2(temp, param_x=10)
```

---

## Canonical Transforms

### Core Mathematical Transforms

| Transform Name   | Inputs                          | Outputs        | Description |
| ---------------- | ------------------------------- | -------------- | ----------- |
| `add`            | scalar inputs                   | scalar         | Addition of all inputs |
| `subtract`       | [minuend, subtrahend]           | vector         | Element-wise subtraction |
| `multiply`       | scalar inputs                   | scalar         | Multiplication of all inputs |
| `divide`         | [dividend, divisor]             | vector         | Element-wise division |
| `normalize`      | vector                          | normalized vector | L2 normalization (optional scale param) |

### Coordinate Frame Transforms

| Transform Name   | Inputs                          | Outputs        | Description |
| ---------------- | ------------------------------- | -------------- | ----------- |
| `ned_to_frd`     | [quaternion, vector]            | 3D vector      | NED to FRD body frame rotation |
| `frd_to_flu`     | [vector]                        | 3D vector      | FRD to FLU frame conversion |
| `rotate_to_body` | [vector, quaternion]            | 3D vector      | Rotate vector by quaternion |
| `project_vector` | [vector, quaternion]            | 3D vector      | Project vector onto frame |

### Encoding Transforms

| Transform Name   | Inputs                          | Outputs        | Description |
| ---------------- | ------------------------------- | -------------- | ----------- |
| `quat_to_yaw`    | [quaternion]                    | scalar         | Extract yaw angle from quaternion |
| `angle_to_sincos`| [angle]                         | [sin, cos]     | Convert angle to sin/cos encoding |
| `one_hot`        | [index, num_classes]            | vector         | One-hot encoding of categorical index |

### Runtime Transforms

| Transform Name   | Inputs                          | Outputs        | Description |
| ---------------- | ------------------------------- | -------------- | ----------- |
| `fetch_last_action`| runtime_context: action_buffer | 4D vector      | Retrieve previous action from history |
| `concat_history`  | [history_array]                 | flattened vector| Concatenate history buffer |

### Utility Transforms

| Transform Name   | Inputs                          | Outputs        | Description |
| ---------------- | ------------------------------- | -------------- | ----------- |
| `passthrough`    | [field]                         | input value    | Identity transform (no-op) |
| `clip`           | [vector]                        | clipped vector | Clip values to bounds (params: min, max) |
| `scale`          | [vector]                        | scaled vector  | Multiply by scale factor (param: scale) |

---

## Validation Expectations

### Schema-Level Validation

The feature registry must be validated against the schema before model inference:

1. **Feature Coverage**: Every feature name in `schema.yaml` must have a corresponding entry in `feature_registry.yaml`
2. **Dimension Matching**: The output dimension of the last transform in each pipeline must match the feature's `dim` in the schema
3. **Total Dimension Check**: Sum of all feature dimensions must equal `schema.total_dim` (excluding `last_action` which is added by pipeline)

### Transform Existence Validation

For each transform step in each pipeline:

1. **Transform Registration**: The `transform` name must be registered in the transform registry (`_TRANSFORM_REGISTRY`)
2. **Entrypoint Resolution**: The `entrypoint` dotted path must resolve to an importable Python module
3. **Input Key Validity**: All keys in `inputs` must exist in the expected RobotState structure

### Parameter Validation

For each pipeline step:

1. **Required Parameters**: All parameters required by the transform function must be provided either in `params` or `runtime_context`
2. **Parameter Types**: Parameter values must match the expected types for the transform function
3. **Parameter Ranges**: Numeric parameters must be within valid ranges (e.g., scale factors > 0)

### Runtime Validation

During inference execution:

1. **RobotState Completeness**: All `inputs` keys must have non-null values in the current RobotState
2. **Context Availability**: All `runtime_context` keys must be available in the inference runtime
3. **Output Dimension**: The final pipeline output must match the expected feature dimension

---

## Example Registry Entries

### Static Feature: target_error

This example shows a feature constructed from static robot state with coordinate transforms:

```yaml
- name: target_error
  entrypoint: neural_pos_ctrl.features.target_error
  description: "Position error from target in FLU body frame"
  pipeline:
    - transform: subtract
      inputs: [position_ned, target_position_ned]
    - transform: rotate_to_body
      params:
        frame: flu
```

**Execution Flow:**
1. Extract `position_ned` and `target_position_ned` from RobotState
2. Compute error vector: `error = position_ned - target_position_ned`
3. Rotate error to FLU body frame using `orientation_quat`
4. Output: 3D error vector in FLU frame (matches schema `dim: 3`)

---

### Static Feature: gravity_projection

This example shows a feature computed from sensor data with projection:

```yaml
- name: gravity_projection
  entrypoint: neural_pos_ctrl.features.gravity_projection
  description: "Gravity vector projected into FLU body frame"
  pipeline:
    - transform: project_vector
      inputs: [orientation_quat]
      params:
        vector: [0, 0, 9.81]  # Gravity in NED frame
```

**Execution Flow:**
1. Extract `orientation_quat` from RobotState
2. Project gravity vector [0, 0, 9.81] into body frame
3. Output: 3D gravity direction in body frame (matches schema `dim: 3`)

---

### Static Feature: current_yaw_encoding

This example shows angular encoding using transforms:

```yaml
- name: current_yaw_encoding
  entrypoint: neural_pos_ctrl.features.yaw_encoding
  description: "Sin/cos encoding of current yaw angle"
  pipeline:
    - transform: quat_to_yaw
      inputs: [orientation_quat]
    - transform: angle_to_sincos
```

**Execution Flow:**
1. Extract `orientation_quat` from RobotState
2. Convert quaternion to yaw angle (scalar)
3. Encode yaw as [cos(yaw), sin(yaw)]
4. Output: 2D encoding vector (matches schema `dim: 2`)

---

### Runtime-Augmented Feature: last_action

This example shows a feature that requires runtime context (action history):

```yaml
- name: last_action
  entrypoint: neural_pos_ctrl.features.action_history
  description: "Previous action from controller history"
  pipeline:
    - transform: fetch_last_action
      runtime_context:
        buffer: action_history
```

**Execution Flow:**
1. Fetch the most recent action from runtime's action history buffer
2. Output: 4D action vector (matches schema `dim: 4`)

**Note:** The action history buffer is maintained by the inference runtime and is not part of the static RobotState.

---

### Complex Feature: target_pos_body

This example shows a feature combining multiple transforms:

```yaml
- name: target_pos_body
  entrypoint: neural_pos_ctrl.features.target_body
  description: "Target position expressed in FLU body frame"
  pipeline:
    - transform: subtract
      inputs: [target_position_ned, position_ned]
    - transform: rotate_to_body
      params:
        frame: flu
    - transform: scale
      params:
        scale: 1.0
```

**Execution Flow:**
1. Extract `target_position_ned` and `position_ned` from RobotState
2. Compute relative target: `relative = target_position_ned - position_ned`
3. Rotate relative position to FLU body frame
4. Apply scaling (identity in this case, could be normalization)
5. Output: 3D target position in body frame (matches schema `dim: 3`)

---

## Complete Example Registry

```yaml
# feature_registry.yaml for hover_v1 model
registry_version: 1

features:
  # 3D position error in FLU frame
  - name: target_error
    entrypoint: neural_pos_ctrl.features.target_error
    description: "Position error vector from target in FLU body frame"
    pipeline:
      - transform: subtract
        inputs: [position_ned, target_position_ned]
      - transform: rotate_to_body
        params:
          frame: flu

  # 3D gravity direction in FLU frame
  - name: gravity_projection
    entrypoint: neural_pos_ctrl.features.gravity_projection
    description: "Gravity vector projected into FLU body frame"
    pipeline:
      - transform: project_vector
        inputs: [orientation_quat]
        params:
          vector: [0, 0, 9.81]

  # 3D angular velocity in FLU frame
  - name: angular_velocity
    entrypoint: neural_pos_ctrl.features.angular_velocity
    description: "Angular velocity in FLU body frame"
    pipeline:
      - transform: frd_to_flu
        inputs: [angular_velocity_body]

  # 2D current yaw encoding
  - name: current_yaw_encoding
    entrypoint: neural_pos_ctrl.features.yaw_encoding
    description: "Sin/cos encoding of current yaw angle"
    pipeline:
      - transform: quat_to_yaw
        inputs: [orientation_quat]
      - transform: angle_to_sincos

  # 3D target position in body frame
  - name: target_pos_body
    entrypoint: neural_pos_ctrl.features.target_body
    description: "Target position expressed in FLU body frame"
    pipeline:
      - transform: subtract
        inputs: [target_position_ned, position_ned]
      - transform: rotate_to_body
        params:
          frame: flu

  # 2D target yaw encoding
  - name: target_yaw_encoding
    entrypoint: neural_pos_ctrl.features.target_yaw
    description: "Sin/cos encoding of target yaw angle"
    pipeline:
      - transform: angle_to_sincos
        inputs: [target_yaw]

  # 4D previous action (runtime augmented)
  - name: last_action
    entrypoint: neural_pos_ctrl.features.action_history
    description: "Previous action from controller history"
    pipeline:
      - transform: fetch_last_action
        runtime_context:
          buffer: action_history
```

---

## Integration with Schema

### Validation Pipeline

The following validation sequence occurs during model loading:

```
1. Load feature_registry.yaml
   ├─ Parse registry_version
   └─ Parse features list

2. For each feature in features list:
   ├─ Resolve entrypoint module (import check)
   ├─ For each pipeline step:
   │   ├─ Verify transform name in registry
   │   ├─ Validate inputs are valid RobotState keys
   │   └─ Validate params match transform signature
   └─ Compute output dimension from pipeline

3. Load schema.yaml
   ├─ Parse schema_version
   └─ Parse features list

4. Cross-validate registry against schema:
   ├─ All schema features exist in registry
   ├─ Registry output dims match schema dims
   └─ Sum of dims + 4 (last_action) == schema.total_dim

5. Load ONNX model
   ├─ Get input tensor dimension
   └─ Verify input dim == schema.total_dim
```

### Runtime Execution Pipeline

```
For each inference step:

1. Receive RobotState from sensors

2. For each feature in schema order:
   ├─ Get feature entry from registry
   ├─ Execute pipeline:
   │   For each pipeline step:
   │   ├─ Extract inputs from RobotState (or runtime context)
   │   ├─ Call transform(*inputs, **params, **runtime_context)
   │   └─ Pass result to next step
   └─ Collect final output (vector)

3. Concatenate all feature vectors in schema order

4. Append last_action from runtime context

5. Feed full observation to ONNX model
```

---

## Error Handling

### Registry Loading Errors

| Error Type                    | Cause                                    | Recovery                          |
| ----------------------------- | ---------------------------------------- | --------------------------------- |
| `FileNotFoundError`          | Registry file not found                  | Abort model loading               |
| `yaml.YAMLError`             | Invalid YAML syntax                      | Report parse error, abort         |
| `ValidationError`            | Missing required fields                  | Report missing field, abort       |
| `ImportError`                | Entrypoint module not found              | Report module path, abort         |

### Transform Resolution Errors

| Error Type                    | Cause                                    | Recovery                          |
| ----------------------------- | ---------------------------------------- | --------------------------------- |
| `KeyError`                    | Transform name not registered            | List available transforms, abort  |
| `RuntimeError`                | RobotState key missing                   | Report missing key, abort         |
| `TypeError`                   | Parameter type mismatch                  | Report parameter name, abort      |

### Runtime Execution Errors

| Error Type                    | Cause                                    | Recovery                          |
| ----------------------------- | ---------------------------------------- | --------------------------------- |
| `KeyError`                    | RobotState key has null value            | Skip inference, request new state |
| `ValueError`                  | Output dimension mismatch                | Log dimension error, abort        |

---

## Best Practices

### Registry Design Guidelines

1. **Keep pipelines simple**: Prefer 2-3 transform steps per feature
2. **Use existing transforms**: Check transform registry before creating new ones
3. **Validate offline**: Run validation tests during development, not at runtime
4. **Document transforms**: Add `description` field for non-obvious features

### Transform Implementation Guidelines

1. **Pure functions**: Transforms should not modify inputs or have side effects
2. **Type hints**: Use numpy arrays with explicit dimensions for inputs/outputs
3. **Error handling**: Validate input types and dimensions in transform functions
4. **Register all transforms**: Use `@register_transform` decorator

### Versioning Guidelines

1. **Bump registry_version** on breaking changes (e.g., new required fields)
2. **Backward compatibility**: Support older registry versions for at least one release
3. **Feature deprecation**: Mark deprecated features with comment before removal

---

## References

- **Schema Design**: See `SCHEMA_DESIGN.md` for architecture overview
- **Transform Registry**: See `vtol-interface/src/neural_manager/neural_inference/transforms/transform_registry.py`
- **Transform Implementations**: See `vtol-interface/src/neural_manager/neural_inference/transforms/*.py`
- **Schema Format**: See `vtol-interface/src/neural_manager/neural_inference/config/model_schema.yaml`
