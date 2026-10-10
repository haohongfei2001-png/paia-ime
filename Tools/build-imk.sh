#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/a1-env.sh
swift build -c release --product PAIAInputMethod
app=.build/PAIAInputMethod.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Engine" "$app/Contents/Resources/Dictionaries"
cp "$(swift build -c release --show-bin-path)/PAIAInputMethod" "$app/Contents/MacOS/"
cp "$PAIA_RIME_LIBRARY" "$app/Contents/Resources/Engine/librime.1.16.0.dylib"
cp -R Resources/Dictionaries/A1Fixture "$app/Contents/Resources/Dictionaries/"
cp -R Licenses "$app/Contents/Resources/"
python3 - "$app" "$PAIA_DICTIONARY_REVISION" <<'PY'
import hashlib,json,plistlib,sys
from pathlib import Path
app=Path(sys.argv[1]);content=app/'Contents'
info={'CFBundleName':'PAIA Input Method Integration','CFBundleIdentifier':'dev.paia.ime.integration','CFBundleExecutable':'PAIAInputMethod','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'0.2.0','LSBackgroundOnly':True,'NSHighResolutionCapable':True,'InputMethodConnectionName':'dev.paia.ime.integration.connection','InputMethodServerControllerClass':'PAIAInputMethodController','tsInputMethodCharacterRepertoireKey':['zh'],'PAIADictionaryRevision':sys.argv[2],'PAIAIntegrationFixtureOnly':True}
(content/'Info.plist').write_bytes(plistlib.dumps(info))
manifest={p.relative_to(app).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(app.rglob('*')) if p.is_file()}
(app.parent/'imk-bundle-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'bundle':str(app),'controller':info['InputMethodServerControllerClass'],'files':len(manifest),'signed':False,'installed':False,'serverStarted':False,'fixtureOnly':True}))
PY
# Never copy into Input Methods directories, invoke TIS/LaunchServices, sign, or
# alter system settings. The default service entry is NOT run by this build script.
echo "$app"
