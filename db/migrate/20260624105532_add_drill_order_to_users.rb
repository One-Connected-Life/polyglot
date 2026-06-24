class AddDrillOrderToUsers < ActiveRecord::Migration[8.1]
  def change
    # How drill cards are ordered: "smart" = FSRS due-order (most-overdue / new first) with
    # ties randomized; "shuffle" = fully random. Default smart. (#drill-order)
    add_column :users, :drill_order, :string, default: "smart", null: false
  end
end
