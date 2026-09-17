# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# Topic lists are filtered by the `TopicQuery.add_custom_filter(:private_topics)`
# hook, which is the only thing that keeps private topics out of /latest and
# friends.
describe TopicQuery do
  fab!(:author, :user)
  fab!(:viewer, :user)
  fab!(:category) { private_topics_category }
  fab!(:authors_topic) { Fabricate(:topic, user: author, category: category) }
  fab!(:viewers_topic) { Fabricate(:topic, user: viewer, category: category) }
  fab!(:public_topic) { Fabricate(:topic, user: author) }

  before { SiteSetting.private_topics_enabled = true }

  def latest_for(user, **opts)
    TopicQuery.new(user, **opts).list_latest.topics
  end

  it "shows the viewer their own private topic, but not anybody else's" do
    topics = latest_for(viewer)

    expect(topics).to include(viewers_topic, public_topic)
    expect(topics).not_to include(authors_topic)
  end

  it "shows a topic whose author is in private_topics_permitted_groups" do
    SiteSetting.private_topics_permitted_groups = private_topics_group(author).id.to_s

    expect(latest_for(viewer)).to include(authors_topic)
  end

  it "shows everything to a member of the category's allowed groups" do
    member = Fabricate(:user)
    group = private_topics_group(member)
    allowed_category = private_topics_category(allowed_groups: [group])
    authors_topic.update!(category: allowed_category)
    viewers_topic.update!(category: allowed_category)

    expect(latest_for(member)).to include(authors_topic, viewers_topic)
  end

  it "shows everything to an admin by default" do
    expect(latest_for(Fabricate(:admin))).to include(authors_topic, viewers_topic)
  end

  it "hides them from an admin when private_topics_admin_sees_all is off" do
    SiteSetting.private_topics_admin_sees_all = false

    expect(latest_for(Fabricate(:admin))).not_to include(authors_topic)
  end

  it "hides them from anonymous visitors" do
    expect(latest_for(nil)).not_to include(authors_topic, viewers_topic)
  end

  it "filters the list of a single private category too" do
    topics = latest_for(viewer, category: category.id)

    expect(topics).to include(viewers_topic)
    expect(topics).not_to include(authors_topic)
  end

  it "does not filter anything while the plugin is disabled" do
    SiteSetting.private_topics_enabled = false

    expect(latest_for(viewer)).to include(authors_topic, viewers_topic)
  end
end
