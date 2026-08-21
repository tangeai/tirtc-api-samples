#ifndef TIRTC_API_SAMPLES_MEDIA_READER_H_
#define TIRTC_API_SAMPLES_MEDIA_READER_H_

#include <stddef.h>
#include <stdint.h>

enum SampleMediaKind {
    SAMPLE_MEDIA_AUDIO = 1,
    SAMPLE_MEDIA_VIDEO = 2,
};

struct SampleMediaFrame {
    enum SampleMediaKind kind;
    const uint8_t *data;
    size_t size;
    uint64_t offset_ms;
    int is_key_frame;
};

struct SampleMediaReader;

int sample_media_reader_open(
    struct SampleMediaReader **out_reader,
    const char *video_path,
    const char *audio_path,
    uint64_t duration_ms,
    char *error_message,
    size_t error_message_size
);

/* Returns 1 for a frame, 0 at the configured duration, and -1 on failure. */
int sample_media_reader_next(
    struct SampleMediaReader *reader,
    struct SampleMediaFrame *out_frame,
    char *error_message,
    size_t error_message_size
);

void sample_media_reader_close(struct SampleMediaReader *reader);

#endif
