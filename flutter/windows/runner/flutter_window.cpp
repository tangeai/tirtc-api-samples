#include "flutter_window.h"

#include <Windows.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodResult = flutter::MethodResult<EncodableValue>;

constexpr wchar_t kPreferencesRegistryPath[] = L"Software\\TiRTC\\Example";
constexpr char kPreferencesKeyPrefix[] = "tirtc_example.";

const EncodableValue* Argument(const EncodableMap* arguments, const char* name) {
  if (arguments == nullptr) {
    return nullptr;
  }
  const auto iterator = arguments->find(EncodableValue(name));
  return iterator == arguments->end() ? nullptr : &iterator->second;
}

std::optional<std::string> StringArgument(const EncodableMap* arguments, const char* name) {
  const EncodableValue* value = Argument(arguments, name);
  const auto* text = value == nullptr ? nullptr : std::get_if<std::string>(value);
  return text == nullptr ? std::nullopt : std::optional<std::string>(*text);
}

std::optional<int32_t> IntArgument(const EncodableMap* arguments, const char* name) {
  const EncodableValue* value = Argument(arguments, name);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int64_t>(value);
      number != nullptr && *number >= INT32_MIN && *number <= INT32_MAX) {
    return static_cast<int32_t>(*number);
  }
  return std::nullopt;
}

std::optional<std::wstring> Wide(const std::string& value) {
  if (value.size() > 16 * 1024) {
    return std::nullopt;
  }
  if (value.empty()) {
    return std::wstring();
  }
  const int input_size = static_cast<int>(value.size());
  const int size =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), input_size, nullptr, 0);
  if (size <= 0) {
    return std::nullopt;
  }
  std::wstring result(static_cast<size_t>(size), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), input_size, result.data(),
                          size) != size) {
    return std::nullopt;
  }
  return result;
}

std::optional<std::wstring> PreferenceKey(const EncodableMap* arguments) {
  const auto key = StringArgument(arguments, "key");
  if (!key || key->size() > 255 || key->rfind(kPreferencesKeyPrefix, 0) != 0) {
    return std::nullopt;
  }
  return Wide(*key);
}

LSTATUS OpenPreferences(HKEY* key) {
  return RegCreateKeyExW(HKEY_CURRENT_USER, kPreferencesRegistryPath, 0, nullptr, 0,
                         KEY_READ | KEY_WRITE, nullptr, key, nullptr);
}

void PreferencesError(std::unique_ptr<MethodResult> result, const char* operation) {
  result->Error("PREFERENCES_IO_FAILED",
                std::string("Windows preferences ") + operation + " failed");
}

void HandlePreferencesCall(const flutter::MethodCall<EncodableValue>& call,
                           std::unique_ptr<MethodResult> result) {
  const auto* arguments =
      call.arguments() == nullptr ? nullptr : std::get_if<EncodableMap>(call.arguments());
  const auto key = PreferenceKey(arguments);
  if (!key) {
    result->Error("INVALID_ARGUMENT", "valid preferences key is required");
    return;
  }
  HKEY registry_key = nullptr;
  if (OpenPreferences(&registry_key) != ERROR_SUCCESS) {
    PreferencesError(std::move(result), "open");
    return;
  }

  const std::string& method = call.method_name();
  if (method == "putPreferencesInt") {
    const auto value = IntArgument(arguments, "value");
    if (!value) {
      RegCloseKey(registry_key);
      result->Error("INVALID_ARGUMENT", "key and value are required");
      return;
    }
    const DWORD stored = static_cast<DWORD>(*value);
    const LSTATUS status =
        RegSetValueExW(registry_key, key->c_str(), 0, REG_DWORD,
                       reinterpret_cast<const BYTE*>(&stored), static_cast<DWORD>(sizeof(stored)));
    RegCloseKey(registry_key);
    if (status != ERROR_SUCCESS) {
      PreferencesError(std::move(result), "write");
      return;
    }
    result->Success();
    return;
  }
  if (method == "getPreferencesInt") {
    const auto default_value = IntArgument(arguments, "defaultValue");
    if (!default_value) {
      RegCloseKey(registry_key);
      result->Error("INVALID_ARGUMENT", "key and defaultValue are required");
      return;
    }
    DWORD stored = 0;
    DWORD size = static_cast<DWORD>(sizeof(stored));
    const LSTATUS status = RegGetValueW(registry_key, nullptr, key->c_str(), RRF_RT_REG_DWORD,
                                        nullptr, &stored, &size);
    RegCloseKey(registry_key);
    if (status == ERROR_FILE_NOT_FOUND) {
      result->Success(EncodableValue(*default_value));
      return;
    }
    if (status != ERROR_SUCCESS) {
      PreferencesError(std::move(result), "read");
      return;
    }
    result->Success(EncodableValue(static_cast<int32_t>(stored)));
    return;
  }
  if (method == "putPreferencesString") {
    const auto value = StringArgument(arguments, "value");
    const auto wide_value = value ? Wide(*value) : std::nullopt;
    if (!wide_value) {
      RegCloseKey(registry_key);
      result->Error("INVALID_ARGUMENT", "key and value are required");
      return;
    }
    const DWORD size = static_cast<DWORD>((wide_value->size() + 1) * sizeof(wchar_t));
    const LSTATUS status = RegSetValueExW(registry_key, key->c_str(), 0, REG_SZ,
                                          reinterpret_cast<const BYTE*>(wide_value->c_str()), size);
    RegCloseKey(registry_key);
    if (status != ERROR_SUCCESS) {
      PreferencesError(std::move(result), "write");
      return;
    }
    result->Success();
    return;
  }
  if (method == "getPreferencesString") {
    const auto default_value = StringArgument(arguments, "defaultValue");
    if (!default_value) {
      RegCloseKey(registry_key);
      result->Error("INVALID_ARGUMENT", "key and defaultValue are required");
      return;
    }
    DWORD size = 0;
    LSTATUS status =
        RegGetValueW(registry_key, nullptr, key->c_str(), RRF_RT_REG_SZ, nullptr, nullptr, &size);
    if (status == ERROR_FILE_NOT_FOUND) {
      RegCloseKey(registry_key);
      result->Success(EncodableValue(*default_value));
      return;
    }
    if (status != ERROR_SUCCESS || size < sizeof(wchar_t)) {
      RegCloseKey(registry_key);
      PreferencesError(std::move(result), "read");
      return;
    }
    std::vector<wchar_t> stored(size / sizeof(wchar_t), L'\0');
    status = RegGetValueW(registry_key, nullptr, key->c_str(), RRF_RT_REG_SZ, nullptr,
                          stored.data(), &size);
    RegCloseKey(registry_key);
    if (status != ERROR_SUCCESS) {
      PreferencesError(std::move(result), "read");
      return;
    }
    result->Success(EncodableValue(Utf8FromUtf16(stored.data())));
    return;
  }
  RegCloseKey(registry_key);
  result->NotImplemented();
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project) : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  preferences_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), "tirtc_example/preferences",
      &flutter::StandardMethodCodec::GetInstance());
  preferences_channel_->SetMethodCallHandler(HandlePreferencesCall);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    preferences_channel_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
