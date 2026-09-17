# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# `Post.public_posts` is the scope the "public" post counts and feeds use. The
# plugin redefines it (via `self.prepended`) to drop posts from private
# categories, which is how those counts stay honest.
describe Post do
  fab!(:author, :user)

  before { SiteSetting.private_topics_enabled = true }

  it "excludes posts from private categories" do
    hidden = Fabricate(:post, user: author, topic: private_topics_topic(user: author))
    visible = Fabricate(:post, user: author, topic: Fabricate(:topic, user: author))

    expect(Post.public_posts).to include(visible)
    expect(Post.public_posts).not_to include(hidden)
  end

  it "keeps private message posts out, as core does" do
    pm = Fabricate(:private_message_post, user: author, recipient: Fabricate(:user))

    expect(Post.public_posts).not_to include(pm)
  end

  it "returns them while the plugin is disabled" do
    hidden = Fabricate(:post, user: author, topic: private_topics_topic(user: author))
    SiteSetting.private_topics_enabled = false

    expect(Post.public_posts).to include(hidden)
  end
end
