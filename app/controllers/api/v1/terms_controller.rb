module Api
  module V1
    # Per-word detail + FSRS hand-tweaks.
    #   GET   /api/v1/terms/:id           — term + all translations + attempt history
    #   PATCH /api/v1/terms/:id/ease      — nudge ease 1–5 (mirrors SchedulingsController#nudge)
    #   PATCH /api/v1/terms/:id/unretire  — bring back from the retired shelf (#unretire)
    class TermsController < BaseController
      def show
        term = current_user.terms.includes(:translations).find(params[:id])
        render json: { term: term_json(term) }
      end

      # PATCH /api/v1/terms/:id/ease { ease, from, to }
      def ease
        term = current_user.terms.find(params[:id])
        scheduling = current_user.schedulings.find_or_initialize_by(
          term_id:       term.id,
          from_language: params[:from].presence || current_user.target_language,
          to_language:   params[:to].presence   || current_user.source_language
        )
        scheduling.nudge_ease!(params[:ease])
        render json: { id: term.id, ease: scheduling.ease }
      end

      # PATCH /api/v1/terms/:id/unretire — direction is target→source (the shelf direction).
      def unretire
        term = current_user.terms.find(params[:id])
        scheduling = current_user.schedulings.find_by(
          term_id:       term.id,
          from_language: current_user.target_language,
          to_language:   current_user.source_language
        )
        scheduling&.unretire!
        render json: { id: term.id, unretired: scheduling.present? }
      end

      private

      def term_json(term)
        {
          id:   term.id,
          kind: term.kind,
          translations: term.translations.map do |t|
            {
              lang:         t.language,
              lang_name:    t.language_name,
              text:         t.text,
              article:      t.article,
              with_article: t.with_article,
              ipa:          t.ipa,
              translit:     t.translit,
              non_latin:    t.non_latin?,
              etymology:    t.etymology.presence,
              mnemonic:     t.mnemonic.presence,
              alternates:   t.alternate_list,
            }
          end,
          attempts: term.attempts.order(:id).map do |a|
            {
              id:         a.id,
              from:       a.from_language,
              to:         a.to_language,
              correct:    a.correct,
              given:      a.given,
              created_at: a.created_at.iso8601,
            }
          end,
        }
      end
    end
  end
end
