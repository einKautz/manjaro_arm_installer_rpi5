#!/usr/bin/env bash
#
# HAL and Profile System Test
# Validates HAL modules and profile loading
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== HAL and Profile System Test ==="
echo

# Test 1: Load libraries
echo "Test 1: Loading libraries..."
source lib/log.sh || { echo "❌ Failed to load lib/log.sh"; exit 1; }
source lib/profiles.sh || { echo "❌ Failed to load lib/profiles.sh"; exit 1; }
echo "✅ Libraries loaded successfully"
echo

# Test 2: Load HAL modules
echo "Test 2: Loading HAL modules..."
hal_modules=("display" "storage" "overlay")
for module in "${hal_modules[@]}"; do
    if [[ -f "hal/${module}.sh" ]]; then
        source "hal/${module}.sh" || { echo "❌ Failed to load hal/${module}.sh"; exit 1; }
        echo "  ✅ hal/${module}.sh loaded"
    else
        echo "  ❌ hal/${module}.sh not found"
        exit 1
    fi
done
echo "✅ All HAL modules loaded"
echo

# Test 3: Validate HAL functions
echo "Test 3: Validating HAL functions..."
hal_functions=(
    "hal_display_detect"
    "hal_display_configure"
    "hal_storage_detect_type"
    "hal_storage_get_capacity"
    "hal_overlay_enable"
    "hal_overlay_disable"
)

missing=0
for func in "${hal_functions[@]}"; do
    if command -v "$func" &>/dev/null; then
        echo "  ✅ $func available"
    else
        echo "  ❌ $func not found"
        ((missing++))
    fi
done

if [[ $missing -gt 0 ]]; then
    echo "❌ $missing HAL function(s) missing"
    exit 1
fi
echo "✅ All HAL functions available"
echo

# Test 4: Load profiles
echo "Test 4: Loading profiles..."
if ! command -v jq &>/dev/null; then
    echo "⚠️  jq not installed, installing for test..."
    sudo pacman -S --noconfirm jq 2>/dev/null || {
        echo "❌ Could not install jq, skipping profile tests"
        exit 1
    }
fi

profile_load_all || { echo "❌ Failed to load profiles"; exit 1; }
echo "✅ Profiles loaded"
echo

# Test 5: List profiles
echo "Test 5: Listing profiles..."
profile_list
echo "✅ Profiles listed"
echo

# Test 6: Validate profile structure
echo "Test 6: Validating profile structure..."
profiles=("minimal" "xfce" "kde" "cyberdeck" "kiosk")
for profile in "${profiles[@]}"; do
    if [[ -f "profiles/${profile}.json" ]]; then
        echo "  Validating $profile..."
        
        # Check required fields
        jq -e '.name' "profiles/${profile}.json" >/dev/null || { echo "    ❌ Missing 'name'"; exit 1; }
        jq -e '.description' "profiles/${profile}.json" >/dev/null || { echo "    ❌ Missing 'description'"; exit 1; }
        jq -e '.base_packages' "profiles/${profile}.json" >/dev/null || { echo "    ❌ Missing 'base_packages'"; exit 1; }
        jq -e '.edition_packages' "profiles/${profile}.json" >/dev/null || { echo "    ❌ Missing 'edition_packages'"; exit 1; }
        jq -e '.services' "profiles/${profile}.json" >/dev/null || { echo "    ❌ Missing 'services'"; exit 1; }
        jq -e '.optimizations' "profiles/${profile}.json" >/dev/null || { echo "    ❌ Missing 'optimizations'"; exit 1; }
        jq -e '.config' "profiles/${profile}.json" >/dev/null || { echo "    ❌ Missing 'config'"; exit 1; }
        jq -e '.features' "profiles/${profile}.json" >/dev/null || { echo "    ❌ Missing 'features'"; exit 1; }
        
        echo "    ✅ $profile valid"
    else
        echo "  ❌ Profile file not found: $profile"
        exit 1
    fi
done
echo "✅ All profiles have required structure"
echo

