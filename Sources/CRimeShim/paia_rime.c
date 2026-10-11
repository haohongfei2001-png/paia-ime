#include "paia_rime.h"
#include "rime_api.h"
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>
#include <time.h>
uint64_t paia_rime_monotonic_nanoseconds(void) {
    struct timespec t;
    return clock_gettime(CLOCK_MONOTONIC,&t)==0 ? (uint64_t)t.tv_sec*1000000000ULL+(uint64_t)t.tv_nsec : 0;
}
static pthread_mutex_t owner = PTHREAD_MUTEX_INITIALIZER;
static RimeApi *api;
static PaiaG01API *g01;
static PaiaMixedAPI *mixed;
static size_t live_sessions;
static int precompiled_mode;
static uint64_t deployment_calls;
static PaiaRimeDiagnostics diagnostics;
static void *library_handle;
static char *shared_path, *user_path;
// Require the whole function pointer, not only its first byte. data_size excludes itself.
#define HAS(p, member) ((p) && (p)->data_size >= 0 &&     (size_t)(p)->data_size + sizeof((p)->data_size) >= offsetof(RimeApi, member) + sizeof((p)->member) && (p)->member)
int paia_rime_api_compatible(const void *table) {
    const RimeApi *a = table;
    return HAS(a, setup) && HAS(a, initialize) && HAS(a, finalize) &&
      HAS(a, deployer_initialize) && HAS(a, deploy_schema) && HAS(a, create_session) && HAS(a, find_session) &&
      HAS(a, destroy_session) && HAS(a, cleanup_all_sessions) && HAS(a, select_schema) &&
      HAS(a, process_key) && HAS(a, clear_composition) && HAS(a, get_input) &&
      HAS(a, get_caret_pos) && HAS(a, get_context) && HAS(a, free_context) &&
      HAS(a, get_commit) && HAS(a, free_commit) && HAS(a, set_option) &&
      HAS(a, get_version) && HAS(a, select_candidate_on_current_page) &&
      HAS(a, select_candidate) && HAS(a, commit_composition);
}
static int copy_text(char **dest, const char *src, size_t limit) {
    if (!src) src = "";
    size_t n = strnlen(src, limit + 1);
    if (n > limit) return PAIA_BOUNDS;
    *dest = malloc(n + 1);
    if (!*dest) return PAIA_ALLOCATION;
    memcpy(*dest, src, n + 1);
    return PAIA_OK;
}
void paia_rime_free_snapshot(PaiaRimeSnapshot *s) {
    if (!s) return;
    free(s->raw); free(s->preedit); free(s->commit);
    if (s->candidates) { for (int i=0; i<s->count; i++) free(s->candidates[i]); free(s->candidates); }
    memset(s, 0, sizeof(*s));
}
static int open_runtime(const char *library, const char *shared, const char *isolated_user, int precompiled) {
    pthread_mutex_lock(&owner);
    int rc = PAIA_UNAVAILABLE;
    if (api) { rc = PAIA_BUSY; goto done; }
    if (!library || !shared || !isolated_user) goto done;
    library_handle = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    if (!library_handle) goto done;
    RimeApi *(*get_api)(void) = (RimeApi *(*)(void))dlsym(library_handle, "rime_get_api");
    api = get_api ? get_api() : NULL;
    if (!paia_rime_api_compatible(api)) { rc=PAIA_ABI;api=NULL;goto fail; }
    const char *version=api->get_version();
    if (!version || strcmp(version,"1.16.0")) {rc=PAIA_ABI;api=NULL;goto fail;}
    shared_path = strdup(shared); user_path = strdup(isolated_user);
    if (!shared_path || !user_path) { rc=PAIA_ALLOCATION; api=NULL; goto fail; }
    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir=shared_path; traits.user_data_dir=user_path;
    traits.distribution_name="PAIA A1 isolated lab"; traits.distribution_code_name="paia_a1";
    traits.distribution_version="0.1.0"; traits.app_name="rime.paia_a1";
    traits.min_log_level=3; traits.log_dir="";
    api->setup(&traits); api->initialize(&traits);
    precompiled_mode = precompiled;
    if (precompiled) { rc=PAIA_OK; goto done; }
    api->deployer_initialize(&traits);
    // One declared schema, compiled before any session or key. Never call deploy on the hot path.
    size_t n = strlen(shared_path)+sizeof("/paia_a1.schema.yaml");
    char *schema = malloc(n);
    if (!schema) { rc=PAIA_ALLOCATION; goto finalize; }
    snprintf(schema, n, "%s/paia_a1.schema.yaml", shared_path);
    deployment_calls++; int deployed=api->deploy_schema(schema); free(schema);
    if (!deployed) { rc=PAIA_DEPLOY; goto finalize; }
    rc=PAIA_OK; goto done;
finalize:
    api->finalize(); api=NULL;
fail:
    if (library_handle) dlclose(library_handle);
    library_handle=NULL; free(shared_path); free(user_path); shared_path=NULL; user_path=NULL;
done:
    pthread_mutex_unlock(&owner); return rc;
}
int paia_rime_open(const char *library, const char *shared, const char *isolated_user) {
    return open_runtime(library,shared,isolated_user,0);
}
int paia_rime_open_precompiled(const char *library, const char *shared, const char *isolated_user) {
    return open_runtime(library,shared,isolated_user,1);
}
uint64_t paia_rime_deployment_calls(void) {
    pthread_mutex_lock(&owner);uint64_t count=deployment_calls;pthread_mutex_unlock(&owner);return count;
}
void paia_rime_diagnostics(PaiaRimeDiagnostics *out) {
    if(!out)return;
    pthread_mutex_lock(&owner);*out=diagnostics;out->live_sessions=live_sessions;pthread_mutex_unlock(&owner);
}
int paia_rime_learning_disabled(uint64_t id) {
    pthread_mutex_lock(&owner);
    int disabled=api && api->find_session(id) && HAS(api,get_option) && api->get_option(id,"_no_learning");
    pthread_mutex_unlock(&owner);return disabled;
}
void paia_rime_close(void) {
    pthread_mutex_lock(&owner);
    if (mixed) {mixed->close_all();mixed=NULL;}
    if (api) { api->cleanup_all_sessions(); api->finalize(); api=NULL; }
    // Keep loaded code resident: some upstream dependency static destructors may outlive finalize.
    // A process may initialize only one runtime in the Swift owner; no runtime hot reload in A1.
    free(shared_path); free(user_path); shared_path=NULL; user_path=NULL; g01=NULL; live_sessions=0;
    pthread_mutex_unlock(&owner);
}
uint64_t paia_rime_start_session(void) {
    pthread_mutex_lock(&owner);
    RimeSessionId id=api ? api->create_session() : 0;
    if (id && !api->select_schema(id, "paia_a1")) { api->destroy_session(id); id=0; }
    if (id) { api->set_option(id, "ascii_mode", False); api->set_option(id, "_no_learning", True); live_sessions++;diagnostics.sessions_created++; }
    pthread_mutex_unlock(&owner); return id;
}
void paia_rime_end_session(uint64_t id) {
    pthread_mutex_lock(&owner); if (api && api->find_session(id)) {api->destroy_session(id);if(live_sessions)live_sessions--;diagnostics.sessions_destroyed++;} pthread_mutex_unlock(&owner);
}
static int snapshot(RimeSessionId id, PaiaRimeSnapshot *out) {
    diagnostics.snapshots++;
    int rc=copy_text(&out->raw, api->get_input(id), PAIA_RAW_LIMIT);
    if (rc) return rc;
    out->caret_utf8=api->get_caret_pos(id);
    RIME_STRUCT(RimeCommit, commit);
    if (api->get_commit(id, &commit)) {
        rc=copy_text(&out->commit, commit.text, PAIA_TEXT_LIMIT);
        api->free_commit(&commit);
        if (rc) return rc; // Commit is consumed; never retry an unknown effect.
    }
    RIME_STRUCT(RimeContext, ctx);
    if (!api->get_context(id, &ctx)) return PAIA_SESSION;
    rc=copy_text(&out->preedit, ctx.composition.preedit, PAIA_TEXT_LIMIT);
    out->preedit_caret_utf8=ctx.composition.cursor_pos;
    out->selection_start_utf8=ctx.composition.sel_start; out->selection_end_utf8=ctx.composition.sel_end;
    out->page=ctx.menu.page_no; out->highlighted=ctx.menu.highlighted_candidate_index;
    out->has_more=!ctx.menu.is_last_page;
    if (!rc && (ctx.menu.num_candidates<0 || ctx.menu.num_candidates>PAIA_MAX_CANDIDATES ||
        (ctx.menu.num_candidates && !ctx.menu.candidates))) rc=PAIA_BOUNDS;
    if (!rc) {
        out->count=ctx.menu.num_candidates;
        if (out->count) {
            out->candidates=calloc((size_t)out->count, sizeof(char*));
            if (!out->candidates) rc=PAIA_ALLOCATION;
        }
        for (int i=0; !rc && i<out->count; i++) rc=copy_text(&out->candidates[i], ctx.menu.candidates[i].text, PAIA_TEXT_LIMIT);
    }
    api->free_context(&ctx);
    return rc;
}
int paia_rime_step(uint64_t id, int action, int key, int modifiers, PaiaRimeSnapshot *out) {
    if (!out) return PAIA_BOUNDS;
    memset(out,0,sizeof(*out));
    pthread_mutex_lock(&owner);
    int rc=PAIA_OK;
    if (!api || !api->find_session(id)) { rc=PAIA_SESSION; goto done; }
    uint64_t engine_begin=paia_rime_monotonic_nanoseconds();
    if (action==1) {diagnostics.keys++;out->handled=api->process_key(id,key,modifiers);}
    else if (action==2) {
        if (key<0 || key>=PAIA_MAX_CANDIDATES) { rc=PAIA_BOUNDS; goto done; }
        RIME_STRUCT(RimeContext, current);
        if (!api->get_context(id,&current)) { rc=PAIA_SESSION; goto done; }
        int in_page=key<current.menu.num_candidates;
        api->free_context(&current);
        if (!in_page) { rc=PAIA_BOUNDS; goto done; }
        diagnostics.selections++;out->handled=api->select_candidate_on_current_page(id,(size_t)key);
    } else if (action==3) { diagnostics.clears++;api->clear_composition(id); out->handled=1; }
    else if (action==4) {
        if(key<0 || key>=PAIA_G01_MAX_SEARCH) {rc=PAIA_BOUNDS;goto done;}
        diagnostics.selections++;out->handled=api->select_candidate(id,(size_t)key);
    } else if(action==5) out->handled=api->commit_composition(id);
    else if(action==6) {
        // Explicit idle-only arming, never library/resource loading on a key.
        const char *raw=api->get_input(id);
        RIME_STRUCT(RimeContext, current);
        if(!g01 || !raw || *raw || !api->get_context(id,&current)){rc=PAIA_BOUNDS;goto done;}
        int empty=current.composition.length==0;
        api->free_context(&current);
        if(!empty){rc=PAIA_BOUNDS;goto done;}
        api->set_option(id,"_auto_commit",False);out->handled=1;
    }
    else if (action!=0) { rc=PAIA_BOUNDS; goto done; }
    out->engine_nanoseconds=paia_rime_monotonic_nanoseconds()-engine_begin;
    uint64_t copy_begin=paia_rime_monotonic_nanoseconds();
    rc=snapshot(id,out);
    out->copy_nanoseconds=paia_rime_monotonic_nanoseconds()-copy_begin;
done:
    if(rc)diagnostics.failed_steps++;
    pthread_mutex_unlock(&owner);
    if (rc) paia_rime_free_snapshot(out);
    return rc;
}

