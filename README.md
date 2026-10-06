# Apocalipse Music Pack (Build 42)

This is a music-radio foundation, with a station registration, independent song
modules, timed local lyrics, and generic between-song radio talk. It depends on
`apocalipsebrradio` (ApocalipseBRRadio). No music files are included yet; the
station stays silent until you register at least one song.

## Files

- `Apocalipse-Music-Pack/42/mod.info`: B42 metadata and radio dependency.
- `Apocalipse-Music-Pack/common/media/lua/shared/ApocalipseMusic/AMPStation.lua`:
  station name/frequency (94.2 FM), color, talk probability, and talk variants.
- `.../AMPRegistry.lua`: shared catalog, validation, and compact protocol.
- `.../Songs/<song-id>.lua`: one registration module per imported song, including
  title, artist, real duration, audio chunks, and timestamped lyrics.
- `common/media/lua/server/ApocalipseMusic/AMPServer.lua`: server/SP authority.
- `common/media/lua/client/ApocalipseMusic/AMPClient.lua`: listener audio/captions.
- `common/media/scripts/AMP_<song-id>.txt` and
  `common/media/sound/ApocalipseMusic/<song-id>/`: generated audio definitions/assets.

The radio framework itself is not modified. This station has no ABR scheduled
transmissions: its separate scheduler uses real seconds rather than game minutes.
Do not add `ABRRadio.triggerImmediate` or regular ABR transmissions to this station;
those would compete with the music scheduler.

## Import a song

Install Node.js and make `ffmpeg` and `ffprobe` available on PATH. From this folder:

```powershell
npm run import:music -- --input "Z:\Music\song.ogg" --id mypack_song01 --title "Song title" --artist "Artist" --lyrics examples/lyrics.json
npm run build
```

`--lyrics` is optional. `--chunk-seconds 5` is the default (allowed: 1–30).
The importer reads the audio duration with ffprobe, splits/re-encodes audio into
Vorbis chunks, and generates a Lua song module and B42 sound script. It refuses
to overwrite an existing ID. IDs must be unique across installed packs, with
1–24 ASCII letters, digits, underscores, or hyphens; use a pack prefix.

Lyrics JSON is an ordered array of cues, measured in seconds from song start:

```json
[
  { "at": 12.5, "untilTime": 17.0, "text": { "EN": "A lyric line", "PTBR": "Uma linha da letra" } },
  { "at": 18.0, "untilTime": 22.5, "text": "Another line" }
]
```

`untilTime` is optional for song lyrics: without it, a cue is eligible for four
seconds, capped at the next cue or song end. A song module can override this
default with `lyricDuration`. Set `untilTime` for an exact lyric window.
Only add cues where lyrics actually occur; no blank entries are needed for
instrumental sections. Omit `lyrics` or use an empty array for instrumental songs.
Playback commands continue every two seconds for the entire song, independently
of whether any lyric is available. A late listener receives only a currently
eligible cue, without replaying earlier lyrics. Expiry prevents old lyrics from
appearing on late tuning; it does not erase an already displayed vanilla chat
bubble. Talk lines default to lasting until the next talk line or segment end.
Radio language
uses the existing ABR server language setting (EN/PTBR). This is radio content,
so every listener resolves the same language.

For manual whole-file registration, see `examples/song.lua.example`. Supply a
non-looping sound script and audio asset before enabling that module. Whole-file
songs play for listeners present at song start; a late listener gets captions
but waits until the next song for audio. Use generated chunks for mid-song audio.

## Listening and scheduling

The authority picks a weighted song, avoids consecutive repeats when possible,
and waits its entire declared real duration before choosing the next segment.
It may choose one weighted talk variant between songs (35% by default), then
returns to music. Talk consists of locally resolved timed text. You can add
variants with `ApocalipseMusic.registerTalk` in separate shared files.

Only radios receiving this frequency start listener playback. Inventory radios
must be equipped; world/vehicle radios must be within local listening range.
Volume follows the radio slider and distance, with headphone ownership and deaf
players checked. Turning off, muting, retuning, leaving range, or losing
heartbeats for eight seconds stops audio and releases its dedicated emitter.
Music does not replace the radio's own static/VOIP emitter. Native radio signal
handling remains responsible for zombie attraction; custom music is local audio.

