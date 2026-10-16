// mbedtls_ms_time for iOS 6, which has no clock_gettime. It uses the
// monotonic clock of the Mach kernel.

#include <mach/mach_time.h>
#include "mbedtls/platform_time.h"

mbedtls_ms_time_t mbedtls_ms_time(void) {
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0) mach_timebase_info(&timebase);
    uint64_t nanoseconds = mach_absolute_time() * timebase.numer / timebase.denom;
    return (mbedtls_ms_time_t)(nanoseconds / 1000000);
}
