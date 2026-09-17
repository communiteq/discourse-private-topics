# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# The contract everything else in the plugin relies on: the category custom field
# `private_topics_enabled` exists (whatever the value) on a category with private
# topics, and is gone when the box is unticked.
#
# This is the round trip the admin UI performs: the connectors in
# assets/javascripts/discourse/connectors/category-custom-security set the field to
# "t" when ticked and to "" when unticked, then the category is saved through the
# normal category endpoint. Discourse drops blank values rather than storing them,
# so unticking removes the row - which is why the rest of the plugin is allowed to
# test for the field's *existence* instead of comparing values.
describe CategoriesController do
  fab!(:admin, :admin)
  fab!(:category, :category)

  before { SiteSetting.private_topics_enabled = true }

  def update_custom_fields(value)
    sign_in(admin)
    put "/categories/#{category.id}.json", params: { custom_fields: { private_topics_enabled: value } }
  end

  def stored_field
    CategoryCustomField.find_by(category_id: category.id, name: "private_topics_enabled")
  end

  it "stores \"t\" when private topics are switched on" do
    update_custom_fields("t")

    expect(response.status).to eq(200)
    expect(stored_field&.value).to eq("t")
    expect(DiscoursePrivateTopics.get_filtered_category_ids(nil)).to eq([category.id])
  end

  it "removes the field again when the empty value is sent" do
    update_custom_fields("t")
    expect(stored_field).to be_present

    update_custom_fields("")

    expect(response.status).to eq(200)
    expect(stored_field).to be_nil
    expect(DiscoursePrivateTopics.get_filtered_category_ids(nil)).to eq([])
  end

  it "also stores the \"true\" shape, which the API is free to send" do
    update_custom_fields("true")

    expect(response.status).to eq(200)
    expect(stored_field&.value).to eq("true")
    expect(DiscoursePrivateTopics.get_filtered_category_ids(nil)).to eq([category.id])
  end
end
