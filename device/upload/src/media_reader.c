#include "media_reader.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AUDIO_FRAME_BYTES 320U
#define AUDIO_FRAME_INTERVAL_MS 40U
#define VIDEO_FRAMES_PER_SECOND 15U
#define MAX_VIDEO_FRAME_BYTES (4U * 1024U * 1024U)

struct AnnexBReader {
    FILE *file;
    uint8_t *nal;
    size_t nal_size;
    size_t nal_capacity;
    size_t start_code_size;
    size_t pending_start_code_size;
};

struct VideoReader {
    struct AnnexBReader annex_b;
    uint8_t *frame;
    size_t frame_size;
    size_t frame_capacity;
    int frame_is_key;
    int held_nal;
};

struct SampleMediaReader {
    struct VideoReader video;
    FILE *audio_file;
    uint8_t audio_frame[AUDIO_FRAME_BYTES];
    size_t audio_frame_size;
    uint64_t duration_ms;
    uint64_t video_index;
    uint64_t audio_index;
    uint64_t video_offset_ms;
    uint64_t audio_offset_ms;
    int video_ready;
    int audio_ready;
    int video_done;
    int audio_done;
};

static void set_error(char *message, size_t message_size, const char *format, ...) {
    va_list arguments;

    if (message == NULL || message_size == 0) {
        return;
    }

    va_start(arguments, format);
    (void)vsnprintf(message, message_size, format, arguments);
    va_end(arguments);
}

static int reserve_bytes(
    uint8_t **buffer,
    size_t *capacity,
    size_t required,
    char *error_message,
    size_t error_message_size
) {
    size_t next_capacity;
    uint8_t *next_buffer;

    if (required > MAX_VIDEO_FRAME_BYTES) {
        set_error(
            error_message,
            error_message_size,
            "H.264 access unit exceeds the %u-byte sample limit",
            (unsigned)MAX_VIDEO_FRAME_BYTES
        );
        return -1;
    }
    if (*capacity >= required) {
        return 0;
    }

    next_capacity = *capacity == 0 ? 128U * 1024U : *capacity;
    while (next_capacity < required) {
        if (next_capacity > MAX_VIDEO_FRAME_BYTES / 2U) {
            next_capacity = MAX_VIDEO_FRAME_BYTES;
        } else {
            next_capacity *= 2U;
        }
    }

    next_buffer = (uint8_t *)realloc(*buffer, next_capacity);
    if (next_buffer == NULL) {
        set_error(error_message, error_message_size, "out of memory while reading H.264");
        return -1;
    }

    *buffer = next_buffer;
    *capacity = next_capacity;
    return 0;
}

static int append_bytes(
    uint8_t **buffer,
    size_t *size,
    size_t *capacity,
    const uint8_t *data,
    size_t data_size,
    char *error_message,
    size_t error_message_size
) {
    if (data_size > MAX_VIDEO_FRAME_BYTES - *size ||
        reserve_bytes(
            buffer,
            capacity,
            *size + data_size,
            error_message,
            error_message_size
        ) != 0) {
        return -1;
    }

    memcpy(*buffer + *size, data, data_size);
    *size += data_size;
    return 0;
}

static int append_zeroes(
    struct AnnexBReader *reader,
    size_t count,
    char *error_message,
    size_t error_message_size
) {
    static const uint8_t zeroes[16] = {0};

    while (count > 0) {
        size_t chunk = count < sizeof(zeroes) ? count : sizeof(zeroes);
        if (append_bytes(
                &reader->nal,
                &reader->nal_size,
                &reader->nal_capacity,
                zeroes,
                chunk,
                error_message,
                error_message_size
            ) != 0) {
            return -1;
        }
        count -= chunk;
    }
    return 0;
}

