#ifndef PAIA_MIXED_H
#define PAIA_MIXED_H
#include "paia_g01.h"
#define PAIA_MIXED_ABI 1
// Independent, optional table; the existing G01 ABI is unchanged. Chinese proof
// tokens are issued only after real selection and belong to one opaque owner.
typedef struct {uint64_t projection;PaiaG01List result;} PaiaMixedPage;
typedef struct {uint64_t proof;size_t start_utf8,end_utf8;char *surface;} PaiaMixedSelection;
typedef struct {const char *source;size_t source_bytes;uint64_t proof;} PaiaMixedPart; // proof==0: explicitly literal
// These functions run only under CRimeShim's process owner mutex.
typedef struct {
 uint32_t data_size,abi;
 int (*open)(uint64_t source,uint64_t *owner);
 void (*close)(uint64_t owner);
 void (*close_all)(void);
 int (*project)(uint64_t owner,const char *raw,size_t raw_bytes,size_t limit,PaiaMixedPage *out);
 int (*select)(uint64_t owner,uint64_t projection,size_t index,PaiaMixedSelection *out);
 void (*free_selection)(PaiaMixedSelection *out);
 int (*commit)(uint64_t owner,const PaiaMixedPart *parts,size_t count,size_t limit,char **out);
 void (*free_text)(char *text);
 void (*forget)(uint64_t owner,uint64_t proof);
} PaiaMixedAPI;
int paia_rime_mixed_open(uint64_t source,uint64_t *owner);
void paia_rime_mixed_close(uint64_t owner);
int paia_rime_mixed_project(uint64_t owner,const char *raw,size_t raw_bytes,size_t limit,PaiaMixedPage *out);
int paia_rime_mixed_select(uint64_t owner,uint64_t projection,size_t index,PaiaMixedSelection *out);
void paia_rime_mixed_free_selection(PaiaMixedSelection *out);
int paia_rime_mixed_commit(uint64_t owner,const PaiaMixedPart *parts,size_t count,size_t limit,char **out);
void paia_rime_mixed_free_text(char *text);
void paia_rime_mixed_forget(uint64_t owner,uint64_t proof);
#endif
