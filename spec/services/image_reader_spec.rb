require "rails_helper"

RSpec.describe ImageReader do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  def upload(content_type: "image/jpeg", bytes: "fakeimagebytes")
    instance_double("ActionDispatch::Http::UploadedFile",
                    content_type: content_type, read: bytes, blank?: false)
  end

  def canned(text)
    { "content" => [{ "type" => "text", "text" => text }] }
  end

  it "returns the transcribed text from the model" do
    reader = ImageReader.new(user, upload)
    allow(reader).to receive(:post_message).and_return(canned("brood\nkaas"))

    expect(reader.call).to eq("brood\nkaas")
  end

  it "sends the image as a base64 vision block" do
    reader = ImageReader.new(user, upload(bytes: "abc"))
    expect(reader).to receive(:post_message) do |_system, content, **_opts|
      img = content.find { |b| b["type"] == "image" }
      expect(img.dig("source", "media_type")).to eq("image/jpeg")
      expect(img.dig("source", "data")).to eq(Base64.strict_encode64("abc"))
      canned("brood")
    end
    reader.call
  end

  it "rejects an unsupported content type" do
    expect { ImageReader.new(user, upload(content_type: "application/pdf")).call }
      .to raise_error(ImageReader::Error)
  end

  it "rejects an oversized image" do
    big = upload(bytes: "x" * (ImageReader::MAX_BYTES + 1))
    expect { ImageReader.new(user, big).call }.to raise_error(ImageReader::Error)
  end

  it "returns '' when there's no file" do
    expect(ImageReader.new(user, nil).call).to eq("")
  end
end
