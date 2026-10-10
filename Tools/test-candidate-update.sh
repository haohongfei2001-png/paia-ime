#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PAIA_CANDIDATE_BUNDLE="$PWD/.build/PAIAInputMethod.app"
export PAIA_PRODUCT_PARENT="$PWD/.build/candidate-update-data"
helper="$PAIA_CANDIDATE_BUNDLE/Contents/MacOS/paia-resources"
test ! -e "$PAIA_PRODUCT_PARENT"
mkdir -m 700 "$PAIA_PRODUCT_PARENT"
# This actual bundled preset-only command has no arbitrary pack/YAML argument.
"$helper" candidate-publish baseline 0 create "$PAIA_PRODUCT_PARENT" | tee evidence/imk-run/update-initial-index.json
stage() {
  PAIA_UPDATE_STAGE="$1" swift test --skip-build --filter 'ProductCandidateTests/testCandidateUpdateAndCurrentPersonalAuthorityStage' 2>&1 | tee "evidence/imk-run/update-$1.txt"
  grep -Fq "CANDIDATE_UPDATE_STAGE $1" "evidence/imk-run/update-$1.txt"
  grep -Fq 'Executed 1 test, with 0 failures' "evidence/imk-run/update-$1.txt"
}
stage active_publication
stage after_publication
python3 - <<'PY_MANIFEST'
from pathlib import Path
import json
root=Path('.build/candidate-update-data/paia-ime-public-resources');index=json.loads((root/'index.json').read_bytes())
for label,reference in [('baseline',index['lastGood']),('updated',index['current'])]:
    data=(root/'generations'/reference['generation']/'manifest.json').read_bytes()
    Path('evidence/imk-run/update-public-'+label+'-manifest.json').write_bytes(data)
    print('CANDIDATE_UPDATE_PUBLIC_MANIFEST '+label+' '+data.decode())
PY_MANIFEST
swift test --skip-build --filter 'ProductCandidateTests/testCandidateUpdateMarkerRejectsCoherentOldCompiledArtifacts' 2>&1 | tee evidence/imk-run/update-marker.txt
grep -Fq 'CANDIDATE_UPDATE_MARKER_NATIVE coherent_old_binary_refused=true' evidence/imk-run/update-marker.txt
swift test --skip-build --filter 'ProductCandidateTests/testCandidateUpdateHelperFaultsAreReapedBeforeRecordedFallback' 2>&1 | tee evidence/imk-run/update-helper-faults.txt
grep -Fq 'CANDIDATE_UPDATE_HELPER_FAULTS faults=4 reaped_before_fallback=true' evidence/imk-run/update-helper-faults.txt
# Preserve this exact healthy two-generation public-only baseline for faults.
for kind in fallback semantic wrong_prism both missing_index; do
  parent="$PWD/.build/candidate-update-$kind"
  test ! -e "$parent"
  cp -R "$PAIA_PRODUCT_PARENT" "$parent"
  python3 Tools/prepare-candidate-update-fault.py "$parent" "$kind"
  PAIA_PRODUCT_PARENT="$parent" stage "$kind"
done
# Settings/terms/expressions have their own authority and never enter the catalog.
PAIA_PRODUCT_STAGE=save swift test --skip-build --filter 'ProductCandidateTests/testSaveRestartDeleteAndNativeOwnerStage' 2>&1 | tee evidence/imk-run/update-personal-save.txt
grep -Fq 'PRODUCT_RESTART_STAGE save' evidence/imk-run/update-personal-save.txt
stage personal_updated
swift test --skip-build --filter 'ProductCandidateTests/testCandidateUpdateLateNativeFailureNeverRetries' 2>&1 | tee evidence/imk-run/update-late-native.txt
grep -Fq 'CANDIDATE_UPDATE_LATE_NATIVE main_attempts=1 no_in_process_fallback=true' evidence/imk-run/update-late-native.txt
python3 Tools/prepare-candidate-update-fault.py "$PAIA_PRODUCT_PARENT" personal_fallback
stage personal_fallback
PAIA_PRODUCT_STAGE=delete swift test --skip-build --filter 'ProductCandidateTests/testSaveRestartDeleteAndNativeOwnerStage' 2>&1 | tee evidence/imk-run/update-personal-delete.txt
grep -Fq 'PRODUCT_RESTART_STAGE delete' evidence/imk-run/update-personal-delete.txt
# Only the public generation changes. Current tombstones remain authoritative.
"$helper" candidate-publish updated 2 existing "$PAIA_PRODUCT_PARENT" | tee evidence/imk-run/update-after-deletion-index.json
stage deleted
python3 Tools/check-candidate-update-entry.py
swift test --skip-build --filter 'ProductCandidateTests/testCandidateCatalogOnlyMetadataNeverEntersResearchLane' 2>&1 | tee evidence/imk-run/update-catalog-metadata.txt
grep -Fq 'CANDIDATE_CATALOG_METADATA_NEGATIVE main_attempts=0' evidence/imk-run/update-catalog-metadata.txt
python3 Tools/check-candidate-update-routing.py 2>&1 | tee evidence/imk-run/update-catalog-routing-red.txt
git diff --exit-code
swift test --filter 'ProductCandidateTests/testCandidateCatalogOnlyMetadataNeverEntersResearchLane' 2>&1 | tee evidence/imk-run/update-catalog-metadata-restored.txt
grep -Fq 'Executed 1 test, with 0 failures' evidence/imk-run/update-catalog-metadata-restored.txt
