class DecksController < ApplicationController
  def new
    @deck = current_user.decks.new
  end

  def create
    unless current_user.can_generate?
      redirect_to new_deck_path, alert: "You've reached your deck-generation limit (#{User::GENERATION_CAP})."
      return
    end

    attrs = params.require(:deck).permit(:topic, :label)
    topic = attrs[:topic].to_s.strip
    if topic.blank?
      redirect_to new_deck_path, alert: "Tell me a topic to build a deck from."
      return
    end

    label = attrs[:label].to_s.strip
    deck = current_user.decks.create!(
      name: label.presence || topic.titleize,
      topic: topic,
      status: "pending",
      position: (current_user.decks.maximum(:position) || -1) + 1
    )
    current_user.increment!(:generations_count)
    GenerateDeckJob.perform_later(deck)

    redirect_to root_path, notice: "Building your “#{deck.name}” deck — it'll appear in a moment."
  end

  def destroy
    # Deck#to_param is the slug, so the :id route segment carries the slug.
    current_user.decks.find_by!(slug: params[:id]).destroy
    redirect_to root_path, notice: "Deck removed."
  end

  # Generate an additional cohort of words for an existing topic deck. Runs in the
  # background; new words land reviewed: false and surface in the review screen.
  def expand
    deck = current_user.decks.find_by!(slug: params[:id])

    unless current_user.can_generate?
      return redirect_to root_path,
        alert: "You've reached your deck-generation limit (#{User::GENERATION_CAP})."
    end
    if deck.topic.blank?
      return redirect_to root_path,
        alert: "“#{deck.name}” wasn't built from a topic, so I can't auto-add more words to it."
    end
    if deck.expanding?
      return redirect_to root_path, notice: "Already adding words to “#{deck.name}” — hang tight."
    end

    deck.update!(expanding: true)
    current_user.increment!(:generations_count)
    ExpandDeckJob.perform_later(deck)
    redirect_to root_path, notice: "Adding more “#{deck.name}” words — they'll appear to review shortly."
  end

  # Prune/edit the candidate words awaiting review — a brand-new deck's whole word
  # list, or a fresh cohort appended to a drillable deck (issue #3 / add-more).
  def review
    @deck  = current_user.decks.find_by!(slug: params[:id])
    @terms = @deck.pending_review_terms.includes(:translations)
    redirect_to root_path, alert: "Nothing to review for that deck." unless @deck.needs_review?
  end

  # Apply the review: drop unchecked words, save edits, mark the rest reviewed
  # (drillable). Only touches the cohort under review — never already-drilling words.
  def update_review
    deck   = current_user.decks.find_by!(slug: params[:id])
    target = current_user.target_language
    source = current_user.source_language
    keep   = Array(params[:keep]).map(&:to_i).to_set

    deck.pending_review_terms.includes(:translations).find_each do |term|
      unless keep.include?(term.id)
        term.destroy
        next
      end
      term.update!(reviewed: true)
      edits = params.dig(:terms, term.id.to_s)
      next if edits.blank?

      term.translation(target)&.update(text: edits[:target]) if edits[:target].present?
      term.translation(source)&.update(text: edits[:source]) if edits[:source].present?
    end

    if deck.terms.reload.any?
      deck.update!(status: "ready")
      redirect_to play_path(deck: deck.slug, from: source, to: target),
        notice: "“#{deck.name}” saved — start drilling."
    else
      deck.destroy
      redirect_to root_path, notice: "No words kept — deck discarded."
    end
  end
end
