require "open3"

# Web-hittable sanity check for the self-hosted transcription stack (issue 3), so prod
# can be verified over HTTP without shelling into the container.
#
#   GET /up/audio          → presence + binary-runs check (cheap)
#   GET /up/audio?deep=1    → also transcribes a tiny bundled clip end-to-end (~1-2s)
#
# Returns 200 when healthy, 503 otherwise. Public, like /up — reveals only booleans, not
# paths. (deep=1 runs whisper per hit; fine for a manual ping on a personal app.)
class AudioHealthController < ApplicationController
  allow_unauthenticated_access

  SAMPLE = Rails.root.join("lib/health/whisper_sample.m4a")

  def show
    checks = {
      ffmpeg: binary_runs?(ffmpeg_bin, "-version"),
      whisper_cli: binary_runs?(whisper_bin, "--help"),
      model: model_info,
    }
    checks[:transcribe] = transcribe_sample if params[:deep].present?

    ok = checks[:ffmpeg] && checks[:whisper_cli] && checks[:model][:present] &&
         (params[:deep].blank? || checks.dig(:transcribe, :ok))

    render json: { ok: ok, **checks }, status: (ok ? :ok : :service_unavailable)
  end

  private

  def binary_runs?(bin, *args)
    _out, status = Open3.capture2e(bin, *args)
    status.success?
  rescue StandardError
    false
  end

  def model_info
    path = ENV["WHISPER_MODEL"].presence || Transcriber::DEFAULT_MODEL
    present = File.exist?(path)
    { present: present, bytes: (present ? File.size(path) : nil) }
  end

  def transcribe_sample
    text = Transcriber.new(language: "nl").call(SAMPLE.to_s)
    { ok: text.present?, sample: text.to_s[0, 80] }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def ffmpeg_bin  = ENV["FFMPEG_BIN"].presence  || "ffmpeg"
  def whisper_bin = ENV["WHISPER_CLI"].presence || "whisper-cli"
end
