# Schema-Based Neural Inference Pipeline Design

## Overview

A schema-driven approach to ensure observation consistency between training (drone_racer) and deployment (vtol-interface).

**Core Principle**: Schema is model metadata, not configuration. It travels with the ONNX model to guarantee matching.

- `schema.yaml` originates from training. The export step that produces
  `policy.onnx` also serializes the observation contract directly from the
  IsaacLab config so deployment never edits this file.
- `feature_registry.yaml` lives in the deployment repo and is loaded before
  inference. It declares the canonical feature functions that may satisfy the
  schema.
- Observation assembly in deployment is a functional transform pipeline defined
  by registry entries. The composer chains pure transforms to build each
  feature vector and then appends `last_action`.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                       drone_racer (Training)                        │
├────────────────────────────────────────────────────────────────────┤
│  Observation Config (iterates freely)                               │
│       ↓                                                             │
│  Training → checkpoint.pt                                           │
│       ↓                                                             │
│  export_onnx.py / schema_writer.py                                  │
│       ├── policy.onnx                                               │
│       └── schema.yaml  (auto-generated from training config)        │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼ Package artifacts to models/
┌────────────────────────────────────────────────────────────────────┐
│                     vtol-interface (Deployment)                     │
├────────────────────────────────────────────────────────────────────┤
│  feature_registry.yaml (versioned in repo)                          │
│       ↓ load registry + transforms                                 │
│  Load policy.onnx + schema.yaml                                    │
│       ↓ validate(schema ↔ registry ↔ ONNX input)                   │
│  Build functional pipeline from registry entries                   │
│       ↓                                                             │
│  obs = pipeline.compute(state) + last_action                       │
└────────────────────────────────────────────────────────────────────┘
```

The architecture explicitly separates artifact ownership: training emits the
schema, while deployment maintains the feature registry and transform
implementations.

---

## Schema Format

### Minimal Design

Schema declares **what** features are needed, not **how** to process them.

```yaml
# models/hover_v1/schema.yaml
schema_version: "1.0"
model_name: "hover_v1"
total_dim: 13

features:
  - name: target_error
    dim: 3
  - name: gravity_projection
    dim: 3
  - name: angular_velocity
    dim: 3
# Note: last_action (4D) appended by pipeline at runtime
```

### Schema Fields

| Field          | Type     | Description                          |
| -------------- | -------- | ------------------------------------ |
| `schema_version` | string   | Schema format version (e.g., "1.0")  |
| `model_name`     | string   | Model identifier                     |
| `total_dim`      | int      | Total observation dim (including last_action) |
| `features`       | list     | List of feature definitions          |

### Feature Fields

| Field   | Type   | Description                    |
| ------- | ------ | ------------------------------ |
| `name`    | string | Feature name (must match registry) |
| `dim`     | int    | Feature dimension              |

## Feature Registry Format

`feature_registry.yaml` is deployment-owned metadata. It is versioned alongside
the inference code, loaded before any model executes, and maps schema feature
names to canonical functional pipelines.

```yaml
# models/hover_v1/feature_registry.yaml
registry_version: 1
features:
  - name: target_error
    entrypoint: neural_pos_ctrl.features.target_error
    pipeline:
      - transform: subtract_target
        inputs: [position_ned, target_position_ned]
      - transform: rotate_to_body
        frame: flu
  - name: gravity_projection
    entrypoint: neural_pos_ctrl.features.gravity_projection
    pipeline:
      - transform: project_vector
        inputs: [orientation_quat]
  - name: angular_velocity
    entrypoint: neural_pos_ctrl.features.angular_velocity
    pipeline:
      - transform: body_frame_passthrough
        inputs: [angular_velocity_body]
```

### Registry Fields

| Field             | Type   | Description |
| ----------------- | ------ | ----------- |
| `registry_version`| int    | Version for compatibility checks |
| `features`        | list   | Entries keyed by schema `name` |
| `entrypoint`      | string | Dotted import path to Python function implementing transforms |
| `pipeline`        | list   | Ordered functional transforms applied to build the feature |
| `inputs`          | list   | RobotState keys consumed by a transform |

Each pipeline step is a pure function. The composer loads these definitions,
creates the functional graph, and caches it so that observation assembly is only
orchestrated, never reinvented, inside deployment.

**No scale/clip**: Processing logic is encapsulated in registered feature functions.

---

## Responsibility Matrix

| Component                        | Responsibility |
| -------------------------------- | ------------- |
| **schema.yaml (training)**       | Declares required features + dims; generated from observation config |
| **feature_registry.yaml (deploy)** | Lists allowed features + entrypoints; stores transform sequences for deployment |
| **Feature Functions**            | Implement pure transforms referenced by registry entrypoints |
| **Functional Pipeline**          | Ordered composition assembling feature vectors from RobotState |
| **Composer**                     | Aligns schema order, executes pipelines, then appends `last_action` |

## Functional Composition Pipeline

Observation assembly in deployment never mutates the schema. Instead it steps
through a deterministic functional pipeline:

1. Load `feature_registry.yaml` and import the declared transform entrypoints.
2. Build a directed acyclic graph where each node is a pure transform function
   (e.g., subtract target, rotate frame, normalize angle).
3. Execute transforms in order to materialize each feature vector, stitch those
   vectors following the schema order, and finally append `last_action`.

```
RobotState
   │
   ├─ subtract_target ─┐
   │                   ▼
   └─ rotate_to_body → target_error (3D)
                               │
                               ├─ concat → Observation (N)
                               ▼
                         gravity_projection (3D)
