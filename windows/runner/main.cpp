#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // Impeller is the default desktop renderer since Flutter 3.47, but on this
  // UI it is not shippable: at 200% DPI it holds ~1.8 GB of GPU textures and
  // every window resize allocates more (measured 1762 MB -> 2814 MB over eight
  // resizes, 8.2 GB over thirty), and the freshly exposed area draws black
  // until the next frame. Skia sits at ~250 MB with no artifacts. Same call,
  // same reason as FlClash (chen08209/FlClash, windows/runner/main.cpp), which
  // hit flutter/flutter#193504 on identical hardware (Windows 11 + Intel Arc).
  // Remove this when a stable Flutter fixes #193504: build with Impeller on
  // that SDK and drag every window edge for a minute at 200% DPI; the window
  // must keep repainting and memory must stay flat.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1440, 900);
  if (!window.Create(L"Bookloom", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
