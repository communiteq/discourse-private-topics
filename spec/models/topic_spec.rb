# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# The class-level `Topic` methods the plugin patches. All three of these are
# `alias_method` patches today (two of them) plus one wholesale replacement, so
# they are part of the refactor surface.
describe Topic do
  fab!(:author, :user)
  fab!(:viewer, :user)

  before do
    SiteSetting.private_topics_enabled = true
    SearchIndexer.enable
  end

  after { SearchIndexer.disable }

  describe ".recent" do
    it "excludes topics in private categories" do
      private_topics_topic(user: author)
      visible = Fabricate(:topic)

      expect(Topic.recent(10)).to contain_exactly(visible)
    end

    it "includes them while the plugin is disabled" do
      private_topics_topic(user: author)
      visible = Fabricate(:topic)
      SiteSetting.private_topics_enabled = false

      expect(Topic.recent(10)).to include(visible)
      expect(Topic.recent(10).count).to eq(2)
    end
  end

  describe ".for_digest" do
    # `for_digest` ignores topics created inside the editing grace period.
    before { SiteSetting.editing_grace_period = 0 }

    it "excludes other people's topics in private categories" do
      private_topics_topic(user: author)
      visible = Fabricate(:topic)

      expect(Topic.for_digest(viewer, 1.year.ago, top_order: true)).to contain_exactly(
        visible,
      )
    end

    it "keeps the viewer's own private topics" do
      own = private_topics_topic(user: viewer)

      expect(Topic.for_digest(viewer, 1.year.ago, top_order: true)).to contain_exactly(
        own,
      )
    end

    it "does not filter anything while the plugin is disabled" do
      other = private_topics_topic(user: author)
      SiteSetting.private_topics_enabled = false

      expect(Topic.for_digest(viewer, 1.year.ago, top_order: true)).to include(other)
    end
  end

  describe ".similar_to" do
    it "excludes other people's topics in private categories" do
      private_category = private_topics_category
      hidden =
        Fabricate(
          :topic_with_op,
          title: "Distinctive private title AlfaBravo",
          category: private_category,
          user: author,
        )
      visible =
        Fabricate(
          :topic_with_op,
          title: "Distinctive public title AlfaBravo",
          user: author,
        )

      results = Topic.similar_to("Distinctive title AlfaBravo", "AlfaBravo body", viewer)

      expect(results).to include(visible)
      expect(results).not_to include(hidden)
    end

    it "keeps the viewer's own private topics" do
      private_category = private_topics_category
      own =
        Fabricate(
          :topic_with_op,
          title: "My own private title CharlieDelta",
          category: private_category,
          user: viewer,
        )

      results = Topic.similar_to("My own private title CharlieDelta", "CharlieDelta body", viewer)

      expect(results).to include(own)
    end
  end
end