```

Because every step is purely functional, the registry can be validated offline
and replayed deterministically at runtime.

---

## Data Flow

### Training Side (drone_racer)

```
Observation Config (IsaacLab)
       │
       ▼
┌──────────────────────────────┐
│ ObsTerm definitions:         │
│   to_target_b = ObsTerm(     │
│     func=mdp.err_p_b, ...)   │
│   grav_dir_b = ObsTerm(      │
│     func=mdp.body_proj_grav) │
│   ang_vel_b = ObsTerm(       │
│     func=mdp.base_ang_vel)   │
└──────────────────────────────┘
       │
       ▼ training
checkpoint.pt
       │
       ▼ export_onnx.py
┌──────────────────────────────┐
│ Generate schema from config: │
│   - Map obs names to feature │
│     names (target_error, etc)│
│   - Extract dimensions       │
│   - Write schema.yaml        │
└──────────────────────────────┘
       │
       ▼
models/hover_v1/
├── policy.onnx
└── schema.yaml
```

### Deployment Side (vtol-interface)

```
models/hover_v1/
├── policy.onnx
├── schema.yaml
└── feature_registry.yaml
       │
       ▼
┌──────────────────────────────┐
│ 1. Load feature_registry.yaml│
│ 2. Import transforms         │
│ 3. Load schema.yaml          │
│ 4. Validate (schema ↔ registry ↔ ONNX) │
│ 5. Create functional pipelines│
└──────────────────────────────┘
       │
       ▼ Runtime
┌──────────────────────────────┐
│ RobotState (from PX4)        │
│   - position_ned             │
│   - velocity_ned             │
│   - orientation_quat         │
│   - angular_velocity_body    │
│   - target_position_ned      │
│   - target_yaw               │
└──────────────────────────────┘
       │
       ▼ functional pipeline
┌──────────────────────────────┐
│ Observation Vector (9D)      │
│   [target_error (3),         │
│    gravity_proj (3),         │
│    ang_vel (3)]              │
└──────────────────────────────┘
       │
       ▼ + last_action (4D)
┌──────────────────────────────┐
│ Full Observation (13D)       │
└──────────────────────────────┘
       │
       ▼ policy_actor(observation)
Action (4D)
```

---

## Component Interfaces

### 1. ObservationSchema (Python)

```python
@dataclass
class FeatureSpec:
    """Single feature specification."""
    name: str
    dim: int


@dataclass
class ObservationSchema:
    """Schema definition for observation space."""
    schema_version: str
    model_name: str
    total_dim: int
    features: List[FeatureSpec]

    @classmethod
    def from_yaml(cls, path: Path) -> "ObservationSchema":
        """Load schema from YAML file."""
        ...

    def to_yaml(self, path: Path) -> None:
        """Save schema to YAML file."""
        ...
```

### 2. SchemaValidator

```python
class SchemaValidator:
    """Validates schema against registry and model."""

    @staticmethod
    def validate(
        schema: ObservationSchema,
        registry: ObservationRegistry,
        onnx_input_dim: int
    ) -> ValidationResult:
        """
        Validate schema completeness.

        Checks:
        1. All feature names are registered
        2. Computed dimension matches schema.total_dim
        3. Schema dimension matches ONNX input dimension

        Returns:
            ValidationResult with success status and error messages
        """
        ...
```

### 3. ObservationComposer (Updated)

```python
class ObservationComposer:
    """Config-driven observation composer."""

    def __init__(self, schema: ObservationSchema, registry: ObservationRegistry):
        """
        Initialize composer with schema and registry.

        Args:
            schema: ObservationSchema defining required features
            registry: ObservationRegistry with feature functions
        """
        self._schema = schema
        self._pipeline = self._build_pipeline(schema, registry)

    def compute(self, state: RobotState) -> np.ndarray:
        """Compute observation vector from RobotState."""
        ...

    def get_obs_dim(self) -> int:
        """Return total observation dimension (excluding last_action)."""
        ...
```

### 4. Schema Generator (drone_racer)

```python
def generate_schema_from_env_cfg(
    env_cfg: ManagerBasedRLEnvCfg,
    model_name: str,
    feature_name_map: Dict[str, str]
) -> ObservationSchema:
    """
    Generate schema from IsaacLab environment config.

    Args:
        env_cfg: Environment configuration with observation terms
        model_name: Name for the model
        feature_name_map: Mapping from training obs names to deployment feature names
            e.g., {"to_target_b": "target_error",
                   "grav_dir_b": "gravity_projection",
                   "ang_vel_b": "angular_velocity"}

    Returns:
        ObservationSchema instance
    """
    ...
