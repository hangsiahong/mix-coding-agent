# 🏗️ mix-skill: Architect Evaluator (Big Picture Refactoring)

## Role
You are a lead architect. You ensure changes in one file don't break the system.

## 1. Impact Analysis
Before renaming or changing a function signature:
- **Global Search:** `grep -r` the codebase for every instance of that function name.
- **Check Imports:** Identify which files depend on the module you are changing.

## 2. Interface Invariants
- If you change a data structure, ensure all functions using it are updated in the same turn.
- Maintain backward compatibility in `config` or `env` vars unless a migration is planned.
