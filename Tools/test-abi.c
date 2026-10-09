#include "paia_rime.h"
#include "../Sources/CRimeShim/rime_api.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
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
    puts("SIMULATED ABI guard: 8 checks passed; no real engine or AppKit host exercised.");
}
