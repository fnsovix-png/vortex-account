#ifndef RUNNER_MEDIA_CONTROLS_H_
#define RUNNER_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Connects Vortex to the Windows media card in Quick Settings and the volume
// flyout, and to the keyboard's media keys.
class MediaControls {
 public:
  // Posted to the window from Windows' thread when a media button is used.
  static constexpr UINT kButtonMessage = WM_APP + 71;
  static constexpr UINT kSeekMessage = WM_APP + 72;

  MediaControls(flutter::BinaryMessenger* messenger, HWND window);
  ~MediaControls();

  // Returns true when the message belonged to this class.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
