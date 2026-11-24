// The part of the Swift runtime's C interface deslop calls. The runtime is
// linked into every Swift program, so these resolve against it at link time.

#ifndef CSWIFTRUNTIME_H
#define CSWIFTRUNTIME_H

#include <stddef.h>
#include <stdint.h>

// Demangles the `mangledNameLength` bytes at `mangledName`. With a null
// `outputBuffer`, it returns a buffer it allocates with `malloc`, which the
// caller frees; it returns null for a name that is not a Swift mangling.
char *_Nullable swift_demangle(const char *_Nonnull mangledName, size_t mangledNameLength,
                               char *_Nullable outputBuffer, size_t *_Nullable outputBufferSize,
                               uint32_t flags);

#endif
