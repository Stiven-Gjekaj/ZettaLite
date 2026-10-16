// The changes of ZettaLite to the default configuration of mbedTLS.

// iOS 6 has no clock_gettime. ms_time.c gives mbedtls_ms_time.
#define MBEDTLS_PLATFORM_MS_TIME_ALT
