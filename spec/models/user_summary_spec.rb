# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# The profile "Summary" tab. All three lists are built from queries that already
# join `topics`, and the plugin adds `(category_id NOT IN ... OR user_id IN ...)`
# to each of them.
describe UserSummary do
  fab!(:author, :user)
  fab!(:viewer, :user)
  fab!(:private_category) { private_topics_category }
  fab!(:private_topic) { Fabricate(:topic, user: author, category: private_category) }
  fab!(:public_topic) { Fabricate(:topic, user: author) }

  before { SiteSetting.private_topics_enabled = true }

  def summary_for(target, viewer)
    UserSummary.new(target, Guardian.new(viewer))
  end

  describe "#topics" do
    it "hides other people's private topics from a visitor" do
      expect(summary_for(author, viewer).topics).to include(public_topic)
      expect(summary_for(author, viewer).topics).not_to include(private_topic)
    end

    it "shows a visitor their own private topics" do
      own = Fabricate(:topic, user: viewer, category: private_category)

      expect(summary_for(viewer, viewer).topics).to include(own)
    end

    it "shows a private topic whose author is in private_topics_permitted_groups" do
      SiteSetting.private_topics_permitted_groups = private_topics_group(author).id.to_s

      expect(summary_for(author, viewer).topics).to include(private_topic)
    end

    it "shows everything to a member of the category's allowed groups" do
      member = Fabricate(:user)
      group = private_topics_group(member)
      private_category.upsert_custom_fields(
        "private_topics_allowed_groups" => group.id.to_s,
      )

      expect(summary_for(author, member).topics).to include(private_topic)
    end

    it "does not filter while the plugin is disabled" do
      SiteSetting.private_topics_enabled = false

      expect(summary_for(author, viewer).topics).to include(private_topic)
    end
  end

  describe "#replies" do
    fab!(:private_reply) do
      Fabricate(:post, topic: private_topic, user: author, post_number: 2)
    end
    fab!(:public_reply) do
      Fabricate(:post, topic: public_topic, user: author, post_number: 2)
    end

    it "hides replies in other people's private topics" do
      expect(summary_for(author, viewer).replies).to include(public_reply)
      expect(summary_for(author, viewer).replies).not_to include(private_reply)
    end

    it "keeps them in the author's own summary" do
      expect(summary_for(author, author).replies).to include(private_reply, public_reply)
    end
  end

  describe "#links" do
    fab!(:private_link) do
      Fabricate(:topic_link, topic: private_topic, post: Fabricate(:post, topic: private_topic, user: author), user: author)
    end
    fab!(:public_link) do
      Fabricate(:topic_link, topic: public_topic, post: Fabricate(:post, topic: public_topic, user: author), user: author)
    end

    it "hides links from other people's private topics" do
      expect(summary_for(author, viewer).links).to include(public_link)
      expect(summary_for(author, viewer).links).not_to include(private_link)
    end
  end
end
