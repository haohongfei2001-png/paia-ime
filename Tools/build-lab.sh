#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/a1-env.sh
swift build -c release --product PAIANativeLab
app=.build/PAIANativeLab.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Engine" "$app/Contents/Resources/Dictionaries"
cp "$(swift build -c release --show-bin-path)/PAIANativeLab" "$app/Contents/MacOS/"
cp "$PAIA_RIME_LIBRARY" "$app/Contents/Resources/Engine/librime.1.16.0.dylib"
cp -R Resources/Dictionaries/A1Fixture "$app/Contents/Resources/Dictionaries/"
cp -R Licenses "$app/Contents/Resources/"
python3 - "$app" "$PAIA_DICTIONARY_REVISION" <<'PYINFO'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleName':'PAIA A1 Native Lab','CFBundleIdentifier':'dev.paia.ime.a1lab','CFBundleExecutable':'PAIANativeLab','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'0.1.0','NSHighResolutionCapable':True,'PAIADictionaryRevision':sys.argv[2]}))
PYINFO
# This is an unsigned, uninstalled lab bundle. No signing, input-source registration or installation.
echo "$app"
