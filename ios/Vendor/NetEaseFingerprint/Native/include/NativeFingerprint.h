#ifndef INKFLOW_NATIVE_FINGERPRINT_H
#define INKFLOW_NATIVE_FINGERPRINT_H
#include <stddef.h>
#include <stdint.h>

// Mono float PCM at 8 kHz. Returns 0 on success, 1 for silence, negative on error.
// No input or output memory is retained after the call.
int inkflow_fingerprint(const float *samples, size_t count,
                        uint8_t *output, size_t capacity, size_t *length);
#endif
