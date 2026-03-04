# Agent Operating Profile

## Submodule Testing

This repo contains submodules `vtol-interface` and `drone_racer`. 
- Never run `pytest` or `ruff` at the repository root.
- Always navigate into submodules before running tests or linting.

Examples:
- `cd vtol-interface && ./agent_bins/python -m pytest`
- `cd drone_racer && ./agent_bins/python -m ruff check`
