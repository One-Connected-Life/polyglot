# Daily sweep: delete Translate-audio clips past the 2-day retention (#16). Destroying
# the Recording purges its attached audio blob (has_one_attached → dependent purge).
# Scheduled in config/recurring.yml. Idempotent: once destroyed a clip falls out of scope.
class RecordingSweepJob < ApplicationJob
  queue_as :default

  def perform
    Recording.expired.find_each(&:destroy)
  end
end
