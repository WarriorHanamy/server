# Schema-Based Neural Inference Pipeline Design

## Overview

A schema-driven approach to ensure observation consistency between training (drone_racer) and deployment (vtol-interface).

**Core Principle**: Schema is model metadata, not configuration. It travels with the ONNX model to guarantee matching.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     drone_racer (Training)                      │
├─────────────────────────────────────────────────────────────────┤
│  Observation Config (free to iterate)                           │
│       ↓                                                         │
│  Training → checkpoint.pt                                       │
│       ↓                                                         │
│  export_onnx.py                                                 │
│       ├── policy.onnx                                           │
│       └── schema.yaml  (auto-generated: name + dim only)        │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼ Package to models/
┌─────────────────────────────────────────────────────────────────┐
│                   vtol-interface (Deployment)                   │
├─────────────────────────────────────────────────────────────────┤
│  1. Register feature functions in Registry                      │
│       ↓                                                         │
│  2. Load models/hover_v1/policy.onnx + schema.yaml              │
│       ↓                                                         │
│  3. Validate: all features registered + dimensions match        │
│       ↓                                                         │
│  4. Create Composer from schema                                 │
│       ↓                                                         │
│  5. Pipeline: obs = composer.compute(state) + last_action       │
└─────────────────────────────────────────────────────────────────┘
```

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

**No scale/clip**: Processing logic is encapsulated in registered feature functions.

---

## Responsibility Matrix

| Component            | Responsibility                                    |
| -------------------- | ------------------------------------------------- |
| **Schema**             | Declares required features + dimensions (contract) |
| **Feature Functions**  | Implement correct transforms, coordinate conversions |
| **Composer**           | Assembles features in declared order              |
| **Pipeline**           | Appends last_action, orchestrates inference       |

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
└── schema.yaml
       │
       ▼
┌──────────────────────────────┐
│ 1. Load schema.yaml          │
│ 2. Validate against registry │
│ 3. Create Composer           │
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
       ▼ composer.compute(state)
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
│               └── schema.yaml     # Schema file
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

### Deployment Config (vtol-interface)

```yaml
# pos_ctrl_config.yaml
model:
  path: "${oc.env:INFER_WORKSPACE}/src/neural_manager/neural_pos_ctrl/models/hover_v1/policy.onnx"
  schema_path: "${oc.env:INFER_WORKSPACE}/src/neural_manager/neural_pos_ctrl/models/hover_v1/schema.yaml"
  actor_type: "mlp"
  # ... other config
```

---

## Validation Checklist

Before model deployment:

- [ ] All feature names in schema are registered in `ObservationRegistry`
- [ ] Sum of feature dimensions + 4 (last_action) equals `total_dim`
- [ ] `total_dim` matches ONNX model input dimension
- [ ] Feature functions produce correct coordinate transforms (FLU body frame)

---

## Future Extensions

1. **Version Compatibility**: Schema versioning for backward compatibility
2. **Multiple Models**: Hot-swap models by loading different schema
3. **Feature Groups**: Group features for partial observation (e.g., critic-only features)
4. **Validation Report**: Generate detailed validation report on startup
