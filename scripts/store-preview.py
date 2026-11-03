#!/usr/bin/env python3
"""Cuts Ghost Thread's app preview from scripts/store-capture.sh --video's clips.

    scripts/store-preview.py <clips dir> <out.mp4>            # iPhone: 1920x886 (the 6.9", 6.3" and iPhone Duo slots)
    scripts/store-preview.py --ipad <clips dir> <out.mp4>     # iPad: 1600x1200 (the 13-inch iPad's slot)

Each clip is a window of seconds around its moment (CLIPS), joined with short crossfades, with the race's own sound
under it (Kraig: "Game sound"). A new best lap sits in the middle (Kraig: "have a new best lap in the middle"), and it
ends with the payoff (Kraig: "a little racing and the lap finishing, the leaderboard appearing, and the challenge"): one
clip of a gold medal lap crossing the line, its session's standing coming up, and over that, dimmed, the challenge a
line at a time (ENDING), in the screenshots' lettering. Apple's format: H.264 High 4.0 at 30 fps and about 11 Mbps, stereo 256 kbps AAC at 48 kHz, 15-30 seconds.

The simulator records an iPhone's screen upright, so it's turned back to landscape; an expanded Dynamic Island the
system draws while the game's sound plays sits at its left edge, in the strip the HUD keeps clear for the island, so
that strip is cropped off. An iPad simulator held upright shows the game in a band across the middle, which is
cropped out.
"""
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# (clip, seconds before its moment, seconds after): the line through Harbor's S-bend, your ghost and the rival into
# Swirl's hairpin, a new best lap on Snake, the track list, then the ending in one clip: racing into the line at
# Ardennes for a gold medal, its banner a moment, and the session's standing coming up (its moment), held for the
# challenge (the race is held under the summary, so its last frame lasts as long as needed).
CLIPS = [
    ("line", -1.5, 3.5),
    ("ghosts", -3.0, 2.5),
    ("best", -3.0, 2.3),
    ("circuits", -2.0, 1.0),
    ("standing", -5.0, 6.5),
]
# The challenge over the standing, a line at a time from this long after it comes up, the last held to the end.
ENDING = ["CAN YOU TOP THE LEADERBOARD?", "CAN YOU BEAT THE GHOST?", "CHALLENGE YOUR FRIENDS"]
ENDING_AFTER = 2.0
ENDING_LINE = 1.5
ENDING_FADE = 0.25
ENDING_DIM = 0.55
# The screenshots' lettering (scripts/store-frames.py): SF Rounded Black, leaning as the logo does.
FONT = "/System/Library/Fonts/SFNSRounded.ttf"
SLANT = 0.21
FADE = 0.3
RATE = 48000
# The iPhone's left edge, in the recording's pixels, where an expanded Dynamic Island can show: inside the HUD's safe
# area (62 points of the 6.9" screen's 3x pixels is 186), so only track and grass go with it.
ISLAND_STRIP = 160


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height", "-of", "json", str(path)], check=True, capture_output=True).stdout
    stream = json.loads(out)["streams"][0]
    return stream["width"], stream["height"]


def picture(width, height, ipad):
    """The filter that turns a recording into the preview's picture."""
    if ipad:
        # Upright, the iPad shows the landscape game in a 4:3 band across the middle.
        band = width * 3 // 4
        return f"crop={width}:{band}:0:{(height - band) // 2},scale=1600:1200:flags=lanczos"
    # Upright, the iPhone's landscape screen is turned a quarter: turn it back, then crop off the island's strip and
    # enough from the bottom to keep 1920x886's shape (the HUD keeps clear of both).
    landscape_w, landscape_h = height, width
    keep_w = landscape_w - ISLAND_STRIP
    keep_h = round(keep_w * 886 / 1920)
    return (f"transpose=2,crop={keep_w}:{keep_h}:{ISLAND_STRIP}:0,scale=1920:886:flags=lanczos")


