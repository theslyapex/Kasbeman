#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f apps/mobile/android/app/src/main/AndroidManifest.xml ]]; then
  echo "Android project not found. Run flutter create --platforms=android,ios . from apps/mobile first." >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path

manifest = Path("apps/mobile/android/app/src/main/AndroidManifest.xml")
source = manifest.read_text(encoding="utf-8")
if 'android:allowBackup="' in source:
    start = source.index('android:allowBackup="')
    end = source.index('"', start + len('android:allowBackup="'))
    source = source[:start] + 'android:allowBackup="false' + source[end:]
else:
    source = source.replace("<application", '<application android:allowBackup="false"', 1)
manifest.write_text(source, encoding="utf-8")

kotlin = Path("apps/mobile/android/app/build.gradle.kts")
groovy = Path("apps/mobile/android/app/build.gradle")
if kotlin.exists():
    source = kotlin.read_text(encoding="utf-8")
    source = source.replace("minSdk = flutter.minSdkVersion", "minSdk = maxOf(flutter.minSdkVersion, 23)", 1)
    kotlin.write_text(source, encoding="utf-8")
elif groovy.exists():
    source = groovy.read_text(encoding="utf-8")
    source = source.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion Math.max(flutter.minSdkVersion, 23)", 1)
    groovy.write_text(source, encoding="utf-8")
else:
    raise SystemExit("Flutter Android Gradle file was not found.")
PY
