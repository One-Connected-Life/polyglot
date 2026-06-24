class AddOmniauthToUsers < ActiveRecord::Migration[8.1]
  def change
    # `name` already exists on users; only add the OAuth-specific columns.
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_column :users, :avatar_url, :string

    # A user is uniquely identified by (provider, uid) within a provider.
    # Partial index so the many email/password users (provider = NULL, uid = NULL)
    # don't all collide on a single NULL/NULL row.
    add_index :users, [:provider, :uid], unique: true,
              where: "provider IS NOT NULL AND uid IS NOT NULL",
              name: "index_users_on_provider_and_uid"

    # OAuth users have no password — make the digest nullable. Email/password
    # users still get one set by has_secure_password.
    change_column_null :users, :password_digest, true
  end
end