/* Returns one Annex-B NAL, preserving its three- or four-byte start code. */
static int annex_b_read_nal(
    struct AnnexBReader *reader,
    char *error_message,
    size_t error_message_size
) {
    int byte;
    size_t zero_count = 0;
    size_t start_code_size;
    uint8_t one = 1;

    reader->nal_size = 0;
    reader->start_code_size = 0;

    if (reader->pending_start_code_size != 0) {
        start_code_size = reader->pending_start_code_size;
        reader->pending_start_code_size = 0;
    } else {
        start_code_size = 0;
        while ((byte = fgetc(reader->file)) != EOF) {
            if (byte == 0) {
                ++zero_count;
                continue;
            }
            if (byte == 1 && zero_count >= 2) {
                start_code_size = zero_count >= 3 ? 4U : 3U;
                break;
            }
            zero_count = 0;
        }
        if (start_code_size == 0) {
            if (ferror(reader->file)) {
                set_error(error_message, error_message_size, "failed to read H.264 asset");
                return -1;
            }
            return 0;
        }
    }

    if (append_zeroes(reader, start_code_size - 1U, error_message, error_message_size) != 0 ||
        append_bytes(
            &reader->nal,
            &reader->nal_size,
            &reader->nal_capacity,
            &one,
            1,
            error_message,
            error_message_size
        ) != 0) {
        return -1;
    }
    reader->start_code_size = start_code_size;

    zero_count = 0;
    while ((byte = fgetc(reader->file)) != EOF) {
        uint8_t value;

        if (byte == 0) {
            ++zero_count;
            continue;
        }
        if (byte == 1 && zero_count >= 2) {
            reader->pending_start_code_size = zero_count >= 3 ? 4U : 3U;
            return reader->nal_size > reader->start_code_size ? 1 : -1;
        }
        if (append_zeroes(reader, zero_count, error_message, error_message_size) != 0) {
            return -1;
        }
        zero_count = 0;
        value = (uint8_t)byte;
        if (append_bytes(
                &reader->nal,
                &reader->nal_size,
                &reader->nal_capacity,
                &value,
                1,
                error_message,
                error_message_size
            ) != 0) {
            return -1;
        }
    }

    if (ferror(reader->file)) {
        set_error(error_message, error_message_size, "failed to read H.264 asset");
        return -1;
    }
    if (append_zeroes(reader, zero_count, error_message, error_message_size) != 0) {
        return -1;
    }
    return reader->nal_size > reader->start_code_size ? 1 : 0;
}

/* The bundled asset has one access-unit delimiter (NAL type 9) per frame. */
static int video_read_frame(
    struct VideoReader *reader,
    char *error_message,
    size_t error_message_size
) {
    int has_nal = 0;
    int first_nal = 1;

    reader->frame_size = 0;
    reader->frame_is_key = 0;

    for (;;) {
        int result;
        unsigned nal_type;

        if (reader->held_nal) {
            reader->held_nal = 0;
            result = 1;
        } else {
            result = annex_b_read_nal(
                &reader->annex_b,
                error_message,
                error_message_size
            );
        }
        if (result < 0) {
            if (error_message != NULL && error_message[0] == '\0') {
                set_error(error_message, error_message_size, "invalid H.264 Annex-B stream");
            }
            return -1;
        }
        if (result == 0) {
            return has_nal ? 1 : 0;
        }

        nal_type = reader->annex_b.nal[reader->annex_b.start_code_size] & 0x1fU;
        if (nal_type == 9U && has_nal) {
            reader->held_nal = 1;
            return 1;
        }
        if (first_nal && nal_type != 9U) {
            set_error(
                error_message,
                error_message_size,
                "video asset must contain an access-unit delimiter before every frame"
            );
            return -1;
        }
        first_nal = 0;

        if (append_bytes(
                &reader->frame,
                &reader->frame_size,
                &reader->frame_capacity,
                reader->annex_b.nal,
                reader->annex_b.nal_size,
                error_message,
                error_message_size
            ) != 0) {
            return -1;
        }
        has_nal = 1;
        if (nal_type == 5U) {
            reader->frame_is_key = 1;
        }
    }
}

static int prepare_video(
    struct SampleMediaReader *reader,
    char *error_message,
    size_t error_message_size
) {
    int result;

    if (reader->video_ready || reader->video_done) {
        return 0;
    }

    reader->video_offset_ms = reader->video_index * 1000U / VIDEO_FRAMES_PER_SECOND;
    if (reader->video_offset_ms > reader->duration_ms) {
        reader->video_done = 1;
        return 0;
    }

    result = video_read_frame(&reader->video, error_message, error_message_size);
    if (result <= 0) {
        if (result == 0) {
            set_error(error_message, error_message_size, "video asset ended before two minutes");
        }
        return -1;
    }
    if (reader->video_index == 0 && !reader->video.frame_is_key) {
        set_error(error_message, error_message_size, "video asset does not start with a key frame");
        return -1;
    }
    reader->video_ready = 1;
    return 0;
}

