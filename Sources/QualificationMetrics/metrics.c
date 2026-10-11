#include "qualification_metrics.h"
#include <mach/mach.h>
#include <sys/resource.h>
uint64_t paia_qualification_current_rss(void) {
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count=MACH_TASK_BASIC_INFO_COUNT;
    if(task_info(mach_task_self(),MACH_TASK_BASIC_INFO,(task_info_t)&info,&count)!=KERN_SUCCESS)return 0;
    return info.resident_size;
}
uint64_t paia_qualification_peak_rss(void) {
    struct rusage value;if(getrusage(RUSAGE_SELF,&value))return 0;
    return (uint64_t)value.ru_maxrss; // Darwin bytes, not Linux KiB.
}
uint64_t paia_qualification_cpu_ns(void) {
    struct rusage value;if(getrusage(RUSAGE_SELF,&value))return 0;
    return ((uint64_t)value.ru_utime.tv_sec+(uint64_t)value.ru_stime.tv_sec)*1000000000ULL+
           ((uint64_t)value.ru_utime.tv_usec+(uint64_t)value.ru_stime.tv_usec)*1000ULL;
}
