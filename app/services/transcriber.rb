require "open3"
require "tmpdir"

# Self-hosted speech→text via whisper.cpp (`whisper-cli`). Audio never leaves
# infrastructure we control — this is the privacy-preserving path chosen in
# docs/PRD-audio-to-vocab.md (D1), because the motivating input is medical/official
# voicemails.
#
# whisper-cli only accepts flac/mp3/ogg/wav, and real voicemails are usually .m4a,
# so we always normalize to 16kHz mono WAV with ffmpeg first.
class Transcriber
  Error = Class.new(StandardError)

  # Overridable so production (Docker image) and dev can point at different paths.
  DEFAULT_MODEL = File.expand_path("~/.local/share/whisper-models/ggml-medium.bin")

  # language: ISO code Whisper should decode as ("nl", "en", ...) or "auto" to detect.
  def initialize(language: "nl")
    @language = language.to_s.presence || "auto"
  end

  # path: a source audio file (m4a/mp3/wav/…). Returns the transcript as a String.
  def call(path)
    raise Error, "audio file not found: #{path}" unless File.exist?(path)

    Dir.mktmpdir("polyglot-transcribe") do |dir|
      wav = File.join(dir, "audio.wav")
      to_wav(path, wav)
      transcribe(wav, File.join(dir, "out"))
    end
  end

  private

  def to_wav(src, dst)
    out, status = Open3.capture2e(
      ffmpeg_bin, "-nostdin", "-y", "-i", src.to_s,
      "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", dst
    )
    unless status.success? && File.exist?(dst)
      raise Error, "ffmpeg could not decode the audio: #{out.to_s.split("\n").last(3).join(' ')}"
    end
  end

  def transcribe(wav, out_base)
    out, status = Open3.capture2e(
      whisper_bin, "-m", model_path, "-l", @language,
      "-otxt", "-nt", "-of", out_base, "-f", wav
    )
    txt = "#{out_base}.txt"
    unless status.success? && File.exist?(txt)
      raise Error, "whisper-cli failed: #{out.to_s.split("\n").last(3).join(' ')}"
    end

    transcript = File.read(txt).strip
    raise Error, "transcript was empty" if transcript.blank?
    transcript
  end

  def ffmpeg_bin  = ENV["FFMPEG_BIN"].presence  || "ffmpeg"
  def whisper_bin = ENV["WHISPER_CLI"].presence || "whisper-cli"

  def model_path
    path = ENV["WHISPER_MODEL"].presence || DEFAULT_MODEL
    return path if File.exist?(path)

    raise Error, "Whisper model not found at #{path} — set WHISPER_MODEL or download a ggml model."
  end
end
