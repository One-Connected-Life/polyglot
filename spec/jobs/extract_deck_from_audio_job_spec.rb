require "rails_helper"

# ExtractDeckFromAudioJob (issue #3): transcribe → extract → land in "review", and
# ALWAYS delete the staged audio afterward (privacy decision D2). Transcriber and
# DeckGenerator are stubbed — their own behavior is covered elsewhere.
RSpec.describe ExtractDeckFromAudioJob, type: :job do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  let(:deck) { create(:deck, user: user, status: "transcribing") }
  let(:audio_path) { Rails.root.join("tmp/audio_uploads/test-#{SecureRandom.hex}.m4a").to_s }

  before do
    FileUtils.mkdir_p(File.dirname(audio_path))
    File.binwrite(audio_path, "fake audio bytes")
  end

  after { File.delete(audio_path) if File.exist?(audio_path) }

  it "transcribes, extracts to review, and deletes the audio" do
    allow_any_instance_of(Transcriber).to receive(:call).and_return("Heeft u een afspraak?")
    fake_gen = instance_double(DeckGenerator)
    expect(DeckGenerator).to receive(:new)
      .with(deck, transcript: "Heeft u een afspraak?", final_status: "review")
      .and_return(fake_gen)
    expect(fake_gen).to receive(:call)

    described_class.perform_now(deck, audio_path)

    expect(File.exist?(audio_path)).to be(false)
  end

  it "marks the deck failed with a reason when there's no speech" do
    allow_any_instance_of(Transcriber).to receive(:call)
      .and_raise(Transcriber::Error, "no speech detected in the audio")

    described_class.perform_now(deck, audio_path)

    expect(deck.reload.status).to eq("failed")
    expect(deck.status_detail).to eq("no speech detected in the audio")
    expect(File.exist?(audio_path)).to be(false)
  end

  it "deletes the audio even when extraction errors" do
    allow_any_instance_of(Transcriber).to receive(:call).and_return("transcript")
    allow_any_instance_of(DeckGenerator).to receive(:call).and_raise(DeckGenerator::Error, "boom")

    described_class.perform_now(deck, audio_path)

    expect(deck.reload.status).to eq("failed")
    expect(File.exist?(audio_path)).to be(false)
  end
end
