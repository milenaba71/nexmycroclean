#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sdk="${ANDROID_HOME:?Android SDK richiesto}"
bt="$sdk/build-tools/35.0.0"
platform="$sdk/platforms/android-35/android.jar"
mkdir "$out/classes" "$out/dex"
javac -source 8 -target 8 -cp "$platform" -d "$out/classes" src/com/mycroclean/rfid/ReaderApp.java
jar cf "$out/app.jar" -C "$out/classes" .
"$bt/d8" --min-api 23 --lib "$platform" --output "$out/dex" "$out/app.jar"
"$bt/aapt" package -f -M AndroidManifest.xml -A assets -I "$platform" -F "$out/app.apk"
(cd "$out/dex" && zip -q "$out/app.apk" classes.dex)
"$bt/zipalign" -f 4 "$out/app.apk" "$out/aligned.apk"
keytool -genkeypair -keystore "$out/test.jks" -alias test -storepass android -keypass android -keyalg RSA -validity 365 -dname 'CN=Mycroclean RFID Test'
"$bt/apksigner" sign --ks "$out/test.jks" --ks-pass pass:android --out Mycroclean-RFID-test.apk "$out/aligned.apk"
"$bt/apksigner" verify Mycroclean-RFID-test.apk
