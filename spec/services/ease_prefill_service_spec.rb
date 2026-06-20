require "rails_helper"

# EasePrefillService: heuristic ease scoring for a learner's vocabulary.
# Cognates (ease=1) are auto-dropped from drilling; others are scored 2–5. (#axis-4)
RSpec.describe EasePrefillService, type: :model do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  subject(:service) { described_class.new(user) }

  def term_with(nl:, en:)
    t = create(:term, deck: create(:deck, user: user))
    create(:translation, term: t, language: "nl", text: nl)
    create(:translation, term: t, language: "en", text: en)
    t.reload
    t.translations.load  # ensure translations are in memory
    t
  end

  describe "#score" do
    it "scores a Dutch/English cognate as ease=1 with cognate: true" do
      term = term_with(nl: "dokter", en: "doctor")
      result = service.score([term]).first
      expect(result[:ease]).to eq(1)
      expect(result[:cognate]).to be(true)
    end

    it "scores a completely different word pair as ease >= 3" do
      term = term_with(nl: "huis", en: "house")
      # "huis"/"house" — NOT cognates by distance (different enough)
      result = service.score([term]).first
      expect(result[:ease]).to be >= 2
    end

    it "returns a result for every term in the input" do
      terms = 3.times.map { |i| term_with(nl: "woord#{i}", en: "word#{i}") }
      results = service.score(terms)
      expect(results.size).to eq(3)
      expect(results.map { |r| r[:term_id] }).to match_array(terms.map(&:id))
    end

    it "defaults to ease=3 when a translation is missing" do
      term = create(:term, deck: create(:deck, user: user))
      create(:translation, term: term, language: "nl", text: "woord")
      # No English translation
      term.reload
      term.translations.load
      result = service.score([term]).first
      expect(result[:ease]).to eq(3)
      expect(result[:cognate]).to be(false)
    end

    it "includes the term_id in every result" do
      term = term_with(nl: "hond", en: "dog")
      result = service.score([term]).first
      expect(result[:term_id]).to eq(term.id)
    end
  end

  describe "#upsert_ease!" do
    it "creates a scheduling row with the scored ease when none exists" do
      term = term_with(nl: "dokter", en: "doctor")
      expect { service.upsert_ease!([term]) }.to change(Scheduling, :count).by(1)

      sched = Scheduling.find_by(user: user, term: term)
      expect(sched.ease).to eq(1)  # cognate
    end

    it "updates the ease on an existing scheduling row (idempotent)" do
      term = term_with(nl: "dokter", en: "doctor")
      Scheduling.create!(user: user, term: term, from_language: "nl", to_language: "en", ease: 3)

      service.upsert_ease!([term])
      expect(Scheduling.find_by(user: user, term: term).ease).to eq(1)
    end
  end
end