static int valid_schema(const char *s) {
    if(!s || !*s || strlen(s)>80)return 0;
    for(const char *p=s;*p;p++)if(!((*p>='a'&&*p<='z')||(*p>='0'&&*p<='9')||*p=='_'))return 0;
    return 1;
}
int paia_rime_deploy_named(const char *schema) {
    pthread_mutex_lock(&owner);int rc=PAIA_DEPLOY;
    if(api && !precompiled_mode && !live_sessions && valid_schema(schema)) {
        size_t n=strlen(shared_path)+strlen(schema)+sizeof("/.schema.yaml");char *path=malloc(n);
        if(path) {snprintf(path,n,"%s/%s.schema.yaml",shared_path,schema);deployment_calls++;rc=api->deploy_schema(path)?PAIA_OK:PAIA_DEPLOY;free(path);}
    }
    pthread_mutex_unlock(&owner);return rc;
}
uint64_t paia_rime_start_named(const char *schema,int deferred) {
    pthread_mutex_lock(&owner);RimeSessionId id=0;
    if(api && valid_schema(schema)) {
        id=api->create_session();
        if(id && !api->select_schema(id,schema)){api->destroy_session(id);id=0;}
        if(id){api->set_option(id,"ascii_mode",False);api->set_option(id,"_no_learning",True);api->set_option(id,"_auto_commit",!deferred);live_sessions++;diagnostics.sessions_created++;}
    }
    pthread_mutex_unlock(&owner);return id;
}
int paia_rime_mixed_api_compatible(const void *table) {
    const PaiaMixedAPI *m=table;
    return m && m->data_size==sizeof(*m) && m->abi==PAIA_MIXED_ABI && m->open && m->close && m->close_all && m->project && m->select && m->free_selection && m->commit && m->free_text && m->forget && m->adopt;
}
unsigned paia_rime_extension_capabilities(void) {
    pthread_mutex_lock(&owner);unsigned result=(g01?1u:0u)|(mixed?2u:0u);pthread_mutex_unlock(&owner);return result;
}
int paia_rime_enable_g01(const char *path) {
    pthread_mutex_lock(&owner);int rc=PAIA_UNAVAILABLE;
    if(api && !live_sessions && path && !g01) {
        void *handle=dlopen(path,RTLD_NOW|RTLD_LOCAL);
        if(handle) {
            PaiaG01API *(*get_api)(void)=(PaiaG01API *(*)(void))dlsym(handle,"paia_g01_get_api");
            PaiaG01API *v=get_api?get_api():NULL;
            if(v && v->data_size==sizeof(*v) && v->abi==PAIA_G01_ABI && v->initialize && v->anchors && v->candidates && v->prepare && v->free_list && v->alternatives && v->free_alternatives && v->initialize(api)==PG_OK){
                g01=v;rc=PAIA_OK;
                PaiaMixedAPI *(*get_mixed)(void)=(PaiaMixedAPI *(*)(void))dlsym(handle,"paia_mixed_get_api");
                PaiaMixedAPI *m=get_mixed?get_mixed():NULL;
                if(paia_rime_mixed_api_compatible(m))mixed=m;
            }
            else dlclose(handle);
        }
    }
    pthread_mutex_unlock(&owner);return rc;
}
int paia_rime_g01_anchors(uint64_t id,PaiaG01List *out) {
    if(!out)return PG_INVALID;
    memset(out,0,sizeof(*out));
    pthread_mutex_lock(&owner);int rc=g01?g01->anchors(id,out):PAIA_UNAVAILABLE;pthread_mutex_unlock(&owner);return rc;
}
int paia_rime_g01_candidates(uint64_t id,size_t limit,PaiaG01List *out) {
    if(!out)return PG_INVALID;
    memset(out,0,sizeof(*out));
    pthread_mutex_lock(&owner);int rc=g01?g01->candidates(id,limit,out):PAIA_UNAVAILABLE;pthread_mutex_unlock(&owner);return rc;
}
int paia_rime_g01_prepare(uint64_t id,size_t target,const char *replacement,const char *surface,size_t limit,PaiaG01Trial *out) {
    if(!out)return PG_INVALID;
    memset(out,0,sizeof(*out));
    pthread_mutex_lock(&owner);int rc=g01?g01->prepare(id,target,replacement,surface,limit,out):PAIA_UNAVAILABLE;
    if(rc==PG_OK && out->session)live_sessions++;
    pthread_mutex_unlock(&owner);return rc;
}
void paia_rime_g01_free_list(PaiaG01List *list) {
    // ABI values contain only malloc-owned copies, never engine pointers. They
    // remain releasable after the runtime/table has closed.
    if(!list)return;
    free(list->raw);free(list->preview);
    if(list->items){for(size_t i=0;i<list->count;++i)free(list->items[i].text);free(list->items);}
    memset(list,0,sizeof(*list));
}

