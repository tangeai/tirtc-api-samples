#define _POSIX_C_SOURCE 200809L

#include "media_reader.h"
#include "tistore.h"

#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define SAMPLE_DURATION_MS UINT64_C(120000)
#define STATUS_INTERVAL_MS UINT64_C(5000)
#define RESULT_TIMEOUT_MS UINT64_C(180000)
#define INDEX_SETTLE_MS UINT64_C(35000)

struct Arguments {
    const char *endpoint;
    const char *device_id;
    const char *device_secret_key;
    const char *token;
    const char *video_file;
    const char *audio_file;
};

struct UploadState {
    pthread_mutex_t mutex;
    uint64_t progress_sequence;
    uint64_t progress_start_time_ms;
    uint64_t progress_end_time_ms;
    uint64_t progress_size_bytes;
    int progress_error;
    int finished;
    int result_code;
    int result_error;
    uint64_t result_start_time_ms;
    uint64_t result_end_time_ms;
    uint64_t result_duration_ms;
    uint64_t result_size_bytes;
    char result_message[256];
};

static volatile sig_atomic_t interrupted = 0;

static void handle_signal(int signal_number) {
    (void)signal_number;
    interrupted = 1;
}

static uint64_t clock_milliseconds(clockid_t clock_id) {
    struct timespec value;

    if (clock_gettime(clock_id, &value) != 0) {
        return 0;
    }
    return (uint64_t)value.tv_sec * UINT64_C(1000) + (uint64_t)value.tv_nsec / UINT64_C(1000000);
}

static void sleep_milliseconds(uint64_t duration_ms) {
    struct timespec request;

    request.tv_sec = (time_t)(duration_ms / UINT64_C(1000));
    request.tv_nsec = (long)((duration_ms % UINT64_C(1000)) * UINT64_C(1000000));
    while (!interrupted && nanosleep(&request, &request) != 0 && errno == EINTR) {
    }
}

static void sleep_until(uint64_t monotonic_deadline_ms) {
    while (!interrupted) {
        uint64_t now_ms = clock_milliseconds(CLOCK_MONOTONIC);
        if (now_ms == 0 || now_ms >= monotonic_deadline_ms) {
            return;
        }
        sleep_milliseconds(monotonic_deadline_ms - now_ms);
    }
}

static void print_usage(const char *program) {
    fprintf(
        stderr,
        "Usage: %s --endpoint <endpoint> --device-id <id> "
        "--device-secret-key <key> --token <token> "
        "--video-file <path> --audio-file <path>\n",
        program
    );
}

static int parse_arguments(int argc, char **argv, struct Arguments *arguments) {
    int index;

    memset(arguments, 0, sizeof(*arguments));
    for (index = 1; index < argc; index += 2) {
        const char *name;
        const char *value;

        if (index + 1 >= argc) {
            return -1;
        }
        name = argv[index];
        value = argv[index + 1];
        if (strcmp(name, "--endpoint") == 0) {
            arguments->endpoint = value;
        } else if (strcmp(name, "--device-id") == 0) {
            arguments->device_id = value;
        } else if (strcmp(name, "--device-secret-key") == 0) {
            arguments->device_secret_key = value;
        } else if (strcmp(name, "--token") == 0) {
            arguments->token = value;
        } else if (strcmp(name, "--video-file") == 0) {
            arguments->video_file = value;
        } else if (strcmp(name, "--audio-file") == 0) {
            arguments->audio_file = value;
        } else {
            return -1;
        }
    }

    return arguments->endpoint != NULL && arguments->endpoint[0] != '\0' &&
               arguments->device_id != NULL && arguments->device_id[0] != '\0' &&
               arguments->device_secret_key != NULL && arguments->device_secret_key[0] != '\0' &&
               arguments->token != NULL && arguments->token[0] != '\0' &&
               arguments->video_file != NULL && arguments->video_file[0] != '\0' &&
               arguments->audio_file != NULL && arguments->audio_file[0] != '\0'
           ? 0
           : -1;
}

