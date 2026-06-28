// Always use english in comments
#pragma once

// Import the Opus C API exposed by the binary target's module
// Angle include works because SPM provides the module headers to dependents
#include <opus.h>

#ifdef __cplusplus
extern "C" {
#endif

// SET wrappers
int opus_enc_set_complexity(OpusEncoder* st, int v);
int opus_enc_set_signal(OpusEncoder* st, int v);
int opus_enc_set_vbr(OpusEncoder* st, int v);
int opus_enc_set_vbr_constraint(OpusEncoder* st, int v);
int opus_enc_set_inband_fec(OpusEncoder* st, int v);
int opus_enc_set_dtx(OpusEncoder* st, int v);
int opus_enc_set_packet_loss_perc(OpusEncoder* st, int v);
int opus_enc_set_bitrate(OpusEncoder* st, opus_int32 v);
int opus_enc_set_bandwidth(OpusEncoder* st, int v);
int opus_enc_set_max_bandwidth(OpusEncoder* st, int v);

// GET wrappers (so tests can assert)
int opus_enc_get_complexity(OpusEncoder* st, int* out);
int opus_enc_get_signal(OpusEncoder* st, int* out);
int opus_enc_get_vbr(OpusEncoder* st, int* out);
int opus_enc_get_vbr_constraint(OpusEncoder* st, int* out);
int opus_enc_get_inband_fec(OpusEncoder* st, int* out);
int opus_enc_get_dtx(OpusEncoder* st, int* out);
int opus_enc_get_packet_loss_perc(OpusEncoder* st, int* out);
int opus_enc_get_bitrate(OpusEncoder* st, opus_int32* out);
int opus_enc_get_bandwidth(OpusEncoder* st, int* out);
int opus_enc_get_max_bandwidth(OpusEncoder* st, int* out);

#ifdef __cplusplus
}
#endif