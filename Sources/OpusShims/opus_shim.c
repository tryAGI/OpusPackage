// Always use english in comments
#include "opus_shim.h"

// SET
int opus_enc_set_complexity(OpusEncoder* st, int v){return opus_encoder_ctl(st, OPUS_SET_COMPLEXITY(v));}
int opus_enc_set_signal(OpusEncoder* st, int v){return opus_encoder_ctl(st, OPUS_SET_SIGNAL(v));}
int opus_enc_set_vbr(OpusEncoder* st, int v){return opus_encoder_ctl(st, OPUS_SET_VBR(v));}
int opus_enc_set_vbr_constraint(OpusEncoder* st, int v){return opus_encoder_ctl(st, OPUS_SET_VBR_CONSTRAINT(v));}
int opus_enc_set_inband_fec(OpusEncoder* st, int v){return opus_encoder_ctl(st, OPUS_SET_INBAND_FEC(v));}
int opus_enc_set_dtx(OpusEncoder* st, int v){return opus_encoder_ctl(st, OPUS_SET_DTX(v));}
int opus_enc_set_packet_loss_perc(OpusEncoder* st, int v){return opus_encoder_ctl(st, OPUS_SET_PACKET_LOSS_PERC(v));}
int opus_enc_set_bitrate(OpusEncoder* st, opus_int32 v){return opus_encoder_ctl(st, OPUS_SET_BITRATE(v));}

// GET
int opus_enc_get_complexity(OpusEncoder* st, int* out){return opus_encoder_ctl(st, OPUS_GET_COMPLEXITY(out));}
int opus_enc_get_signal(OpusEncoder* st, int* out){return opus_encoder_ctl(st, OPUS_GET_SIGNAL(out));}
int opus_enc_get_vbr(OpusEncoder* st, int* out){return opus_encoder_ctl(st, OPUS_GET_VBR(out));}
int opus_enc_get_vbr_constraint(OpusEncoder* st, int* out){return opus_encoder_ctl(st, OPUS_GET_VBR_CONSTRAINT(out));}
int opus_enc_get_inband_fec(OpusEncoder* st, int* out){return opus_encoder_ctl(st, OPUS_GET_INBAND_FEC(out));}
int opus_enc_get_dtx(OpusEncoder* st, int* out){return opus_encoder_ctl(st, OPUS_GET_DTX(out));}
int opus_enc_get_packet_loss_perc(OpusEncoder* st, int* out){return opus_encoder_ctl(st, OPUS_GET_PACKET_LOSS_PERC(out));}
int opus_enc_get_bitrate(OpusEncoder* st, opus_int32* out){return opus_encoder_ctl(st, OPUS_GET_BITRATE(out));}

// Bandwidth control
int opus_enc_set_bandwidth(OpusEncoder* st, int v){return opus_encoder_ctl(st, OPUS_SET_BANDWIDTH(v));}
int opus_enc_set_max_bandwidth(OpusEncoder* st, int v){return opus_encoder_ctl(st, OPUS_SET_MAX_BANDWIDTH(v));}
int opus_enc_get_bandwidth(OpusEncoder* st, int* out){return opus_encoder_ctl(st, OPUS_GET_BANDWIDTH(out));}
int opus_enc_get_max_bandwidth(OpusEncoder* st, int* out){return opus_encoder_ctl(st, OPUS_GET_MAX_BANDWIDTH(out));}