module Api
  module V1
    # POST /api/v1/audio_decks (multipart: audio + label) → enqueues
    # ExtractDeckFromAudioJob. Mirrors AudioDecksController#create: stage the
    # upload in the gitignored tmp dir, the job transcribes + extracts + DELETES
    # the file (audio is never persisted — privacy is load-bearing, issue 3).
    class AudioDecksController < BaseController
      MAX_BYTES = 25.megabytes
      ALLOWED = %w[.m4a .mp3 .wav .ogg .flac .aac .mp4].freeze

      def create
        unless current_user.can_generate?
          return render json: { error: "generation_cap_reached", cap: User::GENERATION_CAP },
                        status: :unprocessable_entity
        end

        file = params[:audio]
        if file.blank?
          return render json: { error: "audio_required" }, status: :unprocessable_entity
        end

        ext = File.extname(file.original_filename.to_s).downcase
        if ALLOWED.exclude?(ext)
          return render json: { error: "unsupported_file_type", allowed: ALLOWED }, status: :unprocessable_entity
        end
        if file.size > MAX_BYTES
          return render json: { error: "file_too_large", max_mb: MAX_BYTES / 1.megabyte },
                        status: :unprocessable_entity
        end

        path = stage(file, ext)
        label = params[:label].to_s.strip
        filename = File.basename(file.original_filename.to_s, ".*").presence || "Audio deck"
        deck = current_user.decks.create!(
          name:     label.presence || filename.titleize,
          status:   "transcribing",
          position: (current_user.decks.maximum(:position) || -1) + 1
        )
        current_user.increment!(:generations_count)
        ExtractDeckFromAudioJob.perform_later(deck, path.to_s)

        render json: {
          deck: {
            id:     deck.id,
            slug:   deck.slug,
            name:   deck.name,
            status: deck.status,
          }
        }, status: :accepted
      end

      private

      def stage(file, ext)
        dir = Rails.root.join("tmp/audio_uploads")
        FileUtils.mkdir_p(dir)
        path = dir.join("#{SecureRandom.uuid}#{ext}")
        File.binwrite(path, file.read)
        path
      end
    end
  end
end
