# AI-prefilled ease scores for a learner's vocabulary (#axis-4).
#
# This learner knows English + 3 Romance languages (French/Spanish/Italian via
# Dutch as the target). We pre-score each term on a 1–5 ease scale:
#   1 = trivially easy (English cognate or near-identical across known languages)
#   2 = clearly related
#   3 = moderate (default)
#   4 = hard (false friend, irregular, or no overlap)
#   5 = very hard
#
# In V1 we use a heuristic (string-distance cognate detection) rather than an
# LLM call — fast, offline, deterministic, good enough for the English-cognate
# skip. The output is the same data structure an LLM call would return, so
# the implementation can be swapped later.
#
# ENGLISH-COGNATE SKIP: terms that score ease=1 are auto-dropped from drilling
# rotation (they supersede the old manual skip_easy toggle). The user confirmed
# they don't want to waste time on "dokter"/"doctor"-style words.
#
# Usage:
#   scored = EasePrefillService.new(user).score(terms)
#   scored #=> [ { term_id:, ease: 1..5, cognate: true/false }, … ]
#
class EasePrefillService
  # Levenshtein ratio <= this → cognate (matches Term#difficulty :easy threshold).
  COGNATE_RATIO = 0.34

  def initialize(user)
    @user = user
  end

  # Returns an array of { term_id:, ease:, cognate: } for every term.
  # `terms` must be pre-loaded with translations (no extra queries issued here).
  def score(terms)
    terms.map { |term| score_term(term) }
  end

  # Convenience: upsert ease into Scheduling rows for a user, in a given drill
  # direction (defaults to the learner's primary target→source). Creates the
  # scheduling row (blank card, backfilled=false) if it doesn't exist yet.
  # Ease is symmetric (same word pair), so the same score applies either way.
  def upsert_ease!(terms, from: nil, to: nil)
    from ||= @user.target_language
    to   ||= @user.source_language

    score(terms).each do |scored|
      scheduling = Scheduling.find_or_initialize_by(
        user_id:       @user.id,
        term_id:       scored[:term_id],
        from_language: from,
        to_language:   to
      )
      scheduling.ease = scored[:ease]
      scheduling.save!
    end
  end

  private

  def score_term(term)
    # Sentences aren't cognate-scorable — Levenshtein over a whole phrase is noise
    # (and would mislabel long matching phrases as "easy"). Default to moderate
    # ease (3). A future easy/hard signal from the drill can refine this.
    return { term_id: term.id, ease: 3, cognate: false } if term.kind == "sentence"

    source_text = term.translation(@user.source_language)&.text
    target_text = term.translation(@user.target_language)&.text

    if source_text && target_text
      ratio   = levenshtein_ratio(normalize(source_text), normalize(target_text))
      cognate = ratio <= COGNATE_RATIO
      ease    = cognate ? 1 : ease_from_ratio(ratio)
    else
      cognate = false
      ease    = 3  # unknown → default moderate
    end

    { term_id: term.id, ease: ease, cognate: cognate }
  end

  # Map distance ratio to ease 2–5 (1 is reserved for cognates above).
  def ease_from_ratio(ratio)
    return 2 if ratio <= 0.50
    return 3 if ratio <= 0.65
    return 4 if ratio <= 0.80
    5
  end

  def normalize(string)
    Term.normalize_for_distance(string)
  end

  def levenshtein_ratio(a, b)
    return 0.0 if a == b
    return 1.0 if a.empty? || b.empty?
    Term.levenshtein(a, b).to_f / [a.length, b.length].max
  end
end
