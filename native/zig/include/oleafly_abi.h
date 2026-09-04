#ifndef OLEAFLY_ABI_H
#define OLEAFLY_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct oleafly_abi_version_t {
    uint32_t major;
    uint32_t minor;
    uint32_t patch;
} oleafly_abi_version_t;

int32_t oleafly_abi_get_version(oleafly_abi_version_t *out);
/* Returns the two's-complement i64 sum modulo 2^64. */
int64_t oleafly_abi_add(int64_t a, int64_t b);

#ifdef __cplusplus
}
#endif

#endif
