#include "flutter_window.h"

#include <objbase.h>
#include <shobjidl.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

#include <flutter/standard_method_codec.h>

namespace {

std::wstring Utf16FromUtf8(const std::string& value) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         value.data(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  if (length <= 0) return L"";
  std::wstring result(length, L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          static_cast<int>(value.size()), result.data(),
                          length) != length) {
    return L"";
  }
  return result;
}

// Only select a path here. Dart streams the prepared file after this dialog.
HRESULT ChooseSavePath(HWND parent, const std::wstring& file_name,
                       std::string* selected_path) {
  const HRESULT init = CoInitializeEx(nullptr,
      COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (FAILED(init)) return init;

  IFileSaveDialog* dialog = nullptr;
  HRESULT status = CoCreateInstance(CLSID_FileSaveDialog, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
  if (SUCCEEDED(status)) {
    DWORD options = 0;
    status = dialog->GetOptions(&options);
    if (SUCCEEDED(status)) {
      status = dialog->SetOptions(options | FOS_FORCEFILESYSTEM |
                                  FOS_OVERWRITEPROMPT | FOS_NOCHANGEDIR);
    }
    if (SUCCEEDED(status)) status = dialog->SetFileName(file_name.c_str());
    if (SUCCEEDED(status)) status = dialog->Show(parent);
    if (SUCCEEDED(status)) {
      IShellItem* item = nullptr;
      status = dialog->GetResult(&item);
      if (SUCCEEDED(status)) {
        PWSTR path = nullptr;
        status = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
        if (SUCCEEDED(status)) {
          *selected_path = Utf8FromUtf16(path);
          CoTaskMemFree(path);
          if (selected_path->empty()) status = E_FAIL;
        }
      }
      if (item != nullptr) item->Release();
    }
    dialog->Release();
  }
  CoUninitialize();
  return status;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

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
  // The runner links flutter_wrapper_app, which does not carry
  // plugin_registrar.cc, so a channel cannot be opened through
  // PluginRegistrarManager here. The engine's own messenger is the documented
  // way to host a runner-level channel.
  file_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "bookloom/file_service",
          &flutter::StandardMethodCodec::GetInstance());
  file_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "commitStagedFile") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args == nullptr) {
        result->Error("invalid_path", "Missing staged file paths");
        return;
      }
      const auto staged_it =
          args->find(flutter::EncodableValue("stagedPath"));
      const auto target_it =
          args->find(flutter::EncodableValue("targetPath"));
      const auto* staged = staged_it == args->end()
                               ? nullptr
                               : std::get_if<std::string>(&staged_it->second);
      const auto* target = target_it == args->end()
                               ? nullptr
                               : std::get_if<std::string>(&target_it->second);
      if (staged == nullptr || target == nullptr || staged->empty() ||
          target->empty()) {
        result->Error("invalid_path", "Missing staged file paths");
        return;
      }
      const std::wstring staged_path = Utf16FromUtf8(*staged);
      const std::wstring target_path = Utf16FromUtf8(*target);
      if (staged_path.empty() || target_path.empty()) {
        result->Error("invalid_path", "Invalid path encoding");
        return;
      }
      if (!MoveFileExW(staged_path.c_str(), target_path.c_str(),
                       MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        result->Error("commit_failed", "Unable to replace save target",
                      flutter::EncodableValue(
                          static_cast<int64_t>(GetLastError())));
        return;
      }
      result->Success();
      return;
    }
    if (call.method_name() != "chooseSavePath") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("invalid_name", "Missing file name");
      return;
    }
    const auto it = args->find(flutter::EncodableValue("fileName"));
    const auto* name = it == args->end()
                           ? nullptr
                           : std::get_if<std::string>(&it->second);
    if (name == nullptr || name->empty()) {
      result->Error("invalid_name", "Missing file name");
      return;
    }
    const std::wstring wide_name = Utf16FromUtf8(*name);
    if (wide_name.empty()) {
      result->Error("invalid_name", "Invalid file name encoding");
      return;
    }
    std::string path;
    const HRESULT status = ChooseSavePath(GetHandle(), wide_name, &path);
    if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      result->Success(flutter::EncodableValue());
    } else if (FAILED(status)) {
      result->Error("dialog_failed", "Unable to choose save location",
                    flutter::EncodableValue(static_cast<int64_t>(status)));
    } else {
      result->Success(flutter::EncodableValue(path));
    }
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (file_channel_) file_channel_->SetMethodCallHandler(nullptr);
  file_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
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
