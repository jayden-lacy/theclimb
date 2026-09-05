#!/bin/bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [[ "$(node -p 'process.versions.node.split(".")[0]')" != "22" ]]; then
  for candidate in /opt/homebrew/opt/node@22/bin /usr/local/opt/node@22/bin; do
    if [[ -x "$candidate/node" ]]; then
      export PATH="$candidate:$PATH"
      break
    fi
  done
fi
if [[ "$(node -p 'process.versions.node.split(".")[0]')" != "22" ]]; then
  printf 'Use Node.js 22 to match the deployed Cloud Functions runtime.\n' >&2
  exit 1
fi
node --version

# Homebrew's keg-only JDK need not be registered as the system Java runtime.
if [[ -z "${JAVA_HOME:-}" ]]; then
  for candidate in /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home /usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home; do
    if [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      break
    fi
  done
fi
if [[ -n "${JAVA_HOME:-}" ]]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi
java -version
command -v firebase >/dev/null || { printf 'Install Firebase CLI before running emulator tests.\n' >&2; exit 1; }

# Never inherit a production project or service-account path into the test run.
unset GOOGLE_APPLICATION_CREDENTIALS FIREBASE_CONFIG
export GCLOUD_PROJECT=demo-theclimb-security
export GOOGLE_CLOUD_PROJECT="$GCLOUD_PROJECT"
firebase emulators:exec \
  --project "$GCLOUD_PROJECT" \
  --config firebase.security-tests.json \
  --only firestore,auth \
  'npm --prefix firebase/functions run test:security:run'
