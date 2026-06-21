# Audio→vocab engine test harness (issue #3, docs/PRD-audio-to-vocab.md).
# Transcribes a local audio file with self-hosted Whisper, then previews the
# vocabulary deck the extractor would build from it — WITHOUT writing to the DB.
#
#   bin/rails "audio:preview[sample-audio/voicemail-1.m4a]"
#   bin/rails "audio:preview[sample-audio/voicemail-1.m4a,nl,en]"   # target, source
#
# Drop real audio in the gitignored sample-audio/ folder (never committed).
namespace :audio do
  desc "Transcribe an audio file and preview the extracted vocab deck (no DB write)"
  task :preview, [ :path, :target, :source ] => :environment do |_t, args|
    path   = args[:path] or abort "usage: bin/rails \"audio:preview[path/to/audio.m4a]\""
    target = (args[:target].presence || "nl")
    source = (args[:source].presence || "en")
    abort "no such file: #{path}" unless File.exist?(path)

    puts "\n== Transcribing #{path} (lang=#{target}) =="
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    transcript = Transcriber.new(language: target).call(path)
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
    puts "(#{elapsed}s)\n\n#{transcript}\n"

    unless ENV["ANTHROPIC_API_KEY"].present?
      puts "\n[skip extraction] ANTHROPIC_API_KEY not set — transcription only."
      next
    end

    puts "\n== Extracting vocabulary (#{target} → #{source}) =="
    user = User.new(target_language: target, source_language: source)
    deck = Deck.new(user: user, name: "preview", topic: nil)
    words = DeckGenerator.new(deck, transcript: transcript).candidate_words

    puts "#{words.size} candidate words:\n"
    words.each do |w|
      art  = w["article"].present? ? "#{w['article']} " : ""
      ipa  = w["ipa"].present? ? "  /#{w['ipa']}/" : ""
      puts "  • #{art}#{w['target']}  —  #{w['source']}#{ipa}"
      puts "      etym: #{w['etymology']}" if w["etymology"].present?
      puts "      mnem: #{w['mnemonic']}" if w["mnemonic"].present?
    end
    puts
  end
end
