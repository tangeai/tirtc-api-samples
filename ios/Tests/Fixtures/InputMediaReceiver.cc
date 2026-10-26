// Darwin custom-input counterpart. It retains encoded callback order and timing.
#include <ti/media.h>
#include <ti/rtc.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <thread>

using Clock = std::chrono::steady_clock;
using namespace std::chrono_literals;

struct Capture {
  std::mutex mutex;
  std::ofstream audio;
  std::ofstream packets;
  uint64_t bytes = 0;
  uint64_t packet_count = 0;
  uint32_t sample_rate_hz = 0;
  uint32_t channels = 0;
  TiMediaCodec codec = TI_MEDIA_CODEC_NONE;
  std::atomic<TiRtcConn*> connection{nullptr};
  std::atomic<int> error{0};
  std::atomic<bool> disconnected{false};
};

static void check(TiError code, const char* operation) {
  if (code != TI_ERROR_OK) {
    throw std::runtime_error(std::string(operation) + ":" + std::to_string(code));
  }
}

static void TI_CALL connected(TiRtcConnService*, TiRtcConn* connection, void* user) {
  static_cast<Capture*>(user)->connection.store(connection);
}

static void TI_CALL service_error(TiRtcConnService*, TiError code, const char*, void* user) {
  static_cast<Capture*>(user)->error.store(code);
}

static void TI_CALL client_state(TiRtcConn* connection, TiRtcConnState state, TiError code,
                                 void* user) {
  auto& capture = *static_cast<Capture*>(user);
  if (code != TI_ERROR_OK)
    capture.error.store(code);
  if (state == TI_RTC_CONN_STATE_CONNECTED)
    capture.connection.store(connection);
  if (state == TI_RTC_CONN_STATE_DISCONNECTED)
    capture.disconnected.store(true);
}

static void TI_CALL audio_frame(TiEncodedAudioOutput*, const TiEncodedAudioFrame* frame,
                                void* user) {
  auto& capture = *static_cast<Capture*>(user);
  TiEncodedAudioFrameInfo info = TI_ENCODED_AUDIO_FRAME_INFO_INITIALIZER;
  if (ti_encoded_audio_frame_get_info(frame, &info) != TI_ERROR_OK) {
    capture.error = 1;
    return;
  }
  std::lock_guard<std::mutex> lock(capture.mutex);
  if ((capture.codec != TI_MEDIA_CODEC_NONE && capture.codec != info.codec) ||
      (capture.sample_rate_hz != 0 && capture.sample_rate_hz != info.sample_rate_hz) ||
      (capture.channels != 0 && capture.channels != info.channels) ||
      capture.bytes + info.data_size > 1024 * 1024) {
    capture.error = 1;
    return;
  }
  capture.codec = info.codec;
  capture.sample_rate_hz = info.sample_rate_hz;
  capture.channels = info.channels;
  capture.packets << info.pts_us << ',' << capture.bytes << ',' << info.data_size << '\n';
  capture.audio.write(reinterpret_cast<const char*>(info.data),
                      static_cast<std::streamsize>(info.data_size));
  capture.bytes += info.data_size;
  capture.packet_count++;
}

