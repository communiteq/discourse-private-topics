# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# Backlinks ("x links to this topic") come from `TopicLink.counts_for`, which only
# knows about category permissions. Since private topics live in *public*
# categories, core happily counts links to them - so the plugin filters the topic
# view's link counts with the `topic_view_link_counts` modifier.
describe TopicView do
  fab!(:author, :user)
  fab!(:viewer, :user)

  before { SiteSetting.private_topics_enabled = true }

  def links_of(topic, user)
    TopicView.new(topic.id, user).link_counts.values.flatten.map { |link| link[:url] }
  end

  def linked_topic_url(topic)
    "/t/#{topic.slug}/#{topic.id}"
  end

  it "drops links to a private topic the viewer may not see" do
    hidden = Fabricate(:topic, user: author, category: private_topics_category)
    source = Fabricate(:topic, user: viewer)
    PostCreator.create!(
      viewer,
      topic_id: source.id,
      raw: "linking to [the other topic](#{linked_topic_url(hidden)}) in passing",
    )

    expect(links_of(source, viewer)).not_to include(linked_topic_url(hidden))
  end

  it "also drops them for people who may see the topic" do
    # NOTE: this documents current behaviour. The modifier asks for
    # `get_filtered_category_ids(nil)` - an anonymous viewer, i.e. *every* private
    # category - instead of the person looking, so nobody keeps these links, not
    # even the author of the linked topic. Looks like an over-filter; the spec
    # will need updating if that is ever changed.
    hidden = Fabricate(:topic, user: author, category: private_topics_category)
    source = Fabricate(:topic, user: viewer)
    PostCreator.create!(
      viewer,
      topic_id: source.id,
      raw: "linking to [the other topic](#{linked_topic_url(hidden)}) in passing",
    )

    expect(links_of(source, author)).not_to include(linked_topic_url(hidden))
  end

  it "keeps them while the plugin is disabled" do
    hidden = Fabricate(:topic, user: author, category: private_topics_category)
    source = Fabricate(:topic, user: viewer)
    PostCreator.create!(
      viewer,
      topic_id: source.id,
      raw: "linking to [the other topic](#{linked_topic_url(hidden)}) in passing",
    )
    SiteSetting.private_topics_enabled = false

    expect(links_of(source, viewer)).to include(linked_topic_url(hidden))
  end
end
