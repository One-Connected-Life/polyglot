module Api
  module V1
    # Deck management for native clients. Mirrors DecksController, but returns JSON
    # (and JSON errors) instead of redirect/flash. :id route segment carries the
    # slug (Deck#to_param), same as the web side.
    class DecksController < BaseController
      # GET /api/v1/decks — the user's decks (drill home list).
      def index
        decks = current_user.decks.includes(:terms).order(:position)
        render json: { decks: decks.map { |d| deck_json(d) } }
      end

      # POST /api/v1/decks { topic, label } → enqueues GenerateDeckJob.
      def create
        unless current_user.can_generate?
          return render json: { error: "generation_cap_reached", cap: User::GENERATION_CAP },
                        status: :unprocessable_entity
        end

        attrs = params.require(:deck).permit(:topic, :label)
        topic = attrs[:topic].to_s.strip
        if topic.blank?
          return render json: { error: "topic_required" }, status: :unprocessable_entity
        end

        label = attrs[:label].to_s.strip
        deck = current_user.decks.create!(
          name:     label.presence || topic.titleize,
          topic:    topic,
          status:   "pending",
          position: (current_user.decks.maximum(:position) || -1) + 1
        )
        current_user.increment!(:generations_count)
        GenerateDeckJob.perform_later(deck)

        render json: { deck: deck_json(deck) }, status: :accepted
      end

      # DELETE /api/v1/decks/:id (:id = slug)
      def destroy
        current_user.decks.find_by!(slug: params[:id]).destroy
        head :no_content
      end

      # POST /api/v1/decks/:id/expand → enqueues ExpandDeckJob (mirrors guards).
      def expand
        deck = current_user.decks.find_by!(slug: params[:id])

        unless current_user.can_generate?
          return render json: { error: "generation_cap_reached", cap: User::GENERATION_CAP },
                        status: :unprocessable_entity
        end
        if deck.topic.blank?
          return render json: { error: "deck_has_no_topic" }, status: :unprocessable_entity
        end
        if deck.expanding?
          return render json: { error: "already_expanding", deck: deck_json(deck) }, status: :conflict
        end

        deck.update!(expanding: true)
        current_user.increment!(:generations_count)
        ExpandDeckJob.perform_later(deck)
        render json: { deck: deck_json(deck) }, status: :accepted
      end

      # GET /api/v1/decks/:id/review — the cohort awaiting review.
      def review
        deck = current_user.decks.find_by!(slug: params[:id])
        unless deck.needs_review?
          return render json: { error: "nothing_to_review" }, status: :unprocessable_entity
        end
        terms = deck.pending_review_terms.includes(:translations)
        render json: { deck: deck_json(deck), terms: terms.map { |t| review_term_json(t) } }
      end

      # PATCH /api/v1/decks/:id/review { keep: [id...], terms: { "id" => { target:, source: } } }
      # Mirrors DecksController#update_review: drop unkept, save edits, mark reviewed.
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
          render json: { deck: deck_json(deck), status: "saved" }
        else
          deck.destroy
          render json: { status: "discarded" }
        end
      end

      private

      def deck_json(deck)
        {
          id:                   deck.id,
          slug:                 deck.slug,
          name:                 deck.name,
          topic:                deck.topic,
          status:               deck.status,
          status_detail:        deck.status_detail,
          expanding:            deck.expanding,
          position:             deck.position,
          word_count:           deck.terms.count { |t| t.reviewed },
          needs_review:         deck.needs_review?,
          pending_review_count: deck.pending_review_count,
        }
      end

      def review_term_json(term)
        target = current_user.target_language
        source = current_user.source_language
        {
          id:        term.id,
          kind:      term.kind,
          target:    term.translation(target)&.with_article,
          source:    term.translation(source)&.with_article,
          etymology: term.translation(target)&.etymology.presence,
          mnemonic:  term.translation(target)&.mnemonic.presence,
        }
      end
    end
  end
end