int main(int argc, char** argv) {
  const bool client = argc == 4 && std::string(argv[2]) == "client";
  if (argc != 2 && !client)
    return 64;
  const std::filesystem::path root = argv[1];
  std::filesystem::create_directories(root);
  Capture capture;
  capture.audio.open(root / "encoded-audio.bin", std::ios::binary);
  capture.packets.open(root / "encoded-audio.bin.packets.csv");
  capture.packets << "pts_us,offset,size\n";
  TiRtcConnService* service = nullptr;
  TiEncodedAudioOutput* audio = nullptr;
  TiRtcConn* connection = nullptr;
  bool initialized = false;
  bool attached = false;
  int result = 0;
  try {
    TiRtcInitOptions options = TI_RTC_INIT_OPTIONS_INITIALIZER;
    options.app_id = std::getenv("TIRTC_APP_ID");
    options.endpoint = std::getenv("TIRTC_ENDPOINT");
    const auto cache = (root / "runtime-work").string();
    options.cache_root_dir = cache.c_str();
    options.console_log_enabled = 1;
    check(tirtc_init(&options), "initialize");
    initialized = true;
    if (client) {
      std::array<char, 16385> buffer{};
      std::ifstream token_file(argv[3], std::ios::binary);
      token_file.read(buffer.data(), buffer.size());
      const auto size = token_file.gcount();
      if (size <= 0 || size > 16384)
        throw std::runtime_error("invalid private client token file");
      const std::string token(buffer.data(), static_cast<size_t>(size));
      TiRtcConnCallbacks callbacks = TI_RTC_CONN_CALLBACKS_INITIALIZER;
      callbacks.on_state_changed = client_state;
      TiRtcConnCreateOptions create = TI_RTC_CONN_CREATE_OPTIONS_INITIALIZER;
      create.callbacks = &callbacks;
      create.user_data = &capture;
      check(tirtc_conn_create(&create, &connection), "client create");
      TiRtcConnConnectOptions connect = TI_RTC_CONN_CONNECT_OPTIONS_INITIALIZER;
      connect.remote_id = std::getenv("TIRTC_DEVICE_ID");
      connect.token = token.c_str();
      check(tirtc_conn_connect(connection, &connect), "client connect");
    } else {
      TiRtcConnServiceStartOptions service_options = TI_RTC_CONN_SERVICE_START_OPTIONS_INITIALIZER;
      service_options.device_id = std::getenv("TIRTC_DEVICE_ID");
      service_options.device_secret_key = std::getenv("TIRTC_DEVICE_SECRET_KEY");
      service_options.client_id = std::getenv("TIRTC_CLIENT_ID");
      service_options.max_connections = 1;
      TiRtcConnServiceCallbacks callbacks = TI_RTC_CONN_SERVICE_CALLBACKS_INITIALIZER;
      callbacks.on_connected = connected;
      callbacks.on_error = service_error;
      check(tirtc_conn_service_start(&service_options, &callbacks, &capture, &service),
            "service start");
    }
    std::cout << "input_media_receiver_ready" << std::endl;
    const auto connection_deadline = Clock::now() + 45s;
    while (!capture.connection.load() && !capture.error && Clock::now() < connection_deadline) {
      std::this_thread::sleep_for(50ms);
    }
    if (!capture.connection.load() || capture.error)
      throw std::runtime_error("connection timeout or service error");
    connection = capture.connection.load();
    check(ti_encoded_audio_output_create(&audio), "audio create");
    TiEncodedAudioOutputCallbacks audio_callbacks = TI_ENCODED_AUDIO_OUTPUT_CALLBACKS_INITIALIZER;
    audio_callbacks.on_frame = audio_frame;
    check(ti_encoded_audio_output_set_callbacks(audio, &audio_callbacks, &capture),
          "audio callbacks");
    check(tirtc_encoded_audio_output_attach(audio, connection, 14), "audio attach");
    attached = true;
    check(tirtc_conn_subscribe_audio(connection, 14), "audio subscribe");
    const auto media_deadline = Clock::now() + 15s;
    bool complete = false;
    while (!capture.error && Clock::now() < media_deadline) {
      {
        std::lock_guard<std::mutex> lock(capture.mutex);
        complete = capture.packet_count >= 100;
      }
      if (complete)
        break;
      std::this_thread::sleep_for(20ms);
    }
    {
      std::lock_guard<std::mutex> lock(capture.mutex);
      complete = capture.packet_count == 100 && capture.bytes == 16000;
    }
    if (capture.error || !complete) {
      throw std::runtime_error("encoded audio did not produce exactly 100 packets / 16000 bytes");
    }
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    result = 1;
  }
  const auto cleanup = [&](TiError code) {
    if (code != TI_ERROR_OK) {
      std::cerr << "cleanup:" << code << std::endl;
      result = 1;
    }
  };
  if (audio) {
    cleanup(ti_encoded_audio_output_set_callbacks(audio, nullptr, nullptr));
    if (attached)
      cleanup(tirtc_encoded_audio_output_detach(audio));
    cleanup(ti_encoded_audio_output_destroy(audio));
  }
  if (service)
    cleanup(tirtc_conn_service_stop(service));
  if (!connection)
    connection = capture.connection.load();
  if (client && connection) {
    cleanup(tirtc_conn_disconnect(connection));
    const auto deadline = Clock::now() + 5s;
    while (!capture.disconnected && Clock::now() < deadline)
      std::this_thread::sleep_for(20ms);
  }
  if (connection)
    cleanup(tirtc_conn_destroy(connection));
  if (service)
    cleanup(tirtc_conn_service_destroy(service));
  if (initialized)
    cleanup(tirtc_uninit());
  capture.audio.close();
  capture.packets.close();
  std::lock_guard<std::mutex> lock(capture.mutex);
  const char* codec = capture.codec == TI_MEDIA_CODEC_AUDIO_G711A ? "g711a" : "unknown";
  std::ofstream manifest(root / "media_receive.json");
  manifest << "{\"audio\":{\"codec\":\"" << codec
           << "\",\"path\":\"encoded-audio.bin\",\"bytes\":" << capture.bytes
           << ",\"packet_count\":" << capture.packet_count
           << ",\"sample_rate_hz\":" << capture.sample_rate_hz
           << ",\"channels\":" << capture.channels << "}}\n";
  return result;
}
