# Secret Scanning Workflow Fix

## Summary
Fixed the secret scanning pipeline that was failing due to CodeQL misconfiguration.

## Problem
The `.github/workflows/secret-scan.yml` workflow was failing with:
```
Code Scanning could not process the submitted SARIF file:
CodeQL analyses from advanced configurations cannot be processed when the default setup is enabled
```

## Root Cause
1. The workflow was trying to use CodeQL with `languages: python` for a Bash-only repository
2. The repository has CodeQL "default setup" enabled at the repository level
3. CodeQL "default setup" and "advanced configuration" (workflow-based) are mutually exclusive
4. This caused every run to fail during the CodeQL analysis step

## Solution
Removed the CodeQL steps from `secret-scan.yml` because:
1. CodeQL scanning is already handled by `.github/workflows/codeql.yml`
2. The secret scanning workflow should focus on actual secrets, not code quality
3. CodeQL doesn't directly support Bash secret scanning

## Changes Made
### Before:
```yaml
jobs:
  scan:
    permissions:
      actions: read
      contents: read
      security-events: write  # For CodeQL

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          submodules: true

      # CodeQL (was failing)
      - name: Initialize CodeQL (Secrets)
        uses: github/codeql-action/init@v4
        with:
          languages: python  # Wrong for Bash repo

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v4
        with:
          category: secret-scan

      # TruffleHog
      - name: Run TruffleHog
        uses: trufflesecurity/trufflehog@v3.64.0
        with:
          path: ./
          extra_args: --only-verified
```

### After:
```yaml
jobs:
  scan:
    permissions:
      actions: read
      contents: read  # Removed security-events

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Removed submodules

      # Custom secret scan
      - name: Run custom secret scan
        run: |
          bash scripts/scan_secrets.sh

      # TruffleHog with proper configuration
      - name: Run TruffleHog
        uses: trufflesecurity/trufflehog@v3.64.0
        with:
          path: ./
          base: ${{ github.event.pull_request.base.sha || github.event.before }}
          head: ${{ github.event.pull_request.head.sha || github.sha }}
          extra_args: --only-verified --fail
```

## Benefits
1. ✅ Removes CodeQL conflict - no more "action_required" failures
2. ✅ Faster execution - removed unnecessary CodeQL analysis
3. ✅ Proper TruffleHog configuration with explicit base/head refs
4. ✅ Added `--fail` flag to properly fail on verified secrets
5. ✅ Focuses on actual secret detection, not code analysis

## Verification
- Custom scan script tested locally: ✅
- YAML syntax validated: ✅
- Workflow structure correct: ✅
- No permission conflicts: ✅

## Note on "action_required" Status
If you see "action_required" status on bot-initiated PRs, this is GitHub's security feature requiring approval for workflows from bot accounts, not a workflow failure.

## Related Files
- `.github/workflows/secret-scan.yml` - Fixed secret scanning workflow
- `.github/workflows/codeql.yml` - Separate CodeQL analysis workflow
- `scripts/scan_secrets.sh` - Custom secret scanning script
- `.secret-scan-ignore` - Patterns to ignore during scanning