static void on_upload_progress(
    int service_id,
    const struct TiStoreUploadRange *range,
    int error,
    void *user_data
) {
    struct UploadState *state = (struct UploadState *)user_data;

    (void)service_id;
    if (state == NULL || range == NULL) {
        return;
    }
    (void)pthread_mutex_lock(&state->mutex);
    ++state->progress_sequence;
    state->progress_start_time_ms = range->start_time_ms;
    state->progress_end_time_ms = range->end_time_ms;
    state->progress_size_bytes = range->size_bytes;
    state->progress_error = error;
    (void)pthread_mutex_unlock(&state->mutex);
}

static void on_upload_result(
    int service_id,
    const struct TiStoreUploadResult *result,
    void *user_data
) {
    struct UploadState *state = (struct UploadState *)user_data;

    (void)service_id;
    if (state == NULL || result == NULL) {
        return;
    }
    (void)pthread_mutex_lock(&state->mutex);
    state->finished = 1;
    state->result_code = result->result;
    state->result_error = result->error;
    state->result_start_time_ms = result->start_time_ms;
    state->result_end_time_ms = result->end_time_ms;
    state->result_duration_ms = result->net_duration_ms;
    state->result_size_bytes = result->size_bytes;
    if (result->message != NULL) {
        (void)snprintf(state->result_message, sizeof(state->result_message), "%s", result->message);
    } else {
        state->result_message[0] = '\0';
    }
    (void)pthread_mutex_unlock(&state->mutex);
}

static int print_upload_updates(struct UploadState *state, uint64_t *seen_sequence) {
    uint64_t sequence;
    uint64_t start_time_ms;
    uint64_t end_time_ms;
    uint64_t size_bytes;
    int error;
    int finished;

    (void)pthread_mutex_lock(&state->mutex);
    sequence = state->progress_sequence;
    start_time_ms = state->progress_start_time_ms;
    end_time_ms = state->progress_end_time_ms;
    size_bytes = state->progress_size_bytes;
    error = state->progress_error;
    finished = state->finished;
    (void)pthread_mutex_unlock(&state->mutex);

    if (sequence != *seen_sequence) {
        printf(
            "[upload] slice=%" PRIu64 " range=%" PRIu64 "..%" PRIu64
            " bytes=%" PRIu64 " status=%s",
            sequence,
            start_time_ms,
            end_time_ms,
            size_bytes,
            error == TISTORE_OK ? "ok" : "failed"
        );
        if (error != TISTORE_OK) {
            printf(" error=%d (%s)", error, TiStoreGetErrorString(error));
        }
        printf("\n");
        *seen_sequence = sequence;
    }
    return finished;
}

static void print_queue_status(
    int service_id,
    uint64_t elapsed_ms,
    uint64_t video_frames,
    uint64_t audio_frames,
    uint64_t media_bytes
) {
    struct TiStoreQueueInfo queue_info;
    int error = TiStoreQueueGetInfo(service_id, &queue_info);

    if (error == TISTORE_OK) {
        printf(
            "[feed] elapsed=%" PRIu64 "ms video=%" PRIu64 " audio=%" PRIu64
            " bytes=%" PRIu64 " queue=%" PRIu64 "/%" PRIu64
            " inflight=%" PRIu64 "\n",
            elapsed_ms,
            video_frames,
            audio_frames,
            media_bytes,
            queue_info.used_bytes,
            queue_info.capacity_bytes,
            queue_info.inflight_bytes
        );
    } else {
        printf(
            "[feed] elapsed=%" PRIu64 "ms video=%" PRIu64 " audio=%" PRIu64
            " bytes=%" PRIu64 " queue_error=%d (%s)\n",
            elapsed_ms,
            video_frames,
            audio_frames,
            media_bytes,
            error,
            TiStoreGetErrorString(error)
        );
    }
}

