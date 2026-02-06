This document trains GitHub Copilot to understand and correctly autocomplete the Pi‑5 Installer Ecosystem.  
Copilot should treat this file as the authoritative reference for patterns, structure, vocabulary, and defensive logic.

---

# 1. **High‑Level Architecture Overview**

The installer ecosystem is built around these core components:

## **A. Container Wrapper**
- Detects host OS, architecture, and runtime environment  
- Ensures reproducible execution across x86, ARM, and containerized hosts  
- Provides a universal entrypoint for all installer workflows  

## **B. Host Compatibility Detection**
- Determines whether the host can run the installer natively  
- Falls back to container mode when required  
- Enforces guardrails to prevent unsupported execution  

## **C. Profile‑Driven Installer**
Profiles define installation behavior. Examples:

- `pi5` — native Raspberry Pi 5 installation  
- `container` — containerized execution  
- `host` — x86 host bootstrap mode  

Each profile has:

- its own module  
- its own guardrails  
- its own diagnostics  
- its own logging patterns  

## **D. Diagnostics Module**
- Runs pre‑flight checks  
- Validates hardware, OS, dependencies, and environment  
- Provides actionable error messages  
- Never silently fails  

## **E. Plugin Architecture**
- Allows contributors to add new modules without modifying core logic  
- Plugins must be self‑contained, defensive, and profile‑aware  

---

# 2. **Core Principles Copilot Must Follow**

Copilot should always assume:

- Scripts must be **modular**, not monolithic  
- Every function must be **defensive**  
- All logic must be **cross‑architecture safe**  
- Error handling is **mandatory**  
- Logging must be **explicit and human‑readable**  
- Contributors must be able to understand the script without tribal knowledge  

Copilot should prefer:

- small, composable functions  
- explicit checks  
- predictable exit paths  
- verbose logging  
- profile‑aware branching  
- container‑safe behavior  

---

# 3. **Vocabulary Copilot Must Use**

Copilot should use the project’s domain‑specific terms:

- container wrapper  
- host compatibility detection  
- profile‑driven installer  
- diagnostics module  
- plugin architecture  
- RPi5 hardware matrix  
- defensive guardrails  
- universal deployment path  
- cross‑architecture execution  
- bootstrap phase  
- phase‑2 installer logic  
- containerized execution mode  

Using this vocabulary ensures consistency across modules and commit messages.

---

# 4. **Bash Patterns Copilot Should Prefer**

## **A. Standard Script Header**
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

## **B. Logging Helpers**
```bash
log_info()  { printf "[INFO] %s\n" "$1"; }
log_warn()  { printf "[WARN] %s\n" "$1"; }
log_error() { printf "[ERROR] %s\n" "$1" >&2; }
```

## **C. Defensive Checks**
```bash
if [[ -z "${INSTALL_PROFILE:-}" ]]; then
    log_error "INSTALL_PROFILE is required"
    exit 1
fi
```

## **D. Guardrails for External Tools**
```bash
if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but missing"
    exit 1
fi
```

## **E. Modular Functions**
```bash
detect_architecture() {
    uname -m
}
```

## **F. Profile‑Aware Branching**
```bash
case "$INSTALL_PROFILE" in
    pi5) run_pi5_profile ;;
    container) run_container_profile ;;
    host) run_host_profile ;;
    *) log_error "Unknown profile: $INSTALL_PROFILE"; exit 1 ;;
esac
```

---

# 5. **Python Patterns Copilot Should Prefer**

## **A. Typed Functions**
```python
def load_profile(path: str) -> dict:
```

## **B. Explicit Error Handling**
```python
if not os.path.exists(path):
    raise FileNotFoundError(f"Profile not found: {path}")
```

## **C. No Silent Failures**
```python
if value is None:
    raise ValueError("Expected value, got None")
```

## **D. Clear Logging**
```python
logger.info("Loading profile: %s", path)
```

---

# 6. **Installer Flow Copilot Must Understand**

The installer follows a predictable sequence:

1. **Environment detection**  
2. **Host compatibility check**  
3. **Profile selection**  
4. **Diagnostics module**  
5. **Bootstrap phase**  
6. **Profile‑specific execution**  
7. **Plugin execution (optional)**  
8. **Finalization & logging**  

Copilot should autocomplete functions that fit into this flow.

---

# 7. **Commit Message Rules Copilot Must Follow**

Copilot must generate commit messages using this structure:

```
<type>(<scope>): <summary>

Context:
- Why this change exists

Changes:
- High-signal list of modifications

Safety:
- Guardrails added or improved
- Compatibility notes

Contributor Notes:
- Anything future maintainers must know
```

Valid types:  
`feat`, `fix`, `refactor`, `chore`, `docs`, `ci`, `test`

Valid scopes:  
`installer`, `container-wrapper`, `diagnostics`, `profiles`, `bootstrap`, `compat`, `logging`

---

# 8. **Examples Copilot Should Learn From**

## **Example 1 — Adding a guardrail**
```
fix(installer): add missing architecture guardrail

Context:
- The installer failed silently on unsupported architectures.

Changes:
- Added explicit architecture detection
- Added error path for unsupported hardware

Safety:
- Prevents accidental execution on non-Pi5 hosts

Contributor Notes:
- Future profiles should extend detect_architecture()
```

## **Example 2 — Updating container wrapper**
```
refactor(container-wrapper): unify host/container execution paths

Context:
- Execution logic diverged between host and container modes.

Changes:
- Consolidated environment detection
- Added fallback for missing runtime variables

Safety:
- Ensures reproducible behavior across environments

Contributor Notes:
- New helper added: ensure_runtime_env()
```

---

# 9. **How Copilot Should Behave When Unsure**

Copilot should:

- prefer defensive patterns  
- avoid guessing architecture‑specific behavior  
- avoid generating monolithic scripts  
- avoid silent failures  
- avoid removing guardrails  
- avoid introducing implicit behavior  

When uncertain, Copilot should generate:

- explicit checks  
- clear logging  
- modular functions  

---

# 10. **Final Rule**

Copilot must treat this architecture as **stable, intentional, and authoritative**.  
Autocomplete should reinforce the ecosystem’s design, not diverge from it.
