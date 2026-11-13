#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdlib>
#include <string>

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

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Impeller is off by default (the app updates tables and logs often and felt
  // heavy on Impeller). To try it: `lab_daemon.exe --enable-impeller` or set the
  // environment variable LABDAEMON_IMPELLER=1.
  bool enable_impeller = false;
  for (const auto &arg : command_line_arguments) {
    if (arg == "--enable-impeller") enable_impeller = true;
  }
  char *env_impeller = nullptr;
  size_t env_len = 0;
  if (_dupenv_s(&env_impeller, &env_len, "LABDAEMON_IMPELLER") == 0 &&
      env_impeller != nullptr) {
    if (std::string(env_impeller) == "1") enable_impeller = true;
    free(env_impeller);
  }
  project.set_impeller_switch(enable_impeller
                                  ? flutter::ImpellerSwitch::Enabled
                                  : flutter::ImpellerSwitch::Disabled);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Lab Daemon", origin, size)) {
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