With chunks, a listener tuning in midway waits for the next chunk boundary
(normally less than five seconds after receiving the first heartbeat). Heartbeats
arrive every two seconds, so total tune-in delay can approach seven seconds.
No one restarts the song from the beginning. Missing a boundary by more than
250 ms skips that chunk rather than starting it at the wrong position. This is
approximate synchronization, not sample-accurate streaming: chunk transitions,
audio buffering, and network latency require an in-game listening check.

## Compact radio protocol

The native transmission text is empty. The `codes` field carries:

```text
AMP1|mypack_song01|1790000000001|123
```

Fields: protocol version, stable content ID, monotonically increasing broadcast
sequence, elapsed deciseconds (123 = 12.3 seconds). The station comes from the
receiving radio's frequency and the catalog. Song position determines the audio
chunk and lyric index; no lyrics, labels, paths, or per-line commands go on wire.
The same format handles talk IDs. Repeated heartbeats never restart an active
chunk or repeat a displayed cue. A sequence change replaces the current segment.
Unknown IDs/versions and older positions/sequences are ignored.

Each heartbeat is a complete current-state command, allowing late tuning and
recovery from packet loss without listener reports or server/client round trips.
The native packet is still distributed by PZ before its radio reception checks;
this does not reduce vanilla delivery to only tuned network connections.
Weather interference may strip effect codes in native `SendTransmission`;
listeners then time out and resume at a later valid chunk boundary when signal
returns. The catalog and audio assets must match on server and clients.

## More packs and stations

Extra catalog mods can depend on `Apocalipse-Music-Pack` and place song modules,
sound scripts, and assets in their own B42 `common/media` folders. Require
`ApocalipseMusic/AMPStation` before registering songs on `amp_music`. Use
`--mod <extra-mod-root>` to generate files in that pack, then supply its own
`42/mod.info` with `require=Apocalipse-Music-Pack`.

For a separate station, require `ApocalipseMusic/AMPRegistry` in a uniquely named
shared registration file and call `registerStation` with a new ID and unused
frequency. Require that registration file explicitly from its song modules
before calling `registerSong`. The importer accepts `--station <id>`; adjust
the generated module's require for that custom station. The generic server and
client controllers support all stations in the registry.

## Build and verify

```powershell
npm test
npm run build
```

Build output: `build/Contents/mods/Apocalipse-Music-Pack`. Copy that mod folder
into your B42 mods directory alongside ApocalipseBRRadio, enable both, and tune
an equipped/world/vehicle radio to 94.2 FM. The build script preserves the B42
layout instead of using the template's former B41 PZ Studio packager.

The Lua tests run through Fengari and simulate registry/protocol behavior,
lyrics and gaps, duplicate/stale packets, late joining, retuning, muting, range,
deafness, lost signal, and song/talk scheduling. They do not exercise Kahlua,
Java interop, FMOD playback, split-screen audio isolation, or multiplayer latency.
Before publishing, verify those in-game, including a second client tuning in
mid-song, battery/power loss, moving away from a world radio, and song transitions.

## Engine evidence and limits

Verified against the local decompiled B42 source:

- `zombie/radio/ZomboidRadio.java`, `SendTransmission` / `DistributeTransmission`:
  wave packets carry text, GUID and effect codes, not music files or sample data.
- `zombie/network/packets/WaveSignalPacket.java`: non-null empty text and codes
  are serialized independently; native receive handling delivers effect codes.
- `zombie/radio/devices/WaveSignalDevice.java`, `inventory/types/Radio.java`,
  `iso/objects/IsoWaveSignal.java`, `vehicles/VehiclePart.java`: reception triggers
  `OnDeviceText(guid, codes, x, y, z, text, device)`.
- `zombie/audio/BaseSoundEmitter.java`: exposed playback, local stop, volume,
  position and emitter tick; `setTimelinePosition(long, String)` takes a named
  marker, not a numeric position for ordinary audio files. No exposed numeric
  file seek was found. Therefore the implementation uses chunks.
- `zombie/iso/IsoWorld.java`: free emitters, explicit ownership and recycling.
- `zombie/GameTime.java`: `getRealworldSecondsSinceLastUpdate()` is independent
  of the game-time speed multiplier, so faster game time does not skip songs.

There is no engine audio broadcast/finished callback here. The server uses the
duration measured from the source audio; it does not wait on individual clients'
FMOD handles. Restarting the server starts a new song rather than restoring a
partly played broadcast. In local split-screen, headphone/private audio uses a
shared process mixer and cannot provide independent physical audio outputs.
