require "net/http"
require "uri"
require "json"

# Shared Anthropic Messages API plumbing (issue #10). Net::HTTP, no gem.
# Mix into a service/job that needs to call the model; keep the `post_message`
# instance-method name so specs can stub it with allow_any_instance_of(...).
module AnthropicMessages
  ENDPOINT = "https://api.anthropic.com/v1/messages"

  # content: a String (plain prompt) or an Array of content blocks (e.g. for vision).
  # Returns the parsed JSON response hash.
  def post_message(system, content, model:, max_tokens: 4000)
    uri = URI(ENDPOINT)
    req = Net::HTTP::Post.new(uri)
    req["x-api-key"] = anthropic_api_key
    req["anthropic-version"] = "2023-06-01"
    req["content-type"] = "application/json"
    # content is a String (plain prompt) or an Array of content blocks (e.g. vision).
    req.body = JSON.generate(
      model: model,
      max_tokens: max_tokens,
      system: system,
      messages: [{ role: "user", content: content }]
    )

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 90, open_timeout: 15) do |http|
      http.request(req)
    end
    raise anthropic_error_class, "Anthropic API #{res.code}: #{res.body.to_s.first(300)}" unless res.code.to_i == 200

    JSON.parse(res.body)
  end

  # Pull the first text block out of a Messages response.
  def message_text(response)
    response.dig("content", 0, "text").to_s
  end

  # Models sometimes wrap JSON in ```json fences despite instructions; strip them.
  def strip_fences(text)
    text.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "").strip
  end

  def anthropic_api_key
    ENV["ANTHROPIC_API_KEY"].presence || raise(anthropic_error_class, "ANTHROPIC_API_KEY is not set")
  end

  # Including classes may define their own Error; default to RuntimeError.
  def anthropic_error_class
    self.class.const_defined?(:Error) ? self.class.const_get(:Error) : RuntimeError
  end
end
