#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/a1-env.sh
app=.build/PAIAInputMethod.app
if test -e "$app"; then echo "Candidate bundle already exists; use a fresh build directory." >&2; exit 1; fi
python3 Tools/prepare-candidate.py
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Engine"
cp "$(swift build -c release --show-bin-path)/PAIAInputMethod" "$app/Contents/MacOS/"
cp "$(swift build -c release --show-bin-path)/paia-resources" "$app/Contents/MacOS/"
cp "$PAIA_RIME_LIBRARY" "$app/Contents/Resources/Engine/librime.1.dylib"
# Link against the unchanged pinned binary, with only a loader-local lookup for
# the engine install name. No absolute build-cache rpath or install_name rewrite.
clang++ -std=c++17 -stdlib=libc++ -Wall -Wextra -Werror -Wno-unused-parameter \
  -ISources/CRimeShim/include -ISources/CRimeShim -isystem .build/a2-headers/src -isystem .build/a2-boost \
  -dynamiclib Tools/G01Bridge/paia_g01.cc "$PAIA_RIME_LIBRARY" \
  -Wl,-rpath,@loader_path -Wl,-install_name,@rpath/paia-g01.dylib \
  -o "$app/Contents/Resources/Engine/paia-g01.dylib"
cp -R Licenses "$app/Contents/Resources/"
cp .build/candidate-inputs.json "$app/Contents/Resources/candidate-inputs.json"
python3 - "$app" <<'PY'
import hashlib,json,plistlib,re,subprocess,sys
from pathlib import Path
app=Path(sys.argv[1]).resolve();content=app/'Contents';resources=content/'Resources'
helper=content/'MacOS/paia-resources';library=resources/'Engine/librime.1.dylib';bridge=resources/'Engine/paia-g01.dylib'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
dependencies=subprocess.check_output(['otool','-L',str(bridge)],text=True)
loads=subprocess.check_output(['otool','-l',str(bridge)],text=True)
rpaths=re.findall(r'cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.*?) \(offset',loads)
assert rpaths==['@loader_path'],rpaths
linked=[line.strip().split(' (compatibility',1)[0] for line in dependencies.splitlines()[1:]]
assert '@rpath/librime.1.dylib' in linked,linked
assert all(x in ['@rpath/paia-g01.dylib','@rpath/librime.1.dylib'] or x.startswith('/usr/lib/') or x.startswith('/System/Library/') for x in linked),linked
print(dependencies);print('CANDIDATE_LOADER loader-local engine dependency; no build-cache rpath')
inputs=json.loads(Path('.build/candidate-inputs.json').read_text())
result=subprocess.run([str(helper),'candidate-compile',str(Path('.build/candidate-sources').resolve()),inputs['inputsSHA'],str(resources/'CandidatePack'),str(library)],check=True,capture_output=True,text=True,timeout=120)
reference=json.loads(result.stdout)
info={'CFBundleName':'PAIA Input Method Candidate','CFBundleIdentifier':'dev.paia.ime.candidate','CFBundleExecutable':'PAIAInputMethod','CFBundlePackageType':'APPL','CFBundleVersion':'2','CFBundleShortVersionString':'0.3.1','LSUIElement':True,'NSHighResolutionCapable':True,'InputMethodConnectionName':'dev.paia.ime.candidate.connection','InputMethodServerControllerClass':'PAIAInputMethodController','tsInputMethodCharacterRepertoireKey':['zh'],'PAIAIntegrationFixtureOnly':True,'PAIACandidateProfile':inputs['profile'],'PAIACandidateResourceCatalog':'paia-public-candidate-v2','PAIACandidateGeneration':reference['generation'],'PAIACandidateManifestSHA':reference['manifestSHA'],'PAIACandidateExtensionSHA':sha(bridge),'PAIAResourceHelperSHA':sha(helper)}
(content/'Info.plist').write_bytes(plistlib.dumps(info))
probe=subprocess.run([str(helper),'candidate-probe',str(resources/'CandidatePack'),reference['generation'],reference['manifestSHA'],str(library),str(bridge),sha(bridge),sha(helper)],check=True,capture_output=True,text=True,timeout=120)
receipt=json.loads(probe.stdout)
assert receipt['reference']==reference and receipt['schemas']==32 and receipt['commits']==106 and receipt['negativePolicies']==24 and receipt['punctuationCases']==32 and receipt['personalSamples']==0 and receipt['g01'] and receipt['mixed'] and receipt['deployments']==0,receipt
Path('.build/candidate-native-receipt.json').write_text(json.dumps(receipt,sort_keys=True)+'\n')
manifest={p.relative_to(app).as_posix():sha(p) for p in sorted(app.rglob('*')) if p.is_file()}
Path('.build/imk-bundle-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('CANDIDATE_BUNDLE_NATIVE schemas=32 commits=106 negative_policies=24 punctuation_cases=32 g01=true mixed=true deployments=0; authored words only')
print(json.dumps({'bundle':str(app),'signed':False,'installed':False,'serverStarted':False,'authoredRows':46,'researchCorpusIncluded':False}))
PY
# Building and helper probes never start IMKServer or register/install a source.
echo "$app"
