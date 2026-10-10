#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/a1-env.sh
if test "$#" -gt 1 || { test "$#" -eq 1 && test "$1" != "--fixture-only"; }; then echo "Unknown build option." >&2; exit 1; fi
swift build -c release --product PAIAInputMethod
swift build -c release --product paia-resources
app=.build/PAIAInputMethodFixture.app
pack="$app/Contents/Resources/DictionaryFixturePack"
if test -e "$pack"; then echo "Resource bundle already exists; use a fresh build directory." >&2; exit 1; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Engine" "$app/Contents/Resources/Dictionaries"
cp "$(swift build -c release --show-bin-path)/PAIAInputMethod" "$app/Contents/MacOS/"
cp "$PAIA_RIME_LIBRARY" "$app/Contents/Resources/Engine/librime.1.16.0.dylib"
cp "$(swift build -c release --show-bin-path)/paia-resources" "$app/Contents/MacOS/paia-resources"
# Fresh packaging directory; never replace a published resource generation.
"$app/Contents/MacOS/paia-resources" compile "$pack" baseline "$PAIA_RIME_LIBRARY" > .build/imk-resource-reference.json
python3 - "$app" "$PAIA_RIME_LIBRARY" <<'PY_PROBE'
import json,subprocess,sys
from pathlib import Path
app=Path(sys.argv[1]);ref=json.loads(Path('.build/imk-resource-reference.json').read_text())
r=subprocess.run([str(app/'Contents/MacOS/paia-resources'),'probe',str(app/'Contents/Resources/DictionaryFixturePack'),ref['generation'],ref['manifestSHA'],sys.argv[2]],check=True,capture_output=True,text=True,timeout=30)
receipt=json.loads(r.stdout);assert receipt['reference']==ref and receipt['deployments']==0 and len(receipt['schemas'])==2 and receipt['commits']==2
print('RESOURCE_BUNDLE_NATIVE all two authored schemas committed once; zero deploy at probe.')
PY_PROBE
cp -R Licenses "$app/Contents/Resources/"
python3 - "$app" "$PAIA_DICTIONARY_REVISION" <<'PY'
import hashlib,json,plistlib,sys
from pathlib import Path
app=Path(sys.argv[1]);content=app/'Contents'
info={'CFBundleName':'PAIA Input Method Integration','CFBundleIdentifier':'dev.paia.ime.integration','CFBundleExecutable':'PAIAInputMethod','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'0.2.0','LSUIElement':True,'NSHighResolutionCapable':True,'InputMethodConnectionName':'dev.paia.ime.integration.connection','InputMethodServerControllerClass':'PAIAInputMethodController','tsInputMethodCharacterRepertoireKey':['zh'],'PAIADictionaryRevision':sys.argv[2],'PAIAIntegrationFixtureOnly':True}
reference=json.loads(Path('.build/imk-resource-reference.json').read_text())
info.update(PAIAResourceGeneration=reference['generation'],PAIAResourceManifestSHA=reference['manifestSHA'],PAIAResourceHelperSHA=hashlib.sha256((content/'MacOS/paia-resources').read_bytes()).hexdigest())
(content/'Info.plist').write_bytes(plistlib.dumps(info))
manifest={p.relative_to(app).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(app.rglob('*')) if p.is_file()}
(app.parent/'imk-bundle-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'bundle':str(app),'controller':info['InputMethodServerControllerClass'],'files':len(manifest),'signed':False,'installed':False,'serverStarted':False,'fixtureOnly':True}))
PY
# Never copy into Input Methods directories, invoke TIS/LaunchServices, sign, or
# alter system settings. The default service entry is NOT run by this build script.
echo "$app"
if test "$#" -eq 0; then bash Tools/build-candidate.sh; fi
