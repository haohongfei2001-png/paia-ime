#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PAIA_CANDIDATE_BUNDLE="$PWD/.build/PAIAInputMethod.app"
export PAIA_PRODUCT_PARENT="$PWD/.build/product-restart-data"
test ! -e "$PAIA_PRODUCT_PARENT"
mkdir -m 700 "$PAIA_PRODUCT_PARENT"
for stage in public save restore delete deleted; do
  PAIA_PRODUCT_STAGE="$stage" swift test --filter 'ProductCandidateTests/testSaveRestartDeleteAndNativeOwnerStage' 2>&1 | tee "evidence/imk-run/product-$stage.txt"
  grep -Fq "PRODUCT_RESTART_STAGE $stage ENGINE_NATIVE + APPKIT_HOST main_attempts=1 deployments=0" "evidence/imk-run/product-$stage.txt"
  grep -Fq 'Executed 1 test, with 0 failures' "evidence/imk-run/product-$stage.txt"
done
for stage in bad_settings missing_personal erased_personal second_writer helper_failure changed_authority replaced_root; do
  parent="$PWD/.build/product-fault-$stage"
  test ! -e "$parent"
  mkdir -m 700 "$parent"
  PAIA_PRODUCT_PARENT="$parent" PAIA_PRODUCT_STAGE="$stage" swift test --skip-build --filter 'ProductCandidateTests/testOptionalStoreAndPersonalPreparationFaultStage' 2>&1 | tee "evidence/imk-run/product-$stage.txt"
  grep -Fq "PRODUCT_FAULT_STAGE $stage ENGINE_NATIVE + APPKIT_HOST public_input_preserved=true main_attempts=1" "evidence/imk-run/product-$stage.txt"
  grep -Fq 'Executed 1 test, with 0 failures' "evidence/imk-run/product-$stage.txt"
done
swift test --skip-build --filter 'ProductCandidateTests/testMissingCandidateMetadataCannotEnterResearchLane' 2>&1 | tee evidence/imk-run/product-metadata.txt
grep -Fq 'PRODUCT_METADATA_NEGATIVE main_attempts=0 no_research_fallback=true' evidence/imk-run/product-metadata.txt
PAIA_CANDIDATE_G01_ONLY="$PWD/.build/candidate-negative-components/paia-g01.dylib" PAIA_CANDIDATE_SOURCES="$PWD/.build/candidate-sources" swift test --skip-build --filter 'ProductCandidateTests/testG01OnlyTableNeverAdvertisesMixedInput' 2>&1 | tee evidence/imk-run/product-g01-only.txt
grep -Fq 'PRODUCT_G01_ONLY_NATIVE repair=true mixed=false actual_commit=1' evidence/imk-run/product-g01-only.txt

python3 Tools/check-candidate-routing-regression.py 2>&1 | tee evidence/imk-run/product-routing-regression.txt
git diff --exit-code
swift test --filter 'ProductCandidateTests/testMissingCandidateMetadataCannotEnterResearchLane' 2>&1 | tee evidence/imk-run/product-metadata-restored.txt
grep -Fq 'Executed 1 test, with 0 failures' evidence/imk-run/product-metadata-restored.txt
