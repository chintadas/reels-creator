# reels-creator

An iOS SwiftUI application for turning selected iPhone photos and videos into 9:16 Instagram Reels with crossfades, optional beat-sync, custom audio or Instagram audio preparation, and a store logo outro.

## Features

- **Photos & Videos Selection**: Multi-select photos and videos from your iPhone Photos library via `PhotosPicker`, reorder clips, and configure photo display duration.
- **Audio Modes**:
  - **No Music (Add in IG)**: Keeps original video clip audio so you can attach trending music inside Instagram.
  - **Custom Audio Track**: Extract the audio track from a video in iPhone Photos, automatically muting original video clip audio and fading out at the end.
- **Polish & Transitions**: Configurable crossfade transitions between clips and optional beat-sync (`Accelerate` / `vDSP_rmsqv` onset detection) that snaps photo durations to detected beats. Photos use static 1080×1920 center crop (no Ken Burns motion).
- **Intro Text Overlay**: Optional 3-second white centered multi-line intro text with soft drop shadow, live 9:16 preview, and smooth fade-in/fade-out over opening clips (stops automatically before any outro).
- **Store Logo Outro**: Append either a static store logo image (PNG) centered over a custom branded background color or a pre-made outro video clip (`.mp4`/`.mov`).
- **Export & Share**: Renders 1080×1920 `.mp4` on-device via `AVFoundation`, previews in-app, saves directly to iPhone Photos, and opens the iOS Share Sheet.

## Tech Stack & Requirements

- iOS 17.0+
- Xcode 16.0+
- Swift 5.0+ / Swift Concurrency (`async/await`) + Observation (`@Observable`)
- Pure Apple Frameworks: `SwiftUI`, `PhotosUI`, `Photos`, `AVFoundation`, `AVKit`, `Accelerate`

## Project Structure

```text
reels-creator/
├── reels-creator.xcodeproj
├── ReelsCreatorCore/              # Local SwiftPM package (models, beat-snapper, timeline planner & tests)
│   ├── Package.swift
│   ├── Sources/ReelsCreatorCore/
│   │   ├── Models/                # MediaClipSpec, AudioSelectionMode, OutroSelectionMode, ReelPolishSettings
│   │   └── Timeline/              # BeatSnapper, TimelinePlanner
│   └── Tests/ReelsCreatorCoreTests/
└── reels-creator/                 # iOS App Target
    ├── App/
    │   └── ReelsCreatorApp.swift
    ├── Models/
    │   └── SelectedMediaItem.swift
    ├── Services/
    │   ├── AudioBeatDetector.swift
    │   ├── IntroTextOverlayRenderer.swift
    │   ├── PhotoLibrarySaver.swift
    │   ├── ReelVideoComposer.swift
    │   ├── StillImageVideoGenerator.swift
    │   └── VideoAudioExtractor.swift
    ├── ViewModels/
    │   └── ReelCreatorViewModel.swift
    ├── Views/
    │   ├── ExportResultSheet.swift
    │   └── ReelCreatorView.swift
    ├── Resources/
    │   └── Assets.xcassets
    └── Info.plist
```

## Testing & Building

Run the unit tests and iOS build verification script:

```bash
./scripts/run_all_tests.sh
```

Or open `reels-creator.xcodeproj` in Xcode and run on your iPhone or iOS Simulator.