# Test 7: Test profile functions
echo "Test 7: Testing profile functions..."

# Test profile_get_packages
pkg_count=$(profile_get_packages "minimal" "base" | wc -l)
echo "  minimal base packages: $pkg_count"
if [[ $pkg_count -lt 5 ]]; then
    echo "  ❌ Expected more base packages"
    exit 1
fi
echo "  ✅ profile_get_packages works"

# Test profile_get_config
gpu_mem=$(profile_get_config "minimal" "gpu_mem")
echo "  minimal gpu_mem: $gpu_mem"
if [[ "$gpu_mem" != "16" ]]; then
    echo "  ❌ Expected gpu_mem=16 for minimal"
    exit 1
fi
echo "  ✅ profile_get_config works"

# Test profile_has_feature
if profile_has_feature "xfce" "gui"; then
    echo "  ✅ profile_has_feature works (xfce has GUI)"
else
    echo "  ❌ profile_has_feature failed (xfce should have GUI)"
    exit 1
fi

if profile_has_feature "minimal" "gui"; then
    echo "  ❌ minimal should not have GUI feature"
    exit 1
else
    echo "  ✅ profile_has_feature correctly identifies missing features"
fi

echo "✅ Profile functions working correctly"
echo

# Test 8: Validate profile features
echo "Test 8: Validating profile features..."
echo "  minimal: GUI=$(profile_has_feature "minimal" "gui" && echo "yes" || echo "no")"
echo "  xfce: GUI=$(profile_has_feature "xfce" "gui" && echo "yes" || echo "no")"
echo "  kde: GUI=$(profile_has_feature "kde" "gui" && echo "yes" || echo "no")"
echo "  cyberdeck: Cyberdeck=$(profile_has_feature "cyberdeck" "cyberdeck" && echo "yes" || echo "no")"
echo "  kiosk: Kiosk=$(profile_has_feature "kiosk" "kiosk" && echo "yes" || echo "no")"
echo "✅ Feature detection working"
echo

# Test 9: File count
echo "Test 9: Counting files..."
hal_count=$(find hal -name "*.sh" -type f | wc -l)
profile_count=$(find profiles -name "*.json" -type f | wc -l)

echo "  HAL modules: $hal_count"
echo "  Profiles: $profile_count"

if [[ $hal_count -lt 3 ]]; then
    echo "❌ Expected at least 3 HAL modules"
    exit 1
fi

if [[ $profile_count -lt 5 ]]; then
    echo "❌ Expected at least 5 profiles"
    exit 1
fi

echo "✅ File counts correct"
echo

# Test 10: Shellcheck validation
echo "Test 10: Running shellcheck on HAL modules..."
shellcheck_failed=0
for module in hal/*.sh; do
    if shellcheck "$module" 2>/dev/null; then
        echo "  ✅ $(basename "$module") passes shellcheck"
    else
        echo "  ❌ $(basename "$module") has shellcheck errors"
        ((shellcheck_failed++))
    fi
done

if shellcheck "lib/profiles.sh" 2>/dev/null; then
    echo "  ✅ lib/profiles.sh passes shellcheck"
else
    echo "  ❌ lib/profiles.sh has shellcheck errors"
    ((shellcheck_failed++))
fi

if [[ $shellcheck_failed -gt 0 ]]; then
    echo "❌ $shellcheck_failed file(s) failed shellcheck"
    exit 1
fi

echo "✅ All files pass shellcheck"
echo

echo "============================================"
echo "✅ All HAL and Profile tests passed!"
echo "============================================"
echo
echo "Summary:"
echo "  • 3 HAL modules created (display, storage, overlay)"
echo "  • 5 installation profiles (minimal, xfce, kde, cyberdeck, kiosk)"
echo "  • Profile loader with jq-based JSON parsing"
echo "  • All functions available and working"
echo "  • All files pass shellcheck validation"
echo
echo "Phase 3 Step 3 (HAL and Profiles): COMPLETE ✅"
