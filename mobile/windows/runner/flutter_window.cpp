#include "flutter_window.h"

#include <optional>
#include <windows.h>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT WM_TRAYICON = WM_USER + 101;
constexpr UINT IDM_TRAY_SHOW = 1001;
constexpr UINT IDM_TRAY_EXIT = 1002;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::ShowAndRestoreWindow() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else {
    ShowWindow(hwnd, SW_SHOW);
  }
  SetForegroundWindow(hwnd);

  if (flutter_controller_) {
    flutter_controller_->ForceRedraw();
  }
}

void FlutterWindow::HideWindow() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  ShowWindow(hwnd, SW_HIDE);

  if (!balloon_shown_) {
    balloon_shown_ = true;
    ShowTrayBalloon(L"Memento", L"Memento \u5df2\u6700\u5c0f\u5316\u5230\u6258\u76d8\uff0c\u5c06\u5728\u540e\u53f0\u6301\u7eed\u8fd0\u884c\u3002");
  }
}

void FlutterWindow::ShowTrayBalloon(const std::wstring& title, const std::wstring& msg) {
  if (!tray_icon_created_) return;
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(NOTIFYICONDATAW);
  nid.hWnd = GetHandle();
  nid.uID = 1;
  nid.uFlags = NIF_INFO;
  nid.dwInfoFlags = NIIF_INFO;
  wcscpy_s(nid.szInfoTitle, title.c_str());
  wcscpy_s(nid.szInfo, msg.c_str());
  Shell_NotifyIconW(NIM_MODIFY, &nid);
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // 1. 初始化并添加系统托盘图标
  memset(&tray_icon_data_, 0, sizeof(NOTIFYICONDATAW));
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = 1;
  tray_icon_data_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_data_.uCallbackMessage = WM_TRAYICON;
  tray_icon_data_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_data_.szTip, L"Memento");

  if (Shell_NotifyIconW(NIM_ADD, &tray_icon_data_)) {
    tray_icon_created_ = true;
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

  bool start_minimized = false;
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv) {
    for (int i = 1; i < argc; ++i) {
      if (wcscmp(argv[i], L"--minimized") == 0 ||
          wcscmp(argv[i], L"--silent") == 0 ||
          wcscmp(argv[i], L"-m") == 0) {
        start_minimized = true;
        break;
      }
    }
    LocalFree(argv);
  }

  flutter_controller_->engine()->SetNextFrameCallback([&, start_minimized]() {
    if (!start_minimized) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (tray_icon_created_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
    tray_icon_created_ = false;
  }

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

    case WM_CLOSE:
      if (!force_close_) {
        // 用户点击右上角的 "X"，拦截并最小化到系统托盘
        HideWindow();
        return 0;
      }
      break;

    case WM_QUERYENDSESSION:
      // 系统关机或注销时允许退出
      force_close_ = true;
      return TRUE;

    case WM_TRAYICON: {
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          if (IsWindowVisible(hwnd) && !IsIconic(hwnd)) {
            HWND fg = GetForegroundWindow();
            if (fg == hwnd) {
              HideWindow();
            } else {
              ShowAndRestoreWindow();
            }
          } else {
            ShowAndRestoreWindow();
          }
          break;

        case WM_RBUTTONUP:
        case WM_CONTEXTMENU: {
          POINT pt;
          GetCursorPos(&pt);
          HMENU hMenu = CreatePopupMenu();
          AppendMenuW(hMenu, MF_STRING, IDM_TRAY_SHOW, L"\u663e\u793a Memento");
          AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
          AppendMenuW(hMenu, MF_STRING, IDM_TRAY_EXIT, L"\u9000\u51fa\u7a0b\u5e8f");

          SetForegroundWindow(hwnd);
          int cmd = TrackPopupMenu(hMenu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                                   pt.x, pt.y, 0, hwnd, nullptr);
          DestroyMenu(hMenu);

          if (cmd == IDM_TRAY_SHOW) {
            ShowAndRestoreWindow();
          } else if (cmd == IDM_TRAY_EXIT) {
            force_close_ = true;
            Destroy();
          }
          break;
        }
      }
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
