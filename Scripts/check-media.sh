#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache"
swift build --disable-sandbox --scratch-path build/swift-package --cache-path build/package-cache
mkdir -p build
fixture_dir=$(mktemp -d "$PWD/build/media-check.XXXXXX")
probe="$PWD/build/swift-package/debug/MediaProbe"
say -v Samantha -r 155 -o "$fixture_dir/speech.aiff" 'Hello, my name is John Smith. Today we are testing local video transcription. Every word stays on this Mac. The final sentence is complete.'
afconvert -f WAVE -d LEF32@48000 "$fixture_dir/speech.aiff" "$fixture_dir/speech-48.wav"
"$probe" generate "$fixture_dir/stereo.mp4" "$fixture_dir/speech-48.wav" 22 2 2
"$probe" decode "$fixture_dir/stereo.mp4" | tee "$fixture_dir/decode.txt"
"$probe" generate "$fixture_dir/silent.mp4" "$fixture_dir/speech.aiff" 5 0 1 silent
"$probe" decode "$fixture_dir/silent.mp4" | tee "$fixture_dir/silent-decode.txt"
"$probe" generate "$fixture_dir/no-audio.mp4" "$fixture_dir/speech.aiff" 3 0 0
if "$probe" inspect "$fixture_dir/no-audio.mp4"; then
    echo "Missing audio was not rejected" >&2; exit 1
fi
printf 'invalid media' > "$fixture_dir/corrupt.mp4"
if "$probe" inspect "$fixture_dir/corrupt.mp4"; then
    echo "Corrupt media was not rejected" >&2; exit 1
fi
python3 - "$fixture_dir" <<'PY'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
decoded = (root / 'decode.txt').read_text()
assert 'audio tracks: 2' in decoded
end = float(re.search(r'end: ([0-9.]+)', decoded)[1])
assert abs(end - 22) < .025, end
audible = float(re.search(r'audible: ([0-9.]+)', decoded)[1])
assert 2 <= audible < 2.2, audible
assert 'audible: -1' in (root / 'silent-decode.txt').read_text()
print('Media decoding checks passed')
PY
if [[ "${1:-}" == "--speech" ]]; then
    "$probe" transcribe "$fixture_dir/stereo.mp4" "$fixture_dir/transcript.txt"
    "$probe" transcribe "$fixture_dir/silent.mp4" "$fixture_dir/silence.txt"
    python3 - "$fixture_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
text = (root / 'transcript.txt').read_text().lower()
assert 'john smith' in text
assert 'final sentence is complete' in text
assert not (root / 'silence.txt').read_text().strip()
print('On-device transcription checks passed')
PY
    python3 Scripts/check-content.py "$fixture_dir/transcript.txt"
fi
echo "Fixture results: $fixture_dir"
