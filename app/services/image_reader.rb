# Read target-language text out of an uploaded image (issue #10) via Claude vision —
# a snapped sign, menu, letter, or screenshot. The extracted text is fed straight into
# the Translate pipeline (Translator → capture). PRIVACY: the image bytes live only in
# memory for the duration of the request and are NEVER written to disk or persisted —
# same posture as audio. No tesseract, no ActiveStorage.
class ImageReader
  include AnthropicMessages

  Error = Class.new(StandardError)

  MODEL = "claude-haiku-4-5-20251001" # vision-capable, cheap
  MAX_BYTES = 10 * 1024 * 1024
  ALLOWED = %w[image/jpeg image/png image/gif image/webp].freeze

  def initialize(user, uploaded_file)
    @user = user
    @file = uploaded_file
  end

  # Returns the transcribed target-language text, or "" when there's nothing to read.
  def call
    return "" if @file.blank?

    media_type = @file.content_type.to_s
    raise Error, "unsupported image type" unless ALLOWED.include?(media_type)
    bytes = @file.read
    raise Error, "image too large" if bytes.bytesize > MAX_BYTES

    data = Base64.strict_encode64(bytes)
    response = post_message(system_prompt, content(media_type, data), model: MODEL, max_tokens: 1500)
    message_text(response).strip
  end

  private

  def system_prompt
    "You transcribe text from images for a language learner. Output only the transcribed text, no commentary."
  end

  def content(media_type, data)
    target = @user.target_language_name
    [
      { "type" => "image", "source" => { "type" => "base64", "media_type" => media_type, "data" => data } },
      { "type" => "text", "text" =>
        "This image contains #{target} text (a sign, menu, letter, label, or screenshot). " \
        "Transcribe the #{target} words and phrases you can see, preserving line breaks. " \
        "Do NOT translate. Do NOT add commentary. If there is no #{target} text, output nothing." }
    ]
  end
end
