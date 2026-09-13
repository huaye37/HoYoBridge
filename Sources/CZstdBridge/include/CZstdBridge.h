#ifndef MGB_CZSTD_BRIDGE_H
#define MGB_CZSTD_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum MGBZstdStatus {
  MGB_ZSTD_STATUS_OK = 0,
  MGB_ZSTD_STATUS_PROGRESS = 1,
  MGB_ZSTD_STATUS_FRAME_FINISHED = 2,
  MGB_ZSTD_STATUS_INVALID_ARGUMENT = 3,
  MGB_ZSTD_STATUS_INVALID_FRAME = 4,
  MGB_ZSTD_STATUS_OUT_OF_MEMORY = 5,
  MGB_ZSTD_STATUS_WINDOW_LIMIT = 6,
  MGB_ZSTD_STATUS_DECODE_ERROR = 7,
  MGB_ZSTD_STATUS_NO_PROGRESS = 8,
  MGB_ZSTD_STATUS_DICTIONARY_REQUIRED = 9
} MGBZstdStatus;

typedef struct MGBZstdFrameProbe {
  uint64_t content_size;
  uint32_t dictionary_id;
  uint8_t content_size_known;
} MGBZstdFrameProbe;

typedef struct MGBZstdDecoder MGBZstdDecoder;

MGBZstdStatus mgb_zstd_probe(
    const uint8_t *input,
    size_t input_size,
    MGBZstdFrameProbe *probe);

MGBZstdStatus mgb_zstd_decoder_create(
    uint32_t maximum_window_log,
    MGBZstdDecoder **decoder);

MGBZstdStatus mgb_zstd_decoder_step(
    MGBZstdDecoder *decoder,
    const uint8_t *input,
    size_t input_size,
    size_t *input_consumed,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_produced);

MGBZstdStatus mgb_zstd_decoder_destroy(MGBZstdDecoder *decoder);

#ifdef __cplusplus
}
#endif

#endif
