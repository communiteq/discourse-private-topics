# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# `CategoryDetailedSerializer#include_displayable_topics?` hides a category's
# featured topic list from the "about" payload when that category has private
# topics.
#
# The custom field is a *text* column and its value is written in several shapes:
# "t" by this plugin's own admin UI, "true" by the API, the console or a fixture,
# and a real boolean if it was built in memory. The frontend accepts all of them
# (the connectors' `isEnabledValue`), and since this change so does the server, via
# `DiscoursePrivateTopics.enabled_value?`.
describe CategoryDetailedSerializer do
  fab!(:author, :user)
  fab!(:viewer, :user)

  before { SiteSetting.private_topics_enabled = true }

  def category_with_field(value)
    category = Fabricate(:category)
    if value
      CategoryCustomField.create!(
        category_id: category.id,
        name: "private_topics_enabled",
        value: value,
      )
    end
    Fabricate(:topic, category: category, user: author)
    category
  end

  def json_for(category, user)
    # The controller is what usually fills these in; the serializer only decides
    # whether to include the list. Preloading has to go through the real API, and
    # has to include every field the serializer may read, or HasCustomFields
    # raises rather than risk an N+1.
    category.displayable_topics = category.topics.limit(5)
    Category.preload_custom_fields([category], Site.preloaded_category_custom_fields)

    CategoryDetailedSerializer.new(
      category,
      scope: Guardian.new(user),
      root: false,
    ).as_json
  end

  it "hides the topic list of a category with private topics" do
    expect(json_for(category_with_field("t"), viewer)).not_to have_key(:topics)
  end

  it "hides it for the \"true\" shape as well" do
    expect(json_for(category_with_field("true"), viewer)).not_to have_key(:topics)
  end

  it "keeps the topic list of an ordinary category" do
    expect(json_for(category_with_field(nil), viewer)).to have_key(:topics)
  end

  it "keeps the topic list once the field is removed again" do
    # Unticking the box sends an empty value, which Discourse drops on save (see
    # spec/requests/category_custom_fields_spec.rb).
    category = category_with_field("t")
    CategoryCustomField.where(
      category_id: category.id,
      name: "private_topics_enabled",
    ).delete_all

    expect(json_for(category, viewer)).to have_key(:topics)
  end

  it "does not raise when custom fields were never preloaded" do
    category = category_with_field("t")
    category.displayable_topics = category.topics.limit(5)

    serializer =
      CategoryDetailedSerializer.new(category, scope: Guardian.new(viewer), root: false)

    expect(category.preloaded_custom_fields).to be_nil
    expect { serializer.include_displayable_topics? }.not_to raise_error
    # Nothing is known about the field, so it is treated as not private.
    expect(serializer.include_displayable_topics?).to eq(true)
  end

  it "does not consult the site setting, only the custom field" do
    category = category_with_field("t")
    SiteSetting.private_topics_enabled = false

    expect(json_for(category, viewer)).not_to have_key(:topics)
  end
end
