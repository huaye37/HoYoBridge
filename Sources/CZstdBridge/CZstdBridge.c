#include "CZstdBridge.h"

#include <stdlib.h>
#include <zstd.h>

struct MGBZstdDecoder {
  ZSTD_DStream *stream;
};

static int mgb_has_standard_magic(const uint8_t *input, size_t input_size) {
  return input_size >= 4 && input[0] == 0x28 && input[1] == 0xB5 &&
      input[2] == 0x2F && input[3] == 0xFD;
}

MGBZstdStatus mgb_zstd_probe(
    const uint8_t *input,
    size_t input_size,
    MGBZstdFrameProbe *probe) {
  if (input == NULL || probe == NULL || !mgb_has_standard_magic(input, input_size)) {
    return MGB_ZSTD_STATUS_INVALID_FRAME;
  }
  unsigned long long content_size = ZSTD_getFrameContentSize(input, input_size);
  if (content_size == ZSTD_CONTENTSIZE_ERROR) {
    return MGB_ZSTD_STATUS_INVALID_FRAME;
  }
  probe->content_size_known = content_size != ZSTD_CONTENTSIZE_UNKNOWN;
  probe->content_size = probe->content_size_known ? (uint64_t)content_size : 0;
  probe->dictionary_id = ZSTD_getDictID_fromFrame(input, input_size);
  return MGB_ZSTD_STATUS_OK;
}

MGBZstdStatus mgb_zstd_decoder_create(
    uint32_t maximum_window_log,
    MGBZstdDecoder **decoder) {
  if (decoder == NULL || maximum_window_log < 10 || maximum_window_log > 24) {
    return MGB_ZSTD_STATUS_INVALID_ARGUMENT;
  }
  *decoder = NULL;
  MGBZstdDecoder *result = calloc(1, sizeof(*result));
  if (result == NULL) return MGB_ZSTD_STATUS_OUT_OF_MEMORY;
  result->stream = ZSTD_createDStream();
  if (result->stream == NULL) {
    free(result);
    return MGB_ZSTD_STATUS_OUT_OF_MEMORY;
  }
  size_t status = ZSTD_initDStream(result->stream);
  if (!ZSTD_isError(status)) {
    status = ZSTD_DCtx_setParameter(
        result->stream, ZSTD_d_windowLogMax, (int)maximum_window_log);
  }
  if (ZSTD_isError(status)) {
    ZSTD_freeDStream(result->stream);
    free(result);
    return MGB_ZSTD_STATUS_INVALID_ARGUMENT;
  }
  *decoder = result;
  return MGB_ZSTD_STATUS_OK;
}

MGBZstdStatus mgb_zstd_decoder_step(
    MGBZstdDecoder *decoder,
    const uint8_t *input,
    size_t input_size,
    size_t *input_consumed,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_produced) {
  if (decoder == NULL || decoder->stream == NULL || input_consumed == NULL ||
      output == NULL || output_capacity == 0 || output_produced == NULL ||
      (input == NULL && input_size != 0)) {
    return MGB_ZSTD_STATUS_INVALID_ARGUMENT;
  }
  *input_consumed = 0;
  *output_produced = 0;
  ZSTD_inBuffer input_buffer = {input, input_size, 0};
  ZSTD_outBuffer output_buffer = {output, output_capacity, 0};
  size_t status = ZSTD_decompressStream(
      decoder->stream, &output_buffer, &input_buffer);
  *input_consumed = input_buffer.pos;
  *output_produced = output_buffer.pos;
  if (ZSTD_isError(status)) {
    switch (ZSTD_getErrorCode(status)) {
      case ZSTD_error_frameParameter_windowTooLarge:
        return MGB_ZSTD_STATUS_WINDOW_LIMIT;
      case ZSTD_error_dictionary_corrupted:
      case ZSTD_error_dictionary_wrong:
      case ZSTD_error_dictionaryCreation_failed:
        return MGB_ZSTD_STATUS_DICTIONARY_REQUIRED;
      case ZSTD_error_memory_allocation:
        return MGB_ZSTD_STATUS_OUT_OF_MEMORY;
      case ZSTD_error_noForwardProgress_destFull:
      case ZSTD_error_noForwardProgress_inputEmpty:
        return MGB_ZSTD_STATUS_NO_PROGRESS;
      case ZSTD_error_prefix_unknown:
      case ZSTD_error_version_unsupported:
      case ZSTD_error_frameParameter_unsupported:
      case ZSTD_error_corruption_detected:
      case ZSTD_error_checksum_wrong:
      case ZSTD_error_literals_headerWrong:
      case ZSTD_error_srcSize_wrong:
        return MGB_ZSTD_STATUS_INVALID_FRAME;
      default:
        return MGB_ZSTD_STATUS_DECODE_ERROR;
    }
  }
  if (status == 0) return MGB_ZSTD_STATUS_FRAME_FINISHED;
  if (input_buffer.pos == 0 && output_buffer.pos == 0) {
    return MGB_ZSTD_STATUS_NO_PROGRESS;
  }
  return MGB_ZSTD_STATUS_PROGRESS;
}

MGBZstdStatus mgb_zstd_decoder_destroy(MGBZstdDecoder *decoder) {
  if (decoder == NULL) return MGB_ZSTD_STATUS_INVALID_ARGUMENT;
  size_t status = ZSTD_freeDStream(decoder->stream);
  free(decoder);
  return ZSTD_isError(status) ? MGB_ZSTD_STATUS_DECODE_ERROR : MGB_ZSTD_STATUS_OK;
}
