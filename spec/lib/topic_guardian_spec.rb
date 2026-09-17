# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# `TopicGuardian#can_see_topic?` is the gate everything else leans on: topic
# lists, search, the post stream and direct URLs all end up asking it.
#
# The plugin patches it with an `alias_method` + redefinition (the thing we want
# to replace with `prepend` later), so these specs are the behaviour we must
# keep identical through that refactor.
describe Guardian do
  fab!(:author, :user)
  fab!(:other_member, :user)

  before { SiteSetting.private_topics_enabled = true }

  def can_see?(user, topic)
    user ? Guardian.new(user).can_see_topic?(topic) : Guardian.new.can_see_topic?(topic)
  end

  describe "a topic in a category with private topics" do
    fab!(:category) { private_topics_category }
    fab!(:topic) { Fabricate(:topic, user: author, category: category) }

    it "is visible to its author" do
      expect(can_see?(author, topic)).to eq(true)
    end

    it "is hidden from another member" do
      expect(can_see?(other_member, topic)).to eq(false)
    end

    it "is hidden from an anonymous visitor" do
      expect(can_see?(nil, topic)).to eq(false)
    end

    it "is visible when its author belongs to private_topics_permitted_groups" do
      # The setting is about who *started* the topic, not about who is looking.
      group = private_topics_group(author)
      SiteSetting.private_topics_permitted_groups = group.id.to_s

      expect(can_see?(other_member, topic)).to eq(true)
    end

    it "is visible to a member of the category's allowed groups" do
      member = Fabricate(:user)
      group = private_topics_group(member)
      topic.update!(category: private_topics_category(allowed_groups: [group]))

      expect(can_see?(member, topic.reload)).to eq(true)
      expect(can_see?(other_member, topic)).to eq(false)
    end

    it "is visible again while the plugin is disabled" do
      SiteSetting.private_topics_enabled = false

      expect(can_see?(other_member, topic)).to eq(true)
    end

    describe "admins" do
      fab!(:admin, :admin)

      it "can see it by default" do
        expect(SiteSetting.private_topics_admin_sees_all).to eq(true)
        expect(can_see?(admin, topic)).to eq(true)
      end

      it "cannot see it when private_topics_admin_sees_all is off" do
        SiteSetting.private_topics_admin_sees_all = false

        expect(can_see?(admin, topic)).to eq(false)
      end
    end
  end

  describe "a topic in an ordinary category" do
    fab!(:topic) { Fabricate(:topic, user: author) }

    it "is unaffected" do
      private_topics_category # the plugin is on, but this category is not private

      expect(can_see?(other_member, topic)).to eq(true)
      expect(can_see?(nil, topic)).to eq(true)
    end
  end

  describe "private messages" do
    fab!(:pm) { Fabricate(:private_message_post, user: author, recipient: other_member) }

    it "keeps core's behaviour for participants" do
      expect(can_see?(author, pm.topic)).to eq(true)
      expect(can_see?(other_member, pm.topic)).to eq(true)
    end

    it "keeps core's behaviour for everybody else" do
      expect(can_see?(Fabricate(:user), pm.topic)).to eq(false)
      expect(can_see?(nil, pm.topic)).to eq(false)
    end
  end

  describe "a deleted topic" do
    fab!(:topic) do
      Fabricate(:topic, user: author, category: private_topics_category).tap do |t|
        t.update!(deleted_at: 1.minute.ago)
      end
    end

    it "keeps core's answer exactly, with the plugin on or off" do
      # Core hides deleted topics from regular members - authors included - and
      # all this plugin does is add filtering on top, so nothing may become
      # visible here.
      expect(can_see?(author, topic)).to eq(false)
      expect(can_see?(other_member, topic)).to eq(false)

      SiteSetting.private_topics_enabled = false

      expect(can_see?(author, topic)).to eq(false)
      expect(can_see?(other_member, topic)).to eq(false)
    end
  end
end
