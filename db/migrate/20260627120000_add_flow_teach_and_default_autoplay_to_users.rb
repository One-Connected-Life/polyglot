class AddFlowTeachAndDefaultAutoplayToUsers < ActiveRecord::Migration[8.1]
  def up
    # Flow mode now teaches on the answer beat: etymology/mnemonic + phonetics,
    # not just the bare translation. Default ON — review 13 (pronunciation) and
    # 14 (etymology) are the richest learning and should be present by default.
    add_column :users, :flow_teach, :boolean, default: true, null: false

    # Pronunciation first-class (review 13): make hearing the word the default.
    # New users default autoplay_prompt ON, and backfill the handful of existing
    # users to true. Still reversible in Settings.
    change_column_default :users, :autoplay_prompt, from: false, to: true
    User.reset_column_information
    User.update_all(autoplay_prompt: true)
  end

  def down
    remove_column :users, :flow_teach
    change_column_default :users, :autoplay_prompt, from: true, to: false
  end
end