```

---

## Feature Name Mapping

Training (drone_racer) → Deployment (vtol-interface) naming convention:

| Training Name       | Deployment Name        | Dim | Description                    |
| ------------------- | ---------------------- | --- | ------------------------------ |
| `to_target_b`         | `target_error`           | 3   | Position error in body frame   |
| `grav_dir_b`          | `gravity_projection`     | 3   | Gravity direction in body frame|
| `ang_vel_b`           | `angular_velocity`       | 3   | Angular velocity in body frame |
| `lin_vel_b`           | `body_velocity`          | 3   | Linear velocity in body frame  |
| `yaw_dir`             | `yaw_encoding`           | 2   | Current yaw [cos, sin]         |
| `target_yaw_dir`      | `target_yaw_encoding`    | 2   | Target yaw [cos, sin]          |
| `last_action`         | (handled by pipeline)    | 4   | Previous action (runtime)      |

---

## Directory Structure

```
server/
├── drone_racer/
│   ├── tools/
│   │   ├── export_onnx.py          # Existing, will be modified
│   │   └── schema_generator.py     # NEW: Generate schema from env cfg
│   └── ...
│
├── vtol-interface/
│   └── src/neural_manager/neural_pos_ctrl/
│       ├── infer_utils/
│       │   ├── observation/
│       │   │   ├── schema.py       # Updated: Simplified schema
│       │   │   ├── features.py     # Existing: Feature functions
│       │   │   ├── registry.py     # Existing: Feature registry
│       │   │   ├── composer.py     # Updated: Schema-driven composer
│       │   │   └── validator.py    # NEW: Schema validation
│       │   └── inference_pipeline.py  # Updated: Use schema
│       └── models/
│           └── hover_v1/
│               ├── policy.onnx     # Model file
│               ├── schema.yaml     # Output of training export
│               └── feature_registry.yaml  # Deployment-owned registry
│
└── SCHEMA_DESIGN.md                # This document
```

---

## Configuration Example

### Training Config (drone_racer)

```python
# vtol_hover_env_cfg.py
class ObservationsCfg:
    @configclass
    class LowDimCfg(ObsGroup):
        history_length = 1

        to_target_b = ObsTerm(func=mdp.err_p_b, ...)
        grav_dir_b = ObsTerm(func=mdp.body_projected_gravity_b, ...)
        ang_vel_b = ObsTerm(func=mdp.base_ang_vel, ...)
        last_action = ObsTerm(func=mdp.last_action, ...)

    low_dim: LowDimCfg = LowDimCfg()
```

### Generated Schema

```yaml
# models/hover_v1/schema.yaml
schema_version: "1.0"
model_name: "hover_v1"
total_dim: 13

features:
  - name: target_error
    dim: 3
  - name: gravity_projection
    dim: 3
  - name: angular_velocity
    dim: 3
```

### Feature Registry (Deployment)

```yaml
# models/hover_v1/feature_registry.yaml
registry_version: 1
features:
  - name: target_error
    entrypoint: neural_pos_ctrl.features.target_error
    pipeline:
      - transform: subtract_target
        inputs: [position_ned, target_position_ned]
      - transform: rotate_to_body
        frame: flu
  - name: gravity_projection
    entrypoint: neural_pos_ctrl.features.gravity_projection
    pipeline:
      - transform: project_vector
        inputs: [orientation_quat]
  - name: angular_velocity
    entrypoint: neural_pos_ctrl.features.angular_velocity
    pipeline:
      - transform: body_frame_passthrough
        inputs: [angular_velocity_body]
```

### Deployment Config (vtol-interface)

```yaml
# pos_ctrl_config.yaml
model:
  path: "${oc.env:INFER_WORKSPACE}/src/neural_manager/neural_pos_ctrl/models/hover_v1/policy.onnx"
  schema_path: "${oc.env:INFER_WORKSPACE}/src/neural_manager/neural_pos_ctrl/models/hover_v1/schema.yaml"
  feature_registry_path: "${oc.env:INFER_WORKSPACE}/src/neural_manager/neural_pos_ctrl/models/hover_v1/feature_registry.yaml"
  actor_type: "mlp"
  # ... other config
```

---

## Validation Checklist

Before model deployment:

- [ ] All feature names in schema are registered in `ObservationRegistry`
- [ ] Sum of feature dimensions + 4 (last_action) equals `total_dim`
- [ ] `total_dim` matches ONNX model input dimension
- [ ] `feature_registry.yaml` exists for the model and lists every schema
      feature with a valid functional pipeline definition
- [ ] Registry entrypoints resolve to pure functions and import without side
      effects
- [ ] Feature functions produce correct coordinate transforms (FLU body frame)

---

## Future Extensions

1. **Version Compatibility**: Schema versioning for backward compatibility
2. **Multiple Models**: Hot-swap models by loading different schema
3. **Feature Groups**: Group features for partial observation (e.g., critic-only features)
4. **Validation Report**: Generate detailed validation report on startup
