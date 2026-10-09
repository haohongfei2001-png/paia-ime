#include "paia_rime.h"
#include "rime_api.h"
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>
#include <time.h>
static uint64_t monotonic_ns(void) {
    struct timespec t;
    return clock_gettime(CLOCK_MONOTONIC,&t)==0 ? (uint64_t)t.tv_sec*1000000000ULL+(uint64_t)t.tv_nsec : 0;
}
static pthread_mutex_t owner = PTHREAD_MUTEX_INITIALIZER;
static RimeApi *api;
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
      HAS(a, get_version) && HAS(a, select_candidate_on_current_page);
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
int paia_rime_open(const char *library, const char *shared, const char *isolated_user) {
    pthread_mutex_lock(&owner);
    int rc = PAIA_UNAVAILABLE;
    if (api) { rc = PAIA_BUSY; goto done; }
    if (!library || !shared || !isolated_user) goto done;
    library_handle = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    if (!library_handle) goto done;
    RimeApi *(*get_api)(void) = (RimeApi *(*)(void))dlsym(library_handle, "rime_get_api");
    api = get_api ? get_api() : NULL;
    if (!paia_rime_api_compatible(api) || strcmp(api->get_version(), "1.16.0")) { rc = PAIA_ABI; api = NULL; goto fail; }
    shared_path = strdup(shared); user_path = strdup(isolated_user);
    if (!shared_path || !user_path) { rc=PAIA_ALLOCATION; api=NULL; goto fail; }
    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir=shared_path; traits.user_data_dir=user_path;
    traits.distribution_name="PAIA A1 isolated lab"; traits.distribution_code_name="paia_a1";
    traits.distribution_version="0.1.0"; traits.app_name="rime.paia_a1";
    traits.min_log_level=3; traits.log_dir="";
    api->setup(&traits); api->initialize(&traits); api->deployer_initialize(&traits);
    // One declared schema, compiled before any session or key. Never call deploy on the hot path.
    size_t n = strlen(shared_path)+sizeof("/paia_a1.schema.yaml");
    char *schema = malloc(n);
    if (!schema) { rc=PAIA_ALLOCATION; goto finalize; }
    snprintf(schema, n, "%s/paia_a1.schema.yaml", shared_path);
    int deployed=api->deploy_schema(schema); free(schema);
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
void paia_rime_close(void) {
    pthread_mutex_lock(&owner);
    if (api) { api->cleanup_all_sessions(); api->finalize(); api=NULL; }
    // Keep loaded code resident: some upstream dependency static destructors may outlive finalize.
    // A process may initialize only one runtime in the Swift owner; no runtime hot reload in A1.
    free(shared_path); free(user_path); shared_path=NULL; user_path=NULL;
    pthread_mutex_unlock(&owner);
}
uint64_t paia_rime_start_session(void) {
    pthread_mutex_lock(&owner);
    RimeSessionId id=api ? api->create_session() : 0;
    if (id && !api->select_schema(id, "paia_a1")) { api->destroy_session(id); id=0; }
    if (id) { api->set_option(id, "ascii_mode", False); api->set_option(id, "_no_learning", True); }
    pthread_mutex_unlock(&owner); return id;
}
void paia_rime_end_session(uint64_t id) {
    pthread_mutex_lock(&owner); if (api && api->find_session(id)) api->destroy_session(id); pthread_mutex_unlock(&owner);
}
static int snapshot(RimeSessionId id, PaiaRimeSnapshot *out) {
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
    uint64_t engine_begin=monotonic_ns();
    if (action==1) out->handled=api->process_key(id,key,modifiers);
    else if (action==2) {
        if (key<0 || key>=PAIA_MAX_CANDIDATES) { rc=PAIA_BOUNDS; goto done; }
        RIME_STRUCT(RimeContext, current);
        if (!api->get_context(id,&current)) { rc=PAIA_SESSION; goto done; }
        int in_page=key<current.menu.num_candidates;
        api->free_context(&current);
        if (!in_page) { rc=PAIA_BOUNDS; goto done; }
        out->handled=api->select_candidate_on_current_page(id,(size_t)key);
    } else if (action==3) { api->clear_composition(id); out->handled=1; }
    else if (action!=0) { rc=PAIA_BOUNDS; goto done; }
    out->engine_nanoseconds=monotonic_ns()-engine_begin;
    uint64_t copy_begin=monotonic_ns();
    rc=snapshot(id,out);
    out->copy_nanoseconds=monotonic_ns()-copy_begin;
done:
    pthread_mutex_unlock(&owner);
    if (rc) paia_rime_free_snapshot(out);
    return rc;
}