static int prepare_audio(
    struct SampleMediaReader *reader,
    char *error_message,
    size_t error_message_size
) {
    size_t bytes_read;

    if (reader->audio_ready || reader->audio_done) {
        return 0;
    }

    reader->audio_offset_ms = reader->audio_index * AUDIO_FRAME_INTERVAL_MS;
    if (reader->audio_offset_ms > reader->duration_ms) {
        reader->audio_done = 1;
        return 0;
    }

    bytes_read = fread(reader->audio_frame, 1, sizeof(reader->audio_frame), reader->audio_file);
    if (bytes_read != sizeof(reader->audio_frame)) {
        if (ferror(reader->audio_file)) {
            set_error(error_message, error_message_size, "failed to read G.711A asset");
        } else {
            set_error(error_message, error_message_size, "G.711A asset ended before two minutes");
        }
        return -1;
    }

    reader->audio_frame_size = bytes_read;
    reader->audio_ready = 1;
    return 0;
}

int sample_media_reader_open(
    struct SampleMediaReader **out_reader,
    const char *video_path,
    const char *audio_path,
    uint64_t duration_ms,
    char *error_message,
    size_t error_message_size
) {
    struct SampleMediaReader *reader;

    if (out_reader == NULL || video_path == NULL || audio_path == NULL || duration_ms == 0) {
        set_error(error_message, error_message_size, "invalid media reader arguments");
        return -1;
    }
    *out_reader = NULL;
    if (error_message != NULL && error_message_size != 0) {
        error_message[0] = '\0';
    }

    reader = (struct SampleMediaReader *)calloc(1, sizeof(*reader));
    if (reader == NULL) {
        set_error(error_message, error_message_size, "out of memory while opening assets");
        return -1;
    }

    reader->duration_ms = duration_ms;
    reader->video.annex_b.file = fopen(video_path, "rb");
    if (reader->video.annex_b.file == NULL) {
        set_error(error_message, error_message_size, "cannot open video asset: %s", video_path);
        sample_media_reader_close(reader);
        return -1;
    }
    reader->audio_file = fopen(audio_path, "rb");
    if (reader->audio_file == NULL) {
        set_error(error_message, error_message_size, "cannot open audio asset: %s", audio_path);
        sample_media_reader_close(reader);
        return -1;
    }

    *out_reader = reader;
    return 0;
}

int sample_media_reader_next(
    struct SampleMediaReader *reader,
    struct SampleMediaFrame *out_frame,
    char *error_message,
    size_t error_message_size
) {
    if (reader == NULL || out_frame == NULL) {
        set_error(error_message, error_message_size, "invalid media reader state");
        return -1;
    }
    if (error_message != NULL && error_message_size != 0) {
        error_message[0] = '\0';
    }

    if (prepare_video(reader, error_message, error_message_size) != 0 ||
        prepare_audio(reader, error_message, error_message_size) != 0) {
        return -1;
    }
    if (!reader->video_ready && !reader->audio_ready) {
        return 0;
    }

    if (reader->video_ready &&
        (!reader->audio_ready || reader->video_offset_ms <= reader->audio_offset_ms)) {
        out_frame->kind = SAMPLE_MEDIA_VIDEO;
        out_frame->data = reader->video.frame;
        out_frame->size = reader->video.frame_size;
        out_frame->offset_ms = reader->video_offset_ms;
        out_frame->is_key_frame = reader->video.frame_is_key;
        reader->video_ready = 0;
        ++reader->video_index;
    } else {
        out_frame->kind = SAMPLE_MEDIA_AUDIO;
        out_frame->data = reader->audio_frame;
        out_frame->size = reader->audio_frame_size;
        out_frame->offset_ms = reader->audio_offset_ms;
        out_frame->is_key_frame = 0;
        reader->audio_ready = 0;
        ++reader->audio_index;
    }

    return 1;
}

void sample_media_reader_close(struct SampleMediaReader *reader) {
    if (reader == NULL) {
        return;
    }
    if (reader->video.annex_b.file != NULL) {
        (void)fclose(reader->video.annex_b.file);
    }
    if (reader->audio_file != NULL) {
        (void)fclose(reader->audio_file);
    }
    free(reader->video.annex_b.nal);
    free(reader->video.frame);
    free(reader);
}
