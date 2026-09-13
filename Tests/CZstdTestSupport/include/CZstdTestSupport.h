#ifndef MGB_CZSTD_TEST_SUPPORT_H
#define MGB_CZSTD_TEST_SUPPORT_H

#include <stddef.h>
#include <stdint.h>

enum {
  MGB_ZSTD_TEST_UNKNOWN_CONTENT_SIZE = 1u << 0,
  MGB_ZSTD_TEST_CHECKSUM = 1u << 1,
  MGB_ZSTD_TEST_DICTIONARY = 1u << 2,
  MGB_ZSTD_TEST_RAW_DICTIONARY = 1u << 3
};

typedef struct MGBZstdTestBuffer {
  uint8_t *bytes;
  size_t size;
} MGBZstdTestBuffer;

int32_t mgb_zstd_test_compress(
    const uint8_t *input,
    size_t input_size,
    uint32_t flags,
    uint32_t window_log,
    MGBZstdTestBuffer *output);

void mgb_zstd_test_buffer_destroy(MGBZstdTestBuffer *buffer);

int32_t mgb_zstd_test_frame_window_size(
    const uint8_t *input,
    size_t input_size,
    uint64_t *window_size);

#endif
