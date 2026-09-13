#include "CZstdTestSupport.h"

#include <stdlib.h>
#include <string.h>
#include <zdict.h>
#include <zstd.h>

#define MGB_SAMPLE_1 "manifest path object checksum payload version one alpha beta "
#define MGB_SAMPLE_2 "manifest path object checksum payload version two gamma delta "
#define MGB_SAMPLE_3 "chunk file directory reference compressed uncompressed epsilon "
#define MGB_SAMPLE_4 "diff patch deletion build source target manifest record zeta "

static size_t mgb_make_dictionary(uint8_t *dictionary, size_t capacity) {
  static const char samples[] =
      MGB_SAMPLE_1 MGB_SAMPLE_2 MGB_SAMPLE_3 MGB_SAMPLE_4;
  static const size_t sample_sizes[] = {
      sizeof(MGB_SAMPLE_1) - 1,
      sizeof(MGB_SAMPLE_2) - 1,
      sizeof(MGB_SAMPLE_3) - 1,
      sizeof(MGB_SAMPLE_4) - 1};
  static const char content[] =
      "manifest-object-reference-checksum-payload-version-path-chunk-diff";
  ZDICT_params_t parameters = {3, 0, 123456};
  return ZDICT_finalizeDictionary(
      dictionary,
      capacity,
      content,
      sizeof(content) - 1,
      samples,
      sample_sizes,
      4,
      parameters);
}

static size_t mgb_compress_streaming(
    ZSTD_CCtx *context,
    uint8_t *output,
    size_t output_capacity,
    const uint8_t *input,
    size_t input_size) {
  static const uint8_t empty = 0;
  ZSTD_inBuffer input_buffer = {
      input_size == 0 ? &empty : input, input_size, 0};
  ZSTD_outBuffer output_buffer = {output, output_capacity, 0};
  size_t status;
  do {
    size_t previous_input = input_buffer.pos;
    size_t previous_output = output_buffer.pos;
    status = ZSTD_compressStream2(
        context, &output_buffer, &input_buffer, ZSTD_e_continue);
    if (ZSTD_isError(status)) return status;
    if (previous_input == input_buffer.pos && previous_output == output_buffer.pos) {
      return SIZE_MAX;
    }
  } while (input_buffer.pos < input_buffer.size);
  ZSTD_inBuffer empty_input = {NULL, 0, 0};
  do {
    size_t previous_output = output_buffer.pos;
    status = ZSTD_compressStream2(
        context, &output_buffer, &empty_input, ZSTD_e_end);
    if (ZSTD_isError(status)) return status;
    if (status != 0 && previous_output == output_buffer.pos) {
      return SIZE_MAX;
    }
  } while (status != 0);
  return output_buffer.pos;
}