int paia_rime_g01_alternatives(uint64_t id,size_t target,const char *replacement,size_t limit,size_t max_rows,PaiaG01Alternatives *out) {
    if(!out)return PG_INVALID;
    memset(out,0,sizeof(*out));
    pthread_mutex_lock(&owner);int rc=g01?g01->alternatives(id,target,replacement,limit,max_rows,out):PAIA_UNAVAILABLE;
    pthread_mutex_unlock(&owner);return rc;
}
void paia_rime_g01_free_alternatives(PaiaG01Alternatives *out) {
    pthread_mutex_lock(&owner);if(g01)g01->free_alternatives(out);pthread_mutex_unlock(&owner);
}

int paia_rime_mixed_open(uint64_t source,uint64_t *out) {
    if(!out)return PG_INVALID;
    *out=0;pthread_mutex_lock(&owner);
    int rc=mixed?mixed->open(source,out):PG_UNSUPPORTED;pthread_mutex_unlock(&owner);return rc;
}
void paia_rime_mixed_close(uint64_t id){pthread_mutex_lock(&owner);if(mixed)mixed->close(id);pthread_mutex_unlock(&owner);}
int paia_rime_mixed_project(uint64_t id,const char *raw,size_t raw_bytes,size_t limit,PaiaMixedPage *out){
    if(!out)return PG_INVALID;
    memset(out,0,sizeof(*out));pthread_mutex_lock(&owner);
    int rc=mixed?mixed->project(id,raw,raw_bytes,limit,out):PG_UNSUPPORTED;pthread_mutex_unlock(&owner);return rc;
}
int paia_rime_mixed_select(uint64_t id,uint64_t projection,size_t index,PaiaMixedSelection *out){
    if(!out)return PG_INVALID;
    memset(out,0,sizeof(*out));pthread_mutex_lock(&owner);
    int rc=mixed?mixed->select(id,projection,index,out):PG_UNSUPPORTED;pthread_mutex_unlock(&owner);return rc;
}
void paia_rime_mixed_free_selection(PaiaMixedSelection *out){if(out){free(out->surface);memset(out,0,sizeof(*out));}}
int paia_rime_mixed_commit(uint64_t id,const PaiaMixedPart *parts,size_t count,size_t limit,char **out){
    if(!out)return PG_INVALID;
    *out=NULL;pthread_mutex_lock(&owner);
    int rc=mixed?mixed->commit(id,parts,count,limit,out):PG_UNSUPPORTED;pthread_mutex_unlock(&owner);return rc;
}
void paia_rime_mixed_free_text(char *text){free(text);}
void paia_rime_mixed_forget(uint64_t id,uint64_t proof){pthread_mutex_lock(&owner);if(mixed)mixed->forget(id,proof);pthread_mutex_unlock(&owner);}

int paia_rime_mixed_adopt(uint64_t id,uint64_t source,PaiaMixedImport *out){
    if(!out)return PG_INVALID;
    memset(out,0,sizeof(*out));pthread_mutex_lock(&owner);
    int rc=mixed?mixed->adopt(id,source,out):PG_UNSUPPORTED;pthread_mutex_unlock(&owner);return rc;
}
void paia_rime_mixed_free_import(PaiaMixedImport *out){
    if(!out)return;
    free(out->raw);
    if(out->anchors){for(size_t i=0;i<out->count;++i)free(out->anchors[i].surface);free(out->anchors);}
    memset(out,0,sizeof(*out));
}