def challenge(text, size):
    """A line of the challenge, as a picture the size of the preview: the words across the middle, leaning, over a soft
    shadow; the screen under them is dimmed separately, once, so the lines change over it."""
    width, height = size
    unit = min(width / 1920, height / 886)
    canvas = Image.new("RGBA", size)
    middle = height // 2
    font_size = round(96 * unit)
    while True:
        font = ImageFont.truetype(FONT, font_size)
        font.set_variation_by_name("Black")
        if font.getlength(text) <= width * 0.86:
            break
        font_size -= 4

    def lean(layer):
        return layer.transform(size, Image.AFFINE, (1, SLANT, -SLANT * middle, 0, 1, 0), resample=Image.BICUBIC)

    shadow = Image.new("RGBA", size)
    ImageDraw.Draw(shadow).text((width // 2, middle + 5 * unit), text, font=font, fill=(0, 0, 0, 170), anchor="mm")
    canvas.alpha_composite(lean(shadow).filter(ImageFilter.GaussianBlur(9 * unit)))
    letters = Image.new("RGBA", size)
    ImageDraw.Draw(letters).text((width // 2, middle), text, font=font, fill=(255, 255, 255, 255), anchor="mm")
    canvas.alpha_composite(lean(letters))
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--ipad", action="store_true")
    parser.add_argument("clips", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()

    length = sum(after - before for _, before, after in CLIPS) - FADE * (len(CLIPS) - 1)
    if not 15 <= length <= 30:
        sys.exit(f"the preview would be {length:.1f}s; Apple allows 15-30s")

    inputs, parts = [], []
    for index, (name, before, after) in enumerate(CLIPS):
        meta = json.loads((args.clips / f"{name}.json").read_text())
        movie = args.clips / f"{name}.mov"
        width, height = probe(movie)
        start = meta["mark"] - meta["video"] + before
        if start < 0:
            sys.exit(f"{name}: the recording starts {-start:.1f}s too late for this clip")
        inputs += ["-i", str(movie)]
        video_input = sum(1 for flag in inputs if flag == "-i") - 1
        # The simulator records a frame only when the screen changes, so a still screen (the track list) ends its
        # recording early: its last frame holds for as long as the clip needs.
        parts.append(f"[{video_input}:v]tpad=stop_mode=clone:stop_duration=30,"
                     f"trim={start:.3f}:{start + after - before:.3f},setpts=PTS-STARTPTS,"
                     f"fps=30,{picture(width, height, args.ipad)},setsar=1[v{index}]")
        duration = after - before
        sound = args.clips / f"{name}.caf"
        if meta.get("sound") is not None and sound.exists():
            inputs += ["-i", str(sound)]
            sound_input = sum(1 for flag in inputs if flag == "-i") - 1
            offset = meta["mark"] - meta["sound"] + before
            # Before the sound began (the race's first moments), silence.
            lead = max(0.0, -offset)
            parts.append(f"[{sound_input}:a]aformat=sample_rates={RATE}:channel_layouts=stereo,"
                         f"atrim={max(0.0, offset):.3f}:{offset + duration:.3f},asetpts=PTS-STARTPTS,"
                         f"adelay={round(lead * 1000)}:all=1,apad,atrim=0:{duration:.3f}[a{index}]")
        else:
            # The track list plays no sound.
            parts.append(f"anullsrc=r={RATE}:cl=stereo,atrim=0:{duration:.3f}[a{index}]")

    video, audio, offset = "v0", "a0", 0.0
    for index in range(1, len(CLIPS)):
        offset += CLIPS[index - 1][2] - CLIPS[index - 1][1] - FADE
        parts.append(f"[{video}][v{index}]xfade=transition=fade:duration={FADE}:offset={offset:.3f}[vx{index}]")
        parts.append(f"[{audio}][a{index}]acrossfade=d={FADE}[ax{index}]")
        video, audio = f"vx{index}", f"ax{index}"
    # The challenge, over the standing: the screen dims, then each line fades in and out in turn, the last staying to
    # the end.
    size = (1600, 1200) if args.ipad else (1920, 886)
    pictures = Path(tempfile.mkdtemp(prefix="ghost-thread-preview-"))
    ending_start = length - CLIPS[-1][2] + ENDING_AFTER
    dim_path = pictures / "dim.png"
    Image.new("RGBA", size, (0, 0, 0, round(255 * ENDING_DIM))).save(dim_path)
    inputs += ["-loop", "1", "-t", f"{length - ending_start:.3f}", "-i", str(dim_path)]
    dim_input = sum(1 for flag in inputs if flag == "-i") - 1
    parts.append(f"[{dim_input}:v]format=rgba,fade=t=in:st=0:d={ENDING_FADE}:alpha=1,"
                 f"setpts=PTS-STARTPTS+{ending_start:.3f}/TB[dim]")
    parts.append(f"[{video}][dim]overlay=eof_action=pass[vdim]")
    video = "vdim"
    for index, text in enumerate(ENDING):
        picture_path = pictures / f"challenge-{index}.png"
        challenge(text, size).save(picture_path)
        start = ending_start + index * ENDING_LINE
        last = index == len(ENDING) - 1
        duration = length - start if last else ENDING_LINE
        inputs += ["-loop", "1", "-t", f"{duration:.3f}", "-i", str(picture_path)]
        picture_input = sum(1 for flag in inputs if flag == "-i") - 1
        fades = f"fade=t=in:st=0:d={ENDING_FADE}:alpha=1"
        if not last:
            fades += f",fade=t=out:st={duration - ENDING_FADE:.3f}:d={ENDING_FADE}:alpha=1"
        parts.append(f"[{picture_input}:v]format=rgba,{fades},setpts=PTS-STARTPTS+{start:.3f}/TB[c{index}]")
        parts.append(f"[{video}][c{index}]overlay=eof_action=pass[vc{index}]")
        video = f"vc{index}"
    parts.append(f"[{video}]format=yuv420p[vout]")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(parts),
         "-map", "[vout]", "-map", f"[{audio}]", "-r", "30",
         "-c:v", "libx264", "-profile:v", "high", "-level", "4.0", "-b:v", "11M", "-maxrate", "12M",
         "-bufsize", "24M", "-c:a", "aac", "-b:a", "256k", "-ar", str(RATE), "-ac", "2",
         "-movflags", "+faststart", str(args.out)],
        check=True,
    )
    print(f"{args.out}: {length:.1f}s")


main()
