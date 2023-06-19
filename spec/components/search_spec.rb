# frozen_string_literal: true

require "rails_helper"

describe Search do
  before do
    SearchIndexer.enable
    SiteSetting.private_topics_enabled = true
  end

  after { SearchIndexer.disable }

  describe "filter topics from search" do
    fab!(:support_group_user) { Fabricate(:group_user) }
    fab!(:whitelisted_user) { Fabricate(:group_user) }
 
    fab!(:regular_user_1) { Fabricate(:user) }
    fab!(:regular_user_2) { Fabricate(:user) }
  
    fab!(:private_category) do
      category = Fabricate(:category)
      category.upsert_custom_fields("private_topics_enabled" => "true")
      category.upsert_custom_fields("private_topics_allowed_groups" => support_group_user.group.id)
      category
    end
  
    fab!(:regular_category) { Fabricate(:category) }
  
    it "filters category search results" do
      private_topic = Fabricate(:topic, category: private_category, user: regular_user_1) 
      private_post = Fabricate(:post, topic: private_topic, raw: "Support post FooBar A", user: regular_user_1)

      private_topic_2 = Fabricate(:topic, category: private_category, user: regular_user_2) 
      private_post_2 = Fabricate(:post, topic: private_topic_2, raw: "Support post FooBar B", user: regular_user_2)

      regular_topic = Fabricate(:topic, category: regular_category, user: regular_user_1) 
      regular_post = Fabricate(:post, topic: regular_topic, raw: "Regular post FooBar C", user: regular_user_1)

      regular_topic_2 = Fabricate(:topic, category: regular_category, user: regular_user_2) 
      regular_post_2 = Fabricate(:post, topic: regular_topic_2, raw: "Regular post FooBar D", user: regular_user_2)      

      expect(Search.execute("FooBar", guardian: Guardian.new(regular_user_1)).posts.length).to eq(3) # A, C, D
      expect(Search.execute("FooBar", guardian: Guardian.new(regular_user_2)).posts.length).to eq(3) # B, C, D
      expect(Search.execute("FooBar", guardian: Guardian.new(support_group_user.user)).posts.length).to eq(4) # A, B, C, D
    end

    it "allows admins to see everything" do
      admin_user = Fabricate(:admin)

      private_topic = Fabricate(:topic, category: private_category, user: regular_user_1) 
      private_post = Fabricate(:post, topic: private_topic, raw: "Support post FooBar A", user: regular_user_1)

      SiteSetting.private_topics_admin_sees_all = true
      expect(TopicQuery.new(admin_user, category: private_category.id).list_latest.topics.size).to eq(1)
      expect(Search.execute("FooBar", guardian: Guardian.new(admin_user)).posts.length).to eq(1)
      
      SiteSetting.private_topics_admin_sees_all = false
      expect(TopicQuery.new(admin_user, category: private_category.id).list_latest.topics.size).to eq(0)
      expect(Search.execute("FooBar", guardian: Guardian.new(admin_user)).posts.length).to eq(0)
    end
  end

end