int32_t mgb_zstd_test_compress(
    const uint8_t *input,
    size_t input_size,
    uint32_t flags,
    uint32_t window_log,
    MGBZstdTestBuffer *output) {
  if (output == NULL || (input == NULL && input_size != 0)) return 1;
  output->bytes = NULL;
  output->size = 0;
  if ((flags & MGB_ZSTD_TEST_RAW_DICTIONARY) != 0) {
    static const char dictionary[] =
        "raw-manifest-dictionary-path-object-checksum-reference-payload-";
    ZSTD_CCtx *context = ZSTD_createCCtx();
    size_t capacity = ZSTD_compressBound(input_size);
    uint8_t *bytes = context == NULL ? NULL : malloc(capacity == 0 ? 1 : capacity);
    static const uint8_t empty = 0;
    size_t status = bytes == NULL
        ? SIZE_MAX
        : ZSTD_compress_usingDict(
              context,
              bytes,
              capacity == 0 ? 1 : capacity,
              input_size == 0 ? &empty : input,
              input_size,
              dictionary,
              sizeof(dictionary) - 1,
              3);
    ZSTD_freeCCtx(context);
    if (bytes == NULL || ZSTD_isError(status)) {
      free(bytes);
      return 3;
    }
    output->bytes = bytes;
    output->size = status;
    return 0;
  }
  if ((flags & MGB_ZSTD_TEST_DICTIONARY) != 0) {
    uint8_t dictionary[1024];
    size_t dictionary_size = mgb_make_dictionary(dictionary, sizeof(dictionary));
    if (ZDICT_isError(dictionary_size)) return 4;
    ZSTD_CDict *compiled = ZSTD_createCDict(dictionary, dictionary_size, 3);
    ZSTD_CCtx *context = ZSTD_createCCtx();
    if (compiled == NULL || context == NULL) {
      ZSTD_freeCCtx(context);
      ZSTD_freeCDict(compiled);
      return 2;
    }
    size_t capacity = ZSTD_compressBound(input_size);
    uint8_t *bytes = malloc(capacity == 0 ? 1 : capacity);
    static const uint8_t empty = 0;
    size_t status = bytes == NULL
        ? ZSTD_error_memory_allocation
        : ZSTD_compress_usingCDict(
              context,
              bytes,
              capacity == 0 ? 1 : capacity,
              input_size == 0 ? &empty : input,
              input_size,
              compiled);
    ZSTD_freeCCtx(context);
    ZSTD_freeCDict(compiled);
    if (bytes == NULL || ZSTD_isError(status)) {
      free(bytes);
      return 3;
    }
    output->bytes = bytes;
    output->size = status;
    return 0;
  }
  ZSTD_CCtx *context = ZSTD_createCCtx();
  if (context == NULL) return 2;
  size_t status = ZSTD_CCtx_setParameter(
      context,
      ZSTD_c_contentSizeFlag,
      (flags & MGB_ZSTD_TEST_UNKNOWN_CONTENT_SIZE) == 0);
  if (!ZSTD_isError(status)) {
    status = ZSTD_CCtx_setParameter(
        context, ZSTD_c_checksumFlag, (flags & MGB_ZSTD_TEST_CHECKSUM) != 0);
  }
  if (!ZSTD_isError(status) && window_log != 0) {
    status = ZSTD_CCtx_setParameter(context, ZSTD_c_windowLog, (int)window_log);
  }
  int streaming = window_log != 0 || (flags & MGB_ZSTD_TEST_UNKNOWN_CONTENT_SIZE) != 0;
  if (!ZSTD_isError(status) && streaming) {
    status = ZSTD_CCtx_setPledgedSrcSize(context, ZSTD_CONTENTSIZE_UNKNOWN);
  }
  size_t capacity = ZSTD_compressBound(input_size);
  if (streaming && capacity <= SIZE_MAX - ZSTD_CStreamOutSize()) {
    capacity += ZSTD_CStreamOutSize();
  }
  uint8_t *bytes = ZSTD_isError(status) ? NULL : malloc(capacity == 0 ? 1 : capacity);
  if (bytes == NULL) {
    ZSTD_freeCCtx(context);
    return 2;
  }
  static const uint8_t empty = 0;
  status = streaming
      ? mgb_compress_streaming(
            context,
            bytes,
            capacity == 0 ? 1 : capacity,
            input,
            input_size)
      : ZSTD_compress2(
            context,
            bytes,
            capacity == 0 ? 1 : capacity,
            input_size == 0 ? &empty : input,
            input_size);
  ZSTD_freeCCtx(context);
  if (ZSTD_isError(status)) {
    free(bytes);
    return 3;
  }
  output->bytes = bytes;
  output->size = status;
  return 0;
}

void mgb_zstd_test_buffer_destroy(MGBZstdTestBuffer *buffer) {
  if (buffer == NULL) return;
  free(buffer->bytes);
  buffer->bytes = NULL;
  buffer->size = 0;
}

int32_t mgb_zstd_test_frame_window_size(
    const uint8_t *input,
    size_t input_size,
    uint64_t *window_size) {
  if (input == NULL || window_size == NULL) return 1;
  ZSTD_frameHeader header;
  size_t status = ZSTD_getFrameHeader(&header, input, input_size);
  if (ZSTD_isError(status) || status != 0) return 2;
  *window_size = header.windowSize;
  return 0;
}
