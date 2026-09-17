# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# Profile -> Activity. `UserAction.stream` builds its SQL through the class method
# `apply_common_filters`, which the plugin patches on the singleton class.
describe UserAction do
  fab!(:author, :user)
  fab!(:viewer, :user)
  fab!(:private_category) { private_topics_category }
  fab!(:private_topic) { Fabricate(:topic, user: author, category: private_category) }
  fab!(:private_post) { Fabricate(:post, topic: private_topic, user: author) }
  fab!(:public_topic) { Fabricate(:topic, user: author) }
  fab!(:public_post) { Fabricate(:post, topic: public_topic, user: author) }

  before { SiteSetting.private_topics_enabled = true }

  def action_for(post)
    UserAction.log_action!(
      action_type: UserAction::NEW_TOPIC,
      user_id: author.id,
      acting_user_id: author.id,
      target_topic_id: post.topic_id,
      target_post_id: post.id,
    )
    UserAction.find_by(target_post_id: post.id)
  end

  # `UserAction.stream` returns rows, not records, so compare ids.
  def stream_ids_for(user)
    UserAction.stream(user_id: author.id, guardian: Guardian.new(user)).map(&:id)
  end

  it "keeps actions on private topics out of other people's activity" do
    private_action = action_for(private_post)
    public_action = action_for(public_post)

    ids = stream_ids_for(viewer)
    expect(ids).to include(public_action.id)
    expect(ids).not_to include(private_action.id)
  end

  it "keeps them in the author's own activity" do
    private_action = action_for(private_post)
    public_action = action_for(public_post)

    expect(stream_ids_for(author)).to include(private_action.id, public_action.id)
  end

  it "does not filter while the plugin is disabled" do
    private_action = action_for(private_post)
    SiteSetting.private_topics_enabled = false

    expect(stream_ids_for(viewer)).to include(private_action.id)
  end
end
