# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# The two helpers everything else in the plugin is built on.
describe DiscoursePrivateTopics do
  before { SiteSetting.private_topics_enabled = true }

  describe ".enabled_value?" do
    it "accepts every shape the custom field is written in" do
      expect(described_class.enabled_value?("t")).to eq(true)
      expect(described_class.enabled_value?("true")).to eq(true)
      expect(described_class.enabled_value?(true)).to eq(true)
    end

    it "treats anything else as off" do
      # "" is what the admin UI sends when unticking, but Discourse drops blank
      # values on save, so it never reaches the database. See
      # spec/requests/category_custom_fields_spec.rb for the round trip.
      expect(described_class.enabled_value?("")).to eq(false)
      expect(described_class.enabled_value?("f")).to eq(false)
      expect(described_class.enabled_value?(false)).to eq(false)
      expect(described_class.enabled_value?(nil)).to eq(false)
    end
  end

  describe ".get_filtered_category_ids" do
    it "returns the categories that have private topics enabled" do
      private_category = private_topics_category
      Fabricate(:category)

      expect(described_class.get_filtered_category_ids(Fabricate(:user))).to eq(
        [private_category.id],
      )
    end

    it "returns nothing while the plugin is disabled" do
      private_topics_category
      SiteSetting.private_topics_enabled = false

      expect(described_class.get_filtered_category_ids(Fabricate(:user))).to eq([])
    end

    it "excludes a category whose allowed groups the user belongs to" do
      group = Fabricate(:group)
      member = Fabricate(:user)
      group.add(member)
      outsider = Fabricate(:user)

      category = private_topics_category(allowed_groups: [group])

      expect(described_class.get_filtered_category_ids(member)).to eq([])
      expect(described_class.get_filtered_category_ids(outsider)).to eq([category.id])
    end

    it "only exempts the group listed on that category" do
      group = Fabricate(:group)
      member = Fabricate(:user)
      group.add(member)

      exempted = private_topics_category(allowed_groups: [group])
      other = private_topics_category

      expect(described_class.get_filtered_category_ids(member)).to eq([other.id])
      expect(described_class.get_filtered_category_ids(member)).not_to include(exempted.id)
    end

    it "returns every private category for an anonymous visitor" do
      exempted = private_topics_category(allowed_groups: [Fabricate(:group)])

      expect(described_class.get_filtered_category_ids(nil)).to eq([exempted.id])
    end
  end

  describe ".get_unfiltered_user_ids" do
    it "always contains the system user, even for an anonymous visitor" do
      expect(described_class.get_unfiltered_user_ids(nil)).to eq(
        [Discourse.system_user.id],
      )
    end

    it "contains the user itself" do
      user = Fabricate(:user)

      expect(described_class.get_unfiltered_user_ids(user)).to include(user.id)
    end

    it "contains the members of private_topics_permitted_groups" do
      member = Fabricate(:user)
      group = private_topics_group(member)
      SiteSetting.private_topics_permitted_groups = group.id.to_s

      expect(described_class.get_unfiltered_user_ids(nil)).to include(member.id)
    end

    it "does not contain an anonymous user" do
      # `User#anonymous?` also requires anonymous mode to be on.
      SiteSetting.allow_anonymous_mode = true
      anonymous = Fabricate(:anonymous)

      expect(described_class.get_unfiltered_user_ids(anonymous)).not_to include(
        anonymous.id,
      )
    end
  end
end
