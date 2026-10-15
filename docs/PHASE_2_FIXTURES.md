# Playback fixtures

Authored on 2026-10-14 using mathematical test patterns and a generated sine tone. No downloaded footage, people, music, fonts or third-party media assets are used. Fixture outputs are distributed under this repository's MIT license; FFmpeg and libx264 executables are not redistributed.

Run these commands from the repository root with a developer-installed FFmpeg. They overwrite only the named authored fixtures (`-y`). The app/SDK does not execute FFmpeg.

```sh
ffmpeg -y -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440:sample_rate=48000 -t 8 -c:v libx264 -pix_fmt yuv420p -preset fast -crf 30 -c:a aac -b:a 64k -movflags +faststart example/assets/media/sample.mp4
ffmpeg -y -f lavfi -i testsrc2=size=180x320:rate=24 -t 3 -c:v libx264 -pix_fmt yuv420p -crf 32 -an example/assets/media/silent.mp4
ffmpeg -y -display_rotation 90 -i example/assets/media/sample.mp4 -c copy example/assets/media/rotated.mp4
ffmpeg -y -f lavfi -i testsrc2=size=160x90:rate=10 -t 600 -c:v libx264 -pix_fmt yuv420p -crf 38 -an example/assets/media/long.mp4
ffmpeg -y -i example/assets/media/sample.mp4 -vn -c:a copy example/assets/media/audio.m4a
ffprobe -v error -select_streams v:0 -show_entries stream=width,height:stream_side_data=rotation -of json example/assets/media/rotated.mp4
```

`empty.mp4` is zero bytes. `corrupt.mp4` is plain text, deliberately not video. The rotation fixture has stored 640×360 pixels plus a 90-degree display matrix; public metadata must report 360×640.

These small H.264/AAC fixtures establish functional decoding, metadata and clock behavior, not HDR/HEVC/VFR/4K support, memory stability under production workloads, or measured lip-sync. The ten-minute fixture is for distant seeking; a 60-second probe does not imply that ten minutes of playback were observed.
