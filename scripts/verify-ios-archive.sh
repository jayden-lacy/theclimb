#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/verify-ios-archive.sh <archive.xcarchive> [version] [build] [signing] [xcode-build] [sdk-prefix]

signing may be: any (default), development, or distribution.
Example: scripts/verify-ios-archive.sh App.xcarchive 1.0 18 development 17F113 iphoneos26
EOF
}

fail() {
  printf 'Archive validation failed: %s\n' "$1" >&2
  exit 1
}

warn() {
  printf 'Archive validation warning: %s\n' "$1" >&2
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null
}

contains_line() {
  local expected="$1"
  shift
  printf '%s\n' "$@" | grep -Fqx "$expected"
}

if [[ $# -lt 1 || $# -gt 6 ]]; then
  usage >&2
  exit 2
fi

archive="${1%/}"
expected_version="${2:-}"
expected_build="${3:-}"
signing_mode="${4:-any}"
expected_xcode_build="${5:-}"
expected_sdk_prefix="${6:-}"

case "$signing_mode" in
  any|development|distribution) ;;
  *) fail "unknown signing mode '$signing_mode'" ;;
esac

[[ -d "$archive" ]] || fail "archive not found at $archive"
[[ -f "$archive/Info.plist" ]] || fail "archive Info.plist is missing"

application_path="$(plist_value 'ApplicationProperties:ApplicationPath' "$archive/Info.plist")"
app="$archive/Products/$application_path"
[[ -d "$app" ]] || fail "archived app not found at $app"

archive_version="$(plist_value 'ApplicationProperties:CFBundleShortVersionString' "$archive/Info.plist")"
archive_build="$(plist_value 'ApplicationProperties:CFBundleVersion' "$archive/Info.plist")"
archive_xcode_build="$(plist_value 'DTXcodeBuild' "$app/Info.plist")"
archive_sdk="$(plist_value 'DTSDKName' "$app/Info.plist")"

if [[ -n "$expected_version" && "$archive_version" != "$expected_version" ]]; then
  fail "expected version $expected_version but found $archive_version"
fi
if [[ -n "$expected_build" && "$archive_build" != "$expected_build" ]]; then
  fail "expected build $expected_build but found $archive_build"
fi
if [[ -n "$expected_xcode_build" && "$archive_xcode_build" != "$expected_xcode_build" ]]; then
  fail "expected Xcode build $expected_xcode_build but found $archive_xcode_build"
fi
if [[ -n "$expected_sdk_prefix" && "$archive_sdk" != "$expected_sdk_prefix"* ]]; then
  fail "expected SDK prefix $expected_sdk_prefix but found $archive_sdk"
fi

expected_ids=(
  "com.jaydenlacy.theclimb"
  "com.jaydenlacy.theclimb.widget"
  "com.jaydenlacy.theclimb.shieldconfiguration"
  "com.jaydenlacy.theclimb.shieldaction"
  "com.jaydenlacy.theclimb.deviceactivitymonitor"
  "com.jaydenlacy.theclimb.deviceactivityreport"
  "com.jaydenlacy.theclimb.contentblocker"
)

family_control_ids=(
  "com.jaydenlacy.theclimb"
  "com.jaydenlacy.theclimb.shieldconfiguration"
  "com.jaydenlacy.theclimb.shieldaction"
  "com.jaydenlacy.theclimb.deviceactivitymonitor"
  "com.jaydenlacy.theclimb.deviceactivityreport"
)

privacy_manifest_ids=(
  "com.jaydenlacy.theclimb"
  "com.jaydenlacy.theclimb.widget"
  "com.jaydenlacy.theclimb.shieldconfiguration"
  "com.jaydenlacy.theclimb.deviceactivitymonitor"
  "com.jaydenlacy.theclimb.deviceactivityreport"
  "com.jaydenlacy.theclimb.contentblocker"
)

bundles=("$app")
while IFS= read -r bundle; do
  bundles+=("$bundle")
done < <(find "$app/PlugIns" "$app/Extensions" -mindepth 1 -maxdepth 1 -type d -name '*.appex' -print 2>/dev/null | sort)

