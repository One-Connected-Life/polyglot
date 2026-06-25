class AddDrillRecallFirstToUsers < ActiveRecord::Migration[8.1]
  def change
    # Default drill direction as a PERSISTED preference (coordinator addition to
    # Finding A): recall-first (recognition) means the target word is shown and
    # you recall the source — e.g. NL→EN — the easier recognition path, and the
    # new default. false = production (source→target, e.g. EN→NL, harder).
    # When /play gets no explicit from/to override, this pref picks the direction.
    add_column :users, :drill_recall_first, :boolean, default: true, null: false
  end
end
