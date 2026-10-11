#ifndef PAIA_QUALIFICATION_METRICS_H
#define PAIA_QUALIFICATION_METRICS_H
#include <stdint.h>
uint64_t paia_qualification_current_rss(void);
uint64_t paia_qualification_peak_rss(void);
uint64_t paia_qualification_cpu_ns(void);
#endif