static int write_frame_with_retry(
    int service_id,
    const struct TiStoreFrameInfo *frame_info,
    const void *frame
) {
    for (;;) {
        int error = TiStoreQueueWriteFrame(service_id, frame_info, frame);
        if (error == TISTORE_OK) {
            return TISTORE_OK;
        }
        if (error != TISTORE_E_QUEUE_FULL || interrupted) {
            return error;
        }
        sleep_milliseconds(20);
    }
}

static int result_is_success(struct UploadState *state) {
    int success;

    (void)pthread_mutex_lock(&state->mutex);
    success = state->finished && state->result_code == TISTORE_UPLOAD_COMPLETE &&
              state->result_error == TISTORE_OK;
    (void)pthread_mutex_unlock(&state->mutex);
    return success;
}

static void print_final_result(struct UploadState *state) {
    int result_code;
    int result_error;
    uint64_t start_time_ms;
    uint64_t end_time_ms;
    uint64_t duration_ms;
    uint64_t size_bytes;
    char message[sizeof(state->result_message)];

    (void)pthread_mutex_lock(&state->mutex);
    result_code = state->result_code;
    result_error = state->result_error;
    start_time_ms = state->result_start_time_ms;
    end_time_ms = state->result_end_time_ms;
    duration_ms = state->result_duration_ms;
    size_bytes = state->result_size_bytes;
    (void)snprintf(message, sizeof(message), "%s", state->result_message);
    (void)pthread_mutex_unlock(&state->mutex);

    printf(
        "[result] code=%d error=%d range=%" PRIu64 "..%" PRIu64
        " duration=%" PRIu64 "ms bytes=%" PRIu64,
        result_code,
        result_error,
        start_time_ms,
        end_time_ms,
        duration_ms,
        size_bytes
    );
    if (message[0] != '\0') {
        printf(" message=%s", message);
    }
    printf("\n");
}