[[ ${#bundles[@]} -eq ${#expected_ids[@]} ]] ||
  fail "expected ${#expected_ids[@]} app bundles but found ${#bundles[@]}"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

actual_ids=()
for bundle in "${bundles[@]}"; do
  info_plist="$bundle/Info.plist"
  [[ -f "$info_plist" ]] || fail "Info.plist is missing from $(basename "$bundle")"

  bundle_id="$(plist_value 'CFBundleIdentifier' "$info_plist")"
  bundle_version="$(plist_value 'CFBundleShortVersionString' "$info_plist")"
  bundle_build="$(plist_value 'CFBundleVersion' "$info_plist")"
  executable="$(plist_value 'CFBundleExecutable' "$info_plist")"
  binary="$bundle/$executable"
  actual_ids+=("$bundle_id")

  contains_line "$bundle_id" "${expected_ids[@]}" || fail "unexpected bundle identifier $bundle_id"
  [[ "$bundle_version" == "$archive_version" ]] || fail "$bundle_id has version $bundle_version"
  [[ "$bundle_build" == "$archive_build" ]] || fail "$bundle_id has build $bundle_build"
  [[ -x "$binary" ]] || fail "$bundle_id executable is missing"

  if [[ "$bundle" == *.appex ]]; then
    plist_value 'CFBundleDisplayName' "$info_plist" >/dev/null || fail "$bundle_id has no display name"
  fi

  if contains_line "$bundle_id" "${privacy_manifest_ids[@]}"; then
    [[ -f "$bundle/PrivacyInfo.xcprivacy" ]] || fail "$bundle_id has no privacy manifest"
  fi

  entitlements="$temporary_directory/$(echo "$bundle_id" | tr '.' '_').plist"
  /usr/bin/codesign -d --entitlements :- "$bundle" >"$entitlements" 2>/dev/null ||
    fail "could not read entitlements for $bundle_id"

  plist_value 'com.apple.security.application-groups' "$entitlements" |
    grep -Fq 'group.com.jaydenlacy.theclimb' || fail "$bundle_id is missing the shared App Group"

  if contains_line "$bundle_id" "${family_control_ids[@]}"; then
    [[ "$(plist_value 'com.apple.developer.family-controls' "$entitlements")" == 'true' ]] ||
      fail "$bundle_id is missing Family Controls"
  elif plist_value 'com.apple.developer.family-controls' "$entitlements" >/dev/null; then
    fail "$bundle_id unexpectedly includes Family Controls"
  fi

  if [[ "$bundle_id" == 'com.jaydenlacy.theclimb' ]]; then
    plist_value 'com.apple.developer.applesignin' "$entitlements" | grep -Fq 'Default' ||
      fail "the main app is missing Sign in with Apple"
    plist_value 'com.apple.developer.associated-domains' "$entitlements" |
      grep -Fq 'applinks:theclimbapp.org' || fail "the main app is missing its associated domain"
  fi

  dsym="$archive/dSYMs/$(basename "$bundle").dSYM"
  [[ -d "$dsym" ]] || fail "$bundle_id dSYM is missing"
  dsym_binary="$(find "$dsym/Contents/Resources/DWARF" -mindepth 1 -maxdepth 1 -type f -print -quit)"
  [[ -n "$dsym_binary" ]] || fail "$bundle_id dSYM has no DWARF binary"

  binary_uuids="$(dwarfdump --uuid "$binary" | awk '{print $2}' | sort)"
  dsym_uuids="$(dwarfdump --uuid "$dsym_binary" | awk '{print $2}' | sort)"
  [[ -n "$binary_uuids" && "$binary_uuids" == "$dsym_uuids" ]] ||
    fail "$bundle_id dSYM UUID does not match its executable"
done

for expected_id in "${expected_ids[@]}"; do
  contains_line "$expected_id" "${actual_ids[@]}" || fail "required bundle $expected_id is missing"
done

[[ "$(plist_value 'NSSupportsLiveActivities' "$app/Info.plist")" == 'true' ]] ||
  fail "the main app does not advertise Live Activities"

device_families="$(plist_value 'UIDeviceFamily' "$app/Info.plist")"
grep -Eq '(^|[^0-9])1([^0-9]|$)' <<<"$device_families" || fail "iPhone is not in UIDeviceFamily"
if grep -Eq '(^|[^0-9])2([^0-9]|$)' <<<"$device_families"; then
  fail "the archive unexpectedly declares iPad support"
fi

find "$app" -type d \( -name '*.watchkitapp' -o -name '*.networkextension' \) -print -quit |
  grep -q . && fail "the archive includes an unsupported Watch or Network Extension target"

/usr/bin/codesign --verify --deep --strict "$app" || fail "deep code-sign verification failed"

main_entitlements="$temporary_directory/main.plist"
/usr/bin/codesign -d --entitlements :- "$app" >"$main_entitlements" 2>/dev/null
get_task_allow="$(plist_value 'get-task-allow' "$main_entitlements" || true)"
signature_details="$(/usr/bin/codesign -dvv "$app" 2>&1)"

case "$signing_mode" in
  development)
    [[ "$get_task_allow" == 'true' ]] || fail "archive is not development signed"
    grep -Fq 'Authority=Apple Development:' <<<"$signature_details" ||
      fail "Apple Development signing authority is missing"
    ;;
  distribution)
    [[ "$get_task_allow" != 'true' ]] || fail "distribution archive still allows debugging"
    grep -Eq 'Authority=(Apple Distribution|iPhone Distribution):' <<<"$signature_details" ||
      fail "Apple Distribution signing authority is missing"
    ;;
esac

third_party_manifest_count="$(find "$app" -mindepth 2 -type f -name 'PrivacyInfo.xcprivacy' | wc -l | tr -d ' ')"
[[ "$third_party_manifest_count" -gt 0 ]] || fail "no third-party privacy manifests were embedded"

missing_framework_dsyms=()
if [[ -d "$app/Frameworks" ]]; then
  while IFS= read -r framework; do
    framework_name="$(basename "$framework")"
    if [[ ! -d "$archive/dSYMs/$framework_name.dSYM" ]]; then
      missing_framework_dsyms+=("$framework_name")
    fi
  done < <(find "$app/Frameworks" -mindepth 1 -maxdepth 1 -type d -name '*.framework' -print | sort)
fi

if [[ ${#missing_framework_dsyms[@]} -gt 0 ]]; then
  warn "precompiled frameworks have no archive dSYMs: ${missing_framework_dsyms[*]}. This may produce non-blocking App Store symbol-upload warnings."
fi

printf 'Archive validation passed.\n'
printf 'Version: %s (%s)\n' "$archive_version" "$archive_build"
printf 'Bundles: %s\n' "${#bundles[@]}"
printf 'Signing: %s\n' "$signing_mode"
printf 'Toolchain: Xcode build %s, SDK %s\n' "$archive_xcode_build" "$archive_sdk"
printf 'Third-party privacy manifests: %s\n' "$third_party_manifest_count"
