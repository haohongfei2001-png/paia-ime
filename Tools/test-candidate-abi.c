// SIMULATED function-table guards only; no engine or host is initialized.
#include "paia_rime.h"
#include <assert.h>
#include <stdio.h>
static int open_owner(uint64_t s,uint64_t *o){(void)s;(void)o;return 0;}
static void close_owner(uint64_t o){(void)o;}
static void close_all(void){}
static int project(uint64_t o,const char *r,size_t n,size_t l,PaiaMixedPage *p){(void)o;(void)r;(void)n;(void)l;(void)p;return 0;}
static int select_row(uint64_t o,uint64_t p,size_t i,PaiaMixedSelection *s){(void)o;(void)p;(void)i;(void)s;return 0;}
static void free_selection(PaiaMixedSelection *s){(void)s;}
static int commit(uint64_t o,const PaiaMixedPart *p,size_t n,size_t l,char **s){(void)o;(void)p;(void)n;(void)l;(void)s;return 0;}
static void free_text(char *s){(void)s;}
static void forget(uint64_t o,uint64_t p){(void)o;(void)p;}
static int adopt(uint64_t o,uint64_t s,PaiaMixedImport *i){(void)o;(void)s;(void)i;return 0;}
int main(void){
    PaiaMixedAPI valid={sizeof(PaiaMixedAPI),PAIA_MIXED_ABI,open_owner,close_owner,close_all,project,select_row,free_selection,commit,free_text,forget,adopt};
    assert(paia_rime_extension_capabilities()==0);assert(!paia_rime_mixed_api_compatible(NULL));assert(paia_rime_mixed_api_compatible(&valid));
    uint32_t truncated=0;assert(!paia_rime_mixed_api_compatible(&truncated));
    PaiaMixedAPI bad=valid;bad.data_size--;assert(!paia_rime_mixed_api_compatible(&bad));bad=valid;bad.abi++;assert(!paia_rime_mixed_api_compatible(&bad));
#define REJECT(field) do{bad=valid;bad.field=NULL;assert(!paia_rime_mixed_api_compatible(&bad));}while(0)
    REJECT(open);REJECT(close);REJECT(close_all);REJECT(project);REJECT(select);REJECT(free_selection);REJECT(commit);REJECT(free_text);REJECT(forget);REJECT(adopt);
    puts("CANDIDATE_ABI_SIMULATED short/missing/wrong-version tables rejected; no loaded capability claimed");return 0;
}
