#ifndef PAIA_RIME_H
#define PAIA_RIME_H
#include <stddef.h>
#include <stdint.h>
#include "paia_g01.h"
#include "paia_mixed.h"
// All engine calls, including initialization and lifetime, use one process-wide mutex.
// Return codes carry no input text. No callbacks, network or body logging.
#define PAIA_MAX_CANDIDATES 64
#define PAIA_TEXT_LIMIT 16384
#define PAIA_RAW_LIMIT 4096
typedef struct {
    char *raw, *preedit, *commit;
    char **candidates;
    size_t caret_utf8;
    uint64_t engine_nanoseconds, copy_nanoseconds;
    int preedit_caret_utf8, selection_start_utf8, selection_end_utf8;
    int page, highlighted, has_more, count, handled;
} PaiaRimeSnapshot;
enum { PAIA_OK=0, PAIA_UNAVAILABLE=1, PAIA_ABI=2, PAIA_DEPLOY=3,
       PAIA_SESSION=4, PAIA_BOUNDS=5, PAIA_ALLOCATION=6, PAIA_BUSY=7 };
int paia_rime_open(const char *library, const char *shared, const char *isolated_user);
// Validated precompiled resources only: no deployer initialization/maintenance,
// and named deploy is disabled for the lifetime of this runtime.
int paia_rime_open_precompiled(const char *library, const char *shared, const char *isolated_user);
uint64_t paia_rime_deployment_calls(void);
// Independent actual loaded-table capabilities: bit 0 G01, bit 1 mixed owner.
unsigned paia_rime_extension_capabilities(void);
int paia_rime_mixed_api_compatible(const void *table);
void paia_rime_close(void);
uint64_t paia_rime_start_session(void);
void paia_rime_end_session(uint64_t session);
// Actions: 0 read/consume, 1 process key, 2 select current-page index, 3 clear,
// 4 select absolute engine index (validated by caller snapshot), 5 explicit engine commit,
// 6 explicitly arm an idle verified-extension session for one retained composition.
int paia_rime_step(uint64_t session, int action, int key, int modifiers, PaiaRimeSnapshot *out);
void paia_rime_free_snapshot(PaiaRimeSnapshot *snapshot);
// ABI guard is also directly exercised with short/missing function tables.
int paia_rime_api_compatible(const void *table);
#endif
