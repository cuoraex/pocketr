#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kWindowStateChannelName[] = "pocketr/window_state";

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_state_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowStateChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  window_state_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setFullScreen") {
          result->NotImplemented();
          return;
        }

        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("invalid_arguments",
                        "Expected fullscreen arguments.");
          return;
        }

        const auto fullscreen_iterator =
            arguments->find(flutter::EncodableValue("isFullScreen"));
        const auto maximize_iterator =
            arguments->find(flutter::EncodableValue("maximize"));
        if (fullscreen_iterator == arguments->end() ||
            maximize_iterator == arguments->end()) {
          result->Error("invalid_arguments",
                        "Missing fullscreen state arguments.");
          return;
        }

        const auto* fullscreen =
            std::get_if<bool>(&fullscreen_iterator->second);
        const auto* maximize = std::get_if<bool>(&maximize_iterator->second);
        if (fullscreen == nullptr || maximize == nullptr) {
          result->Error("invalid_arguments",
                        "Fullscreen state arguments must be booleans.");
          return;
        }

        if (!SetFullScreen(*fullscreen, *maximize)) {
          result->Error("window_transition_failed",
                        "Could not change the window display mode.");
          return;
        }
        result->Success(flutter::EncodableValue(true));
      });

  return true;
}

void FlutterWindow::OnDestroy() {
  if (window_state_channel_) {
    window_state_channel_->SetMethodCallHandler({});
    window_state_channel_.reset();
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::SetFullScreen(bool is_fullscreen, bool maximize_on_exit) {
  HWND window = GetHandle();
  if (window == nullptr) return false;
  if (is_fullscreen == is_fullscreen_) return true;

  if (is_fullscreen) {
    WINDOWPLACEMENT placement{};
    placement.length = sizeof(placement);
    if (!GetWindowPlacement(window, &placement)) return false;

    const LONG_PTR style = GetWindowLongPtr(window, GWL_STYLE);
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    const HMONITOR monitor =
        MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    if (!GetMonitorInfo(monitor, &monitor_info)) return false;

    window_placement_before_fullscreen_ = placement;
    window_style_before_fullscreen_ = style;
    SetLastError(ERROR_SUCCESS);
    SetWindowLongPtr(window, GWL_STYLE,
                     style & ~(WS_MAXIMIZE | WS_CAPTION | WS_THICKFRAME |
                               WS_MAXIMIZEBOX));
    if (GetLastError() != ERROR_SUCCESS) return false;

    const RECT& bounds = monitor_info.rcMonitor;
    if (!SetWindowPos(window, HWND_TOP, bounds.left, bounds.top,
                      bounds.right - bounds.left,
                      bounds.bottom - bounds.top,
                      SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_FRAMECHANGED)) {
      SetWindowLongPtr(window, GWL_STYLE, style & ~WS_MAXIMIZE);
      SetWindowPos(window, nullptr, 0, 0, 0, 0,
                   SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_FRAMECHANGED);
      return false;
    }

    is_fullscreen_ = true;
    return true;
  }

  SetLastError(ERROR_SUCCESS);
  SetWindowLongPtr(window, GWL_STYLE,
                   window_style_before_fullscreen_ & ~WS_MAXIMIZE);
  if (GetLastError() != ERROR_SUCCESS) return false;

  if (!SetWindowPos(window, nullptr, 0, 0, 0, 0,
                    SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                        SWP_FRAMECHANGED)) {
    return false;
  }

  if (maximize_on_exit) {
    ShowWindow(window, SW_MAXIMIZE);

    WINDOWPLACEMENT placement{};
    placement.length = sizeof(placement);
    if (!GetWindowPlacement(window, &placement)) return false;
    placement.rcNormalPosition =
        window_placement_before_fullscreen_.rcNormalPosition;
    if (!SetWindowPlacement(window, &placement)) return false;
  } else {
    WINDOWPLACEMENT placement = window_placement_before_fullscreen_;
    placement.length = sizeof(placement);
    placement.showCmd = SW_SHOWNORMAL;
    if (!SetWindowPlacement(window, &placement)) return false;
  }

  is_fullscreen_ = false;
  return true;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_GETMINMAXINFO) {
    auto* min_max_info = reinterpret_cast<MINMAXINFO*>(lparam);
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    if (min_max_info != nullptr && GetMonitorInfo(monitor, &monitor_info)) {
      min_max_info->ptMaxPosition.x =
          monitor_info.rcWork.left - monitor_info.rcMonitor.left;
      min_max_info->ptMaxPosition.y =
          monitor_info.rcWork.top - monitor_info.rcMonitor.top;
      min_max_info->ptMaxSize.x =
          monitor_info.rcWork.right - monitor_info.rcWork.left;
      min_max_info->ptMaxSize.y =
          monitor_info.rcWork.bottom - monitor_info.rcWork.top;
      return 0;
    }
  }

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
