<div align="center">

  <img src="assets/icon/app_icon.png" width="120" height="120" alt="Lumino Logo" style="border-radius: 24px;" />

  # Lumino
  ### Next-Generation Movie & TV Streaming Platform

  [![Flutter Version](https://img.shields.io/badge/Flutter-%3E%3D3.10.1-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
  [![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android-FFB561?style=for-the-badge&logo=windows&logoColor=black)](https://github.com/Sanjeev1412-official/Lumino__Movie_Streaming)
  [![Version](https://img.shields.io/badge/Version-v1.3.3-brightgreen?style=for-the-badge)](https://github.com/Sanjeev1412-official/Lumino__Movie_Streaming/releases/latest)
  [![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)

  <p align="center">
    A premium, high-performance streaming application engineered with Flutter and <code>libmpv</code>. Stream movies, TV series, and live television with ultra-fast multi-source providers, 4K auto-quality selection, multi-language audio tracks, and hardware-accelerated playback.
  </p>

  <p align="center">
    <a href="https://github.com/Sanjeev1412-official/Lumino__Movie_Streaming/releases/latest">
      <img src="https://img.shields.io/badge/Download%20for-Windows%20(.exe)-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Download Windows" />
    </a>
    &nbsp;&nbsp;
    <a href="https://github.com/Sanjeev1412-official/Lumino__Movie_Streaming/releases/latest">
      <img src="https://img.shields.io/badge/Download%20for-Android%20(.apk)-3DDC84?style=for-the-badge&logo=android&logoColor=black" alt="Download Android" />
    </a>
  </p>

  [⬇️ Download Latest](#-download--installation) • [✨ Features](#-key-features) • [🛠️ Tech Stack](#-tech-stack--architecture) • [🔨 Building From Source](#-building-from-source)

</div>

---

## 🚀 Download & Installation

Get the latest stable release directly for your operating system:

| Platform | Format | Direct Download Link |
|---|---|---|
| 💻 **Windows** (x64) | Setup Installer (`.exe`) | [**⬇️ Download Windows Installer (Latest)**](https://github.com/Sanjeev1412-official/Lumino__Movie_Streaming/releases/latest) |
| 📱 **Android** (Universal) | Standalone Package (`.apk`) | [**⬇️ Download Android APK (Latest)**](https://github.com/Sanjeev1412-official/Lumino__Movie_Streaming/releases/latest) |

> 💡 **Tip**: You can also browse all past versions, release notes, and assets on the [**GitHub Releases Page**](https://github.com/Sanjeev1412-official/Lumino__Movie_Streaming/releases).

---

## ✨ Key Features

* **Hardware-Accelerated Playback**: Powered by `media_kit` and `libmpv` for smooth decoding of 4K UHD, HDR, and high-bitrate media.
* **High-Speed HTTP Streaming**: Integrated support for premium HTTP sources (MovieBox, Pixeldrain, FSL, 10Gbps).
* **Live TV Channels**: Browse live television categories and stream IPTV broadcasts directly inside the player.
* **Cross-Device Sync & History**: Automatically remembers playback timestamps, episode completions, and syncs watch progress seamlessly via Supabase backend.
* **In-App Auto-Updates**: Native auto-updater integration for both Windows (WinSparkle) and Android (in-app APK installer).

---

## 🛠️ Tech Stack & Architecture

| Layer | Technology |
|---|---|
| **Framework** | [Flutter](https://flutter.dev) (Dart 3.x) |
| **Media Engine** | [media_kit](https://github.com/media-kit/media-kit) (`libmpv` native bindings) |
| **Backend & Auth** | [Supabase](https://supabase.com) (Database, Auth & Storage) |
| **Networking & HTTP** | `http`, `dio`, `connectivity_plus` |
| **UI & Icons** | `google_fonts`, `hugeicons`, `lottie` animations |
| **Storage & Caching** | `shared_preferences`, `sqflite`, `cached_network_image` |
| **Platform Integration** | `flutter_volume_controller`, `screen_brightness`, `wakelock_plus` |

---

## 🔨 Building From Source

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.10.1`)
* [Visual Studio](https://visualstudio.microsoft.com/) with *Desktop development with C++* (for Windows builds)
* [Android Studio](https://developer.android.com/studio) with Android SDK (for Android builds)

### 1. Clone the repository
```bash
git clone https://github.com/Sanjeev1412-official/Lumino__Movie_Streaming.git
cd Lumino__Movie_Streaming
```

### 2. Install dependencies
```bash
flutter pub get
```

### 3. Run on desktop or connected mobile device
```bash
# Windows
flutter run -d windows

# Android
flutter run -d android
```

### 4. Build Release Artifacts
```bash
# Build Windows Release
flutter build windows --release

# Build Android APK
flutter build apk --release
```

---

## 🔒 Security & Privacy
* Private keys, credentials, and local browser cache directories are excluded from this repository.
* When self-hosting or building, provide your own TMDB and Supabase API credentials in environment variables or service configuration files.

---

## 📄 License
Distributed under the **MIT License**. See `LICENSE` for more information.

<div align="center">
  <sub>Engineered with ❤️ for cinematic experiences on desktop and mobile.</sub>
</div>
