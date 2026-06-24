class GenerateSentencesJob < ApplicationJob
  queue_as :default

  # Refreshes the user's "Recent sentences" pool from the words they've recently practiced.
  # Fire-and-forget from the drill (see DrillsController#play): never blocks a drill, and a
  # failed generation just leaves the existing/seeded sentences in place.
  def perform(user)
    SentenceGenerator.new(user).call
  rescue StandardError => e
    Rails.logger.error("[GenerateSentencesJob] user=#{user&.id} #{e.class}: #{e.message}")
  end
end