int main(int argc, char **argv) {
    struct Arguments arguments;
    struct SampleMediaReader *media_reader = NULL;
    struct UploadState upload_state;
    struct TiStoreOptions store_options = TISTORE_OPTIONS_INITIALIZER;
    struct TiStoreServiceOptions service_options = TISTORE_SERVICE_OPTIONS_INITIALIZER;
    struct TiStoreUploadRequestOptions upload_options = TISTORE_UPLOAD_REQUEST_OPTIONS_INITIALIZER;
    struct sigaction signal_action;
    uint64_t utc_base_ms;
    uint64_t monotonic_base_ms;
    uint64_t next_status_ms = 0;
    uint64_t seen_progress_sequence = 0;
    uint64_t video_frames = 0;
    uint64_t audio_frames = 0;
    uint64_t media_bytes = 0;
    char media_error[256];
    int store_initialized = 0;
    int service_started = 0;
    int service_id = -1;
    int exit_code = 1;
    int error;

    setvbuf(stdout, NULL, _IOLBF, 0);
    if (parse_arguments(argc, argv, &arguments) != 0) {
        print_usage(argv[0]);
        return 2;
    }

    memset(&signal_action, 0, sizeof(signal_action));
    signal_action.sa_handler = handle_signal;
    (void)sigemptyset(&signal_action.sa_mask);
    (void)sigaction(SIGINT, &signal_action, NULL);
    (void)sigaction(SIGTERM, &signal_action, NULL);

    memset(&upload_state, 0, sizeof(upload_state));
    if (pthread_mutex_init(&upload_state.mutex, NULL) != 0) {
        fprintf(stderr, "[error] failed to initialize callback state\n");
        return 1;
    }

    if (sample_media_reader_open(
            &media_reader,
            arguments.video_file,
            arguments.audio_file,
            SAMPLE_DURATION_MS,
            media_error,
            sizeof(media_error)
        ) != 0) {
        fprintf(stderr, "[error] %s\n", media_error);
        goto cleanup;
    }

    store_options.endpoint = arguments.endpoint;
    /* Keep credentials and signed upload responses out of developer console logs. */
    store_options.log_level = TISTORE_LOG_NONE;
    error = TiStoreInit(&store_options);
    if (error != TISTORE_OK) {
        fprintf(stderr, "[error] TiStoreInit: %d (%s)\n", error, TiStoreGetErrorString(error));
        goto cleanup;
    }
    store_initialized = 1;
    printf("[init] TiStore %s\n", TiStoreGetVersion());

    service_options.device_secret_key = arguments.device_secret_key;
    service_id = TiStoreServiceCreate(arguments.device_id, &service_options);
    if (service_id < 0) {
        fprintf(
            stderr,
            "[error] TiStoreServiceCreate: %d (%s)\n",
            service_id,
            TiStoreGetErrorString(service_id)
        );
        goto cleanup;
    }

    error = TiStoreServiceUpdateToken(service_id, arguments.token);
    if (error != TISTORE_OK) {
        fprintf(
            stderr,
            "[error] TiStoreServiceUpdateToken: %d (%s)\n",
            error,
            TiStoreGetErrorString(error)
        );
        goto cleanup;
    }
    error = TiStoreServiceStart(service_id);
    if (error != TISTORE_OK) {
        fprintf(
            stderr,
            "[error] TiStoreServiceStart: %d (%s)\n",
            error,
            TiStoreGetErrorString(error)
        );
        goto cleanup;
    }
    service_started = 1;

    upload_options.start_time_ms = TISTORE_TIME_EARLIEST;
    upload_options.duration_ms = SAMPLE_DURATION_MS;
    upload_options.on_progress = on_upload_progress;
    upload_options.on_result = on_upload_result;
    upload_options.user_data = &upload_state;
    error = TiStoreUploadRequest(service_id, &upload_options);
    if (error < 0) {
        fprintf(
            stderr,
            "[error] TiStoreUploadRequest: %d (%s)\n",
            error,
            TiStoreGetErrorString(error)
        );
        goto cleanup;
    }
    printf("[upload] request=%d duration=%" PRIu64 "ms\n", error, SAMPLE_DURATION_MS);

    utc_base_ms = clock_milliseconds(CLOCK_REALTIME);
    monotonic_base_ms = clock_milliseconds(CLOCK_MONOTONIC);
    if (utc_base_ms == 0 || monotonic_base_ms == 0) {
        fprintf(stderr, "[error] failed to read system clocks\n");
        goto cleanup;
    }

    for (;;) {
        struct SampleMediaFrame media_frame;
        struct TiStoreFrameInfo frame_info;
        int read_result = sample_media_reader_next(
            media_reader,
            &media_frame,
            media_error,
            sizeof(media_error)
        );

        if (read_result < 0) {
            fprintf(stderr, "[error] %s\n", media_error);
            goto cleanup;
        }
        if (read_result == 0 || interrupted) {
            break;
        }

        sleep_until(monotonic_base_ms + media_frame.offset_ms);
        if (interrupted) {
            break;
        }

        memset(&frame_info, 0, sizeof(frame_info));
        frame_info.channel_id = 0;
        frame_info.media = media_frame.kind == SAMPLE_MEDIA_VIDEO
                               ? TISTORE_VIDEO_H264
                               : TISTORE_AUDIO_ALAW;
        frame_info.flags = media_frame.kind == SAMPLE_MEDIA_VIDEO
                               ? (media_frame.is_key_frame ? TISTORE_FRAME_FLAG_KEY_FRAME : 0)
                               : TISTORE_AUDIO_SAMPLE_8K16B1C;
        frame_info.timestamp_ms = utc_base_ms + media_frame.offset_ms;
        frame_info.length = (uint32_t)media_frame.size;

        error = write_frame_with_retry(service_id, &frame_info, media_frame.data);
        if (error != TISTORE_OK) {
            fprintf(
                stderr,
                "[error] TiStoreQueueWriteFrame at %" PRIu64 "ms: %d (%s)\n",
                media_frame.offset_ms,
                error,
                TiStoreGetErrorString(error)
            );
            goto cleanup;
        }

        if (media_frame.kind == SAMPLE_MEDIA_VIDEO) {
            ++video_frames;
            if (video_frames == 1) {
                printf(
                    "[feed] first video frame timestamp=%" PRIu64 " key=%d bytes=%zu\n",
                    frame_info.timestamp_ms,
                    media_frame.is_key_frame,
                    media_frame.size
                );
            }
        } else {
            ++audio_frames;
            if (audio_frames == 1) {
                printf(
                    "[feed] first audio frame timestamp=%" PRIu64 " bytes=%zu\n",
                    frame_info.timestamp_ms,
                    media_frame.size
                );
            }
        }
        media_bytes += media_frame.size;

        (void)print_upload_updates(&upload_state, &seen_progress_sequence);
        if (media_frame.offset_ms >= next_status_ms) {
            print_queue_status(
                service_id,
                media_frame.offset_ms,
                video_frames,
                audio_frames,
                media_bytes
            );
            next_status_ms += STATUS_INTERVAL_MS;
        }
    }

    if (interrupted) {
        fprintf(stderr, "[stop] interrupted\n");
        goto cleanup;
    }
    printf(
        "[feed] finished duration=%" PRIu64 "ms video=%" PRIu64
        " audio=%" PRIu64 " bytes=%" PRIu64 "\n",
        SAMPLE_DURATION_MS,
        video_frames,
        audio_frames,
        media_bytes
    );

    {
        uint64_t wait_started_ms = clock_milliseconds(CLOCK_MONOTONIC);
        while (!interrupted &&
               !print_upload_updates(&upload_state, &seen_progress_sequence) &&
               clock_milliseconds(CLOCK_MONOTONIC) - wait_started_ms < RESULT_TIMEOUT_MS) {
            sleep_milliseconds(100);
        }
        if (interrupted) {
            fprintf(stderr, "[stop] interrupted while waiting for upload result\n");
            goto cleanup;
        }
        if (!print_upload_updates(&upload_state, &seen_progress_sequence)) {
            fprintf(stderr, "[error] timed out waiting for upload result\n");
            goto cleanup;
        }
    }

    print_final_result(&upload_state);
    if (!result_is_success(&upload_state)) {
        goto cleanup;
    }

    printf(
        "[index] keeping the service active for background index reporting (%" PRIu64 "ms)\n",
        INDEX_SETTLE_MS
    );
    {
        uint64_t settle_started_ms = clock_milliseconds(CLOCK_MONOTONIC);
        uint64_t next_settle_log_ms = STATUS_INTERVAL_MS;
        while (!interrupted) {
            uint64_t elapsed_ms = clock_milliseconds(CLOCK_MONOTONIC) - settle_started_ms;
            if (elapsed_ms >= INDEX_SETTLE_MS) {
                break;
            }
            if (elapsed_ms >= next_settle_log_ms) {
                printf("[index] waiting elapsed=%" PRIu64 "ms\n", elapsed_ms);
                next_settle_log_ms += STATUS_INTERVAL_MS;
            }
            sleep_milliseconds(100);
        }
    }
    if (!interrupted) {
        printf("[result] upload complete\n");
        exit_code = 0;
    }

cleanup:
    sample_media_reader_close(media_reader);
    if (service_started) {
        error = TiStoreServiceStop(service_id);
        if (error != TISTORE_OK) {
            fprintf(stderr, "[error] TiStoreServiceStop: %d (%s)\n", error, TiStoreGetErrorString(error));
            exit_code = 1;
        }
    }
    if (service_id > 0) {
        error = TiStoreServiceDestroy(service_id);
        if (error != TISTORE_OK) {
            fprintf(
                stderr,
                "[error] TiStoreServiceDestroy: %d (%s)\n",
                error,
                TiStoreGetErrorString(error)
            );
            exit_code = 1;
        }
    }
    if (store_initialized) {
        error = TiStoreUninit();
        if (error != TISTORE_OK) {
            fprintf(stderr, "[error] TiStoreUninit: %d (%s)\n", error, TiStoreGetErrorString(error));
            exit_code = 1;
        }
    }
    (void)pthread_mutex_destroy(&upload_state.mutex);
    return exit_code;
}
