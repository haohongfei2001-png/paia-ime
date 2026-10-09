#ifndef PAIA_G01_H
#define PAIA_G01_H
#include <stdint.h>
#include <stddef.h>
#define PAIA_G01_ABI 1
#define PAIA_G01_MAX_ANCHORS 256
#define PAIA_G01_MAX_SEARCH 2048
typedef struct {size_t start_utf8,end_utf8,index;char *text;} PaiaG01Span;
typedef struct {char *raw,*preview;PaiaG01Span *items;size_t count;int complete;} PaiaG01List;
typedef struct {uint64_t session;PaiaG01List result;size_t examined;int status;} PaiaG01Trial;
enum {PG_OK=0,PG_CONFLICT=20,PG_INCOMPLETE=21,PG_UNSUPPORTED=22,PG_INVALID=23,PG_ENGINE=24};
// Only the CRimeShim owner calls these function pointers, under its global mutex.
typedef struct {
 uint32_t data_size,abi;
 int (*initialize)(const void *rime_api);
 int (*anchors)(uint64_t id,PaiaG01List *out);
 int (*candidates)(uint64_t id,size_t limit,PaiaG01List *out);
 int (*prepare)(uint64_t source,size_t target,const char *replacement_raw,const char *surface,size_t limit,PaiaG01Trial *out);
 void (*free_list)(PaiaG01List *list);
} PaiaG01API;
// Public shim functions. None loads code or resources on a key event.
int paia_rime_enable_g01(const char *verified_extension);
int paia_rime_deploy_named(const char *schema);
uint64_t paia_rime_start_named(const char *schema,int deferred_commit);
int paia_rime_g01_anchors(uint64_t id,PaiaG01List *out);
int paia_rime_g01_candidates(uint64_t id,size_t limit,PaiaG01List *out);
int paia_rime_g01_prepare(uint64_t id,size_t target,const char *replacement,const char *surface,size_t limit,PaiaG01Trial *out);
void paia_rime_g01_free_list(PaiaG01List *list);
#endif
