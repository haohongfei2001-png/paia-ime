#include "paia_rime.h"
#include "../Sources/CRimeShim/rime_api.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    RimeApi api;
    memset(&api, 0xff, sizeof(api));
    RIME_STRUCT_INIT(RimeApi,api);
    assert(paia_rime_api_compatible(&api));
    api.data_size=-1;assert(!paia_rime_api_compatible(&api));
    api.data_size=0;assert(!paia_rime_api_compatible(&api));
    api.data_size=offsetof(RimeApi,select_candidate_on_current_page)+sizeof(api.select_candidate_on_current_page)-sizeof(api.data_size)-1;
    assert(!paia_rime_api_compatible(&api));
    RIME_STRUCT_INIT(RimeApi,api);api.get_input=NULL;assert(!paia_rime_api_compatible(&api));
    assert(!paia_rime_api_compatible(NULL));
    PaiaRimeSnapshot snapshot={0};paia_rime_free_snapshot(&snapshot);paia_rime_free_snapshot(&snapshot);
    assert(paia_rime_step(0,0,0,0,&snapshot)==PAIA_SESSION);
    uint64_t before_clock=paia_rime_monotonic_nanoseconds();assert(before_clock>0);
    assert(paia_rime_monotonic_nanoseconds()>=before_clock);
    PaiaRimeDiagnostics diagnostics={0};paia_rime_diagnostics(&diagnostics);
    assert(diagnostics.failed_steps==1 && !diagnostics.keys && !diagnostics.selections && !diagnostics.clears && !diagnostics.snapshots);
    assert(!paia_rime_learning_disabled(0));paia_rime_diagnostics(NULL);
    // Output copies have no native object pointers and remain releasable after
    // table/runtime closure. Authored allocations, not real engine evidence.
    PaiaG01List list={0};list.raw=strdup("synthetic");list.preview=strdup("synthetic");
    list.count=1;list.items=calloc(1,sizeof(*list.items));list.items[0].text=strdup("synthetic");
    PaiaMixedSelection selection={0};selection.surface=strdup("synthetic");
    PaiaMixedImport imported={0};imported.raw=strdup("synthetic");imported.count=2;
    imported.anchors=calloc(imported.count,sizeof(*imported.anchors));
    for(size_t i=0;i<imported.count;++i)imported.anchors[i].surface=strdup("synthetic");
    char *text=strdup("synthetic");
    paia_rime_close();paia_rime_g01_free_list(&list);paia_rime_mixed_free_selection(&selection);
    paia_rime_mixed_free_import(&imported);paia_rime_mixed_free_text(text);
    assert(!list.raw && !list.preview && !list.items && !list.count && !selection.surface && !imported.raw && !imported.anchors && !imported.count);
    paia_rime_g01_free_list(&list);paia_rime_mixed_free_selection(&selection);paia_rime_mixed_free_import(&imported);
    puts("SIMULATED mixed output ownership: list/selection/import/text release after close, zeroed repeated free; sanitizer checked.");
    puts("SIMULATED ABI guard: 8 checks passed; no real engine or AppKit host exercised.");
}
