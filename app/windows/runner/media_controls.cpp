#include "media_controls.h"

#include <flutter/standard_method_codec.h>
#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include <chrono>
#include <string>

namespace {

namespace foundation = winrt::Windows::Foundation;
namespace media = winrt::Windows::Media;
namespace streams = winrt::Windows::Storage::Streams;

using flutter::EncodableMap;
using flutter::EncodableValue;

std::wstring Widen(const std::string& text) {
  if (text.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), wide.data(), size);
  return wide;
}

std::string TextField(const EncodableMap& map, const char* key) {
  auto found = map.find(EncodableValue(key));
  if (found == map.end()) return {};
  const auto* text = std::get_if<std::string>(&found->second);
  return text ? *text : std::string();
}

int64_t NumberField(const EncodableMap& map, const char* key) {
  auto found = map.find(EncodableValue(key));
  if (found == map.end()) return 0;
  return found->second.LongValue();
}

foundation::TimeSpan Milliseconds(int64_t ms) {
  return std::chrono::duration_cast<foundation::TimeSpan>(std::chrono::milliseconds(ms));
}

constexpr WPARAM kPlay = 1;
constexpr WPARAM kPause = 2;
constexpr WPARAM kNext = 3;
constexpr WPARAM kPrevious = 4;

}  // namespace

struct MediaControls::Impl {
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  media::SystemMediaTransportControls controls{nullptr};
  winrt::event_token button_token{};
  winrt::event_token seek_token{};

  bool Connect(HWND window) {
    try {
      auto interop = winrt::get_activation_factory<media::SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
      winrt::check_hresult(interop->GetForWindow(window, winrt::guid_of<media::SystemMediaTransportControls>(), winrt::put_abi(controls)));
      controls.IsEnabled(false);
      controls.IsPlayEnabled(true);
      controls.IsPauseEnabled(true);
      controls.IsNextEnabled(true);
      controls.IsPreviousEnabled(true);
      button_token = controls.ButtonPressed([window](auto const&, media::SystemMediaTransportControlsButtonPressedEventArgs const& args) {
        WPARAM button = 0;
        switch (args.Button()) {
          case media::SystemMediaTransportControlsButton::Play: button = kPlay; break;
          case media::SystemMediaTransportControlsButton::Pause: button = kPause; break;
          case media::SystemMediaTransportControlsButton::Next: button = kNext; break;
          case media::SystemMediaTransportControlsButton::Previous: button = kPrevious; break;
          default: break;
        }
        if (button != 0) PostMessage(window, kButtonMessage, button, 0);
      });
      seek_token = controls.PlaybackPositionChangeRequested([window](auto const&, media::PlaybackPositionChangeRequestedEventArgs const& args) {
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(args.RequestedPlaybackPosition()).count();
        PostMessage(window, kSeekMessage, 0, static_cast<LPARAM>(ms));
      });
      return true;
    } catch (...) {
      controls = nullptr;
      return false;
    }
  }

  void Track(const EncodableMap& map) {
    if (!controls) return;
    try {
      auto updater = controls.DisplayUpdater();
      updater.ClearAll();
      updater.Type(media::MediaPlaybackType::Music);
      auto music = updater.MusicProperties();
      music.Title(Widen(TextField(map, "title")));
      music.Artist(Widen(TextField(map, "artist")));
      music.AlbumTitle(Widen(TextField(map, "album")));
      auto art = TextField(map, "art");
      if (!art.empty()) {
        updater.Thumbnail(streams::RandomAccessStreamReference::CreateFromUri(foundation::Uri(Widen(art))));
      }
      updater.Update();
      controls.IsEnabled(true);
    } catch (...) {
    }
  }

  void Playing(bool playing) {
    if (!controls) return;
    try {
      controls.PlaybackStatus(playing ? media::MediaPlaybackStatus::Playing : media::MediaPlaybackStatus::Paused);
    } catch (...) {
    }
  }

  void Timeline(const EncodableMap& map) {
    if (!controls) return;
    try {
      media::SystemMediaTransportControlsTimelineProperties timeline;
      timeline.StartTime(Milliseconds(0));
      timeline.MinSeekTime(Milliseconds(0));
      timeline.Position(Milliseconds(NumberField(map, "position")));
      timeline.MaxSeekTime(Milliseconds(NumberField(map, "duration")));
      timeline.EndTime(Milliseconds(NumberField(map, "duration")));
      controls.UpdateTimelineProperties(timeline);
    } catch (...) {
    }
  }

  void Clear() {
    if (!controls) return;
    try {
      controls.IsEnabled(false);
      controls.DisplayUpdater().ClearAll();
    } catch (...) {
    }
  }
};

MediaControls::MediaControls(flutter::BinaryMessenger* messenger, HWND window) : impl_(std::make_unique<Impl>()) {
  impl_->Connect(window);
  impl_->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "vortex/media", &flutter::StandardMethodCodec::GetInstance());
  Impl* impl = impl_.get();
  impl_->channel->SetMethodCallHandler([impl](const flutter::MethodCall<EncodableValue>& call, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto* map = std::get_if<EncodableMap>(call.arguments());
    const std::string& name = call.method_name();
    if (name == "track" && map) {
      impl->Track(*map);
    } else if (name == "timeline" && map) {
      impl->Timeline(*map);
    } else if (name == "playing") {
      const auto* playing = std::get_if<bool>(call.arguments());
      impl->Playing(playing && *playing);
    } else if (name == "clear") {
      impl->Clear();
    } else {
      result->NotImplemented();
      return;
    }
    result->Success();
  });
}

MediaControls::~MediaControls() {
  if (impl_->controls) {
    try {
      impl_->controls.ButtonPressed(impl_->button_token);
      impl_->controls.PlaybackPositionChangeRequested(impl_->seek_token);
      impl_->controls.IsEnabled(false);
    } catch (...) {
    }
  }
}

bool MediaControls::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kSeekMessage) {
    impl_->channel->InvokeMethod("seek", std::make_unique<EncodableValue>(static_cast<int32_t>(lparam)));
    return true;
  }
  if (message != kButtonMessage) return false;
  const char* method = wparam == kPlay ? "play" : wparam == kPause ? "pause" : wparam == kNext ? "next" : "previous";
  impl_->channel->InvokeMethod(method, nullptr);
  return true;
}
