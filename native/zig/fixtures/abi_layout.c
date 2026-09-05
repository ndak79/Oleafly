#include <stddef.h>

#include "texflow_abi.h"

_Static_assert(sizeof(texflow_abi_version_t) == 12, "ABI version size changed");
_Static_assert(_Alignof(texflow_abi_version_t) == 4, "ABI version alignment changed");
_Static_assert(offsetof(texflow_abi_version_t, major) == 0, "major offset changed");
_Static_assert(offsetof(texflow_abi_version_t, minor) == 4, "minor offset changed");
_Static_assert(offsetof(texflow_abi_version_t, patch) == 8, "patch offset changed");
