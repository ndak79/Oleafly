#ifndef TEXFLOW_ABI_H
#define TEXFLOW_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct texflow_abi_version_t {
    uint32_t major;
    uint32_t minor;
    uint32_t patch;
} texflow_abi_version_t;

int32_t texflow_abi_get_version(texflow_abi_version_t *out);
/* Returns the two's-complement i64 sum modulo 2^64. */
int64_t texflow_abi_add(int64_t a, int64_t b);

#ifdef __cplusplus
}
#endif

#endif